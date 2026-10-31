import Foundation
import OSLog
import RecallDomain

/// Upload steps in the iPhone's log (Console.app on the Mac, subsystem com.rachitthariani.recall); never the key.
let log = Logger(subsystem: "com.rachitthariani.recall", category: "upload")

/// Resumable upload: plan from the server (it reports parts it already has), parts on a background URLSession
/// (they keep going with the phone locked), then the manifest last and `complete`. Re-running is always safe.
public actor Uploader: ScanUploading {
    public static let sessionIdentifier = "com.rachitthariani.recall.upload"

    private let delegate = BackgroundDelegate()
    private let session: URLSession
    private var waiting: [String: CheckedContinuation<PartResult, Never>] = [:]
    private var progress: [String: UploadState] = [:]
    private var listeners: [@Sendable (String, UploadState) -> Void] = []

    public init() {
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.timeoutIntervalForRequest = 120
        session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        delegate.onFinish = { [weak self] key, result in Task { await self?.finished(key, result) } }
    }

    /// The app delegate hands over the system's completion handler when relaunched for background events.
    public nonisolated func setBackgroundCompletion(_ handler: @escaping @Sendable () -> Void) { delegate.backgroundCompletion = handler }

    public func observe(_ listener: @escaping @Sendable (String, UploadState) -> Void) { listeners.append(listener) }

    public func upload(scan scanId: String, home: String, room: String, episode: URL, manifest: Manifest,
                       server: any ScanServer) async {
        set(scanId, .preparing)
        var step = "Packing the scan"
        do {
            log.info("upload \(scanId, privacy: .public)")
            let archive = try EpisodeArchive.make(episode: episode)
            log.info("archive \(archive.size) bytes, \(archive.parts.count) parts")
            step = "Starting the upload"
            let plan = try await server.createScan(scan: scanId, home: home, room: room, size: archive.size,
                                                   sha256: archive.sha256, partSize: EpisodeArchive.partSize)
            guard plan.parts.count == archive.parts.count else { throw RecallError.server("The upload plan doesn't match the archive.") }
            var done = plan.parts.filter(\.received).count
            let total = archive.parts.count
            set(scanId, .uploading(fraction: Double(done) / Double(total)))
            step = "Sending the parts"
            for (planned, part) in zip(plan.parts, archive.parts) where !planned.received {
                var result = PartResult(status: 0, error: nil)
                for attempt in 1...3 where result.status != 200 {  // a failed part retries alone
                    result = await send(server.partRequest(path: planned.path, sha256: part.sha256), file: part.file,
                                        key: "\(scanId)#\(part.number)")
                    log.info("part \(part.number) attempt \(attempt): HTTP \(result.status) \(result.error ?? "", privacy: .public)")
                }
                guard result.status == 200 else {
                    let why = result.status > 0 ? "the Mac answered \(result.status)" : (result.error ?? "no answer")
                    throw RecallError.server("Part \(part.number) could not be sent (\(why)). Check the connection to the Mac.")
                }
                done += 1
                set(scanId, .uploading(fraction: Double(done) / Double(total)))
            }
            set(scanId, .finishing)
            step = "Sending the manifest"
            try await server.putManifest(scan: scanId, manifest: manifest)
            step = "Finishing the upload"
            let (status, detail) = try await server.complete(scan: scanId)
            log.info("complete: \(status.rawValue, privacy: .public)")
            set(scanId, status == .failed ? .failed(reason: detail ?? "The Mac refused the scan.") : .processing)
        } catch {
            let detail = "\(step) failed: \(UserMessage.explain(error))"
            log.error("\(detail, privacy: .public)")
            set(scanId, .failed(reason: detail))
        }
    }

    private func send(_ request: URLRequest, file: URL, key: String) async -> PartResult {
        await withCheckedContinuation { cont in
            waiting[key] = cont
            let task = session.uploadTask(with: request, fromFile: file)
            task.taskDescription = key
            task.resume()
        }
    }

    private func finished(_ key: String, _ result: PartResult) {
        waiting.removeValue(forKey: key)?.resume(returning: result)
    }

    private func set(_ scanId: String, _ p: UploadState) {
        progress[scanId] = p
        for l in listeners { l(scanId, p) }
    }
}

/// How one part's request ended: the HTTP status (0 when there was no answer) and the network error, if any.
struct PartResult: Sendable {
    let status: Int
    let error: String?
}

/// URLSession delegate for the background session; it only forwards completions to the actor.
final class BackgroundDelegate: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate, @unchecked Sendable {
    var onFinish: (@Sendable (String, PartResult) -> Void)?
    var backgroundCompletion: (@Sendable () -> Void)?

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let status = (task.response as? HTTPURLResponse)?.statusCode ?? 0
        onFinish?(task.taskDescription ?? "", PartResult(status: error == nil ? status : 0,
                                                          error: error.map { UserMessage.explain($0) }))
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let done = backgroundCompletion
        backgroundCompletion = nil
        DispatchQueue.main.async { done?() }
    }
}

/// Zips an episode for AirDrop or Files (the same archive an upload sends).
public struct ZipArchiver: EpisodeArchiving {
    public init() {}
    public func archive(episode: URL) -> URL? {
        guard FileManager.default.fileExists(atPath: episode.appending(path: "manifest.json").path) else { return nil }
        return try? EpisodeArchive.make(episode: episode).zip
    }
}

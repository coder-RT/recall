import Foundation
import OSLog
import RecallDomain
import RecallNetworking

/// Upload steps in the iPhone's log (Console.app on the Mac, subsystem com.rachitthariani.recall); never the key.
let log = Logger(subsystem: "com.rachitthariani.recall", category: "upload")

/// Where one scan's upload stands; shown on the Home screen and spoken on change.
public struct UploadProgress: Sendable, Equatable {
    public enum Phase: String, Sendable { case preparing, uploading, finishing, processing, processed, failed }
    public var phase: Phase
    public var partsDone: Int
    public var partsTotal: Int
    public var detail: String?

    public var fraction: Double { partsTotal == 0 ? 0 : Double(partsDone) / Double(partsTotal) }
}

/// Resumable upload: plan from the server (it reports parts it already has), parts on a background URLSession
/// (they keep going with the phone locked), then the manifest last and `complete`. Re-running is always safe.
public actor Uploader {
    public static let sessionIdentifier = "com.rachitthariani.recall.upload"

    private let delegate = BackgroundDelegate()
    private let session: URLSession
    private var waiting: [String: CheckedContinuation<PartResult, Never>] = [:]
    private var progress: [String: UploadProgress] = [:]
    private var listeners: [@Sendable (String, UploadProgress) -> Void] = []

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

    public func observe(_ listener: @escaping @Sendable (String, UploadProgress) -> Void) { listeners.append(listener) }

    public func current(_ scanId: String) -> UploadProgress? { progress[scanId] }

    public func upload(scanId: String, homeId: String, room: String, episode: URL, manifest: Manifest, api: RecallAPI) async {
        set(scanId, .init(phase: .preparing, partsDone: 0, partsTotal: 0))
        var step = "Packing the scan"
        do {
            log.info("upload \(scanId, privacy: .public) to \(api.baseURL.absoluteString, privacy: .public)")
            let archive = try EpisodeArchive.make(episode: episode)
            log.info("archive \(archive.size) bytes, \(archive.parts.count) parts")
            step = "Starting the upload"
            let plan = try await api.createScan(scanId: scanId, homeId: homeId, room: room, size: archive.size,
                                                sha256: archive.sha256, partSize: EpisodeArchive.partSize)
            guard plan.parts.count == archive.parts.count else { throw APIError.server("The upload plan doesn't match the archive.") }
            var done = plan.parts.filter(\.received).count
            set(scanId, .init(phase: .uploading, partsDone: done, partsTotal: archive.parts.count))
            step = "Sending the parts"
            for (planned, part) in zip(plan.parts, archive.parts) where !planned.received {
                var result = PartResult(status: 0, error: nil)
                for attempt in 1...3 where result.status != 200 {  // a failed part retries alone
                    result = await send(api.partRequest(path: planned.path, sha256: part.sha256), file: part.file,
                                        key: "\(scanId)#\(part.number)")
                    log.info("part \(part.number) attempt \(attempt): HTTP \(result.status) \(result.error ?? "", privacy: .public)")
                }
                guard result.status == 200 else {
                    let why = result.status > 0 ? "the Mac answered \(result.status)" : (result.error ?? "no answer")
                    throw APIError.server("Part \(part.number) could not be sent (\(why)). Check the connection to the Mac.")
                }
                done += 1
                set(scanId, .init(phase: .uploading, partsDone: done, partsTotal: archive.parts.count))
            }
            set(scanId, .init(phase: .finishing, partsDone: done, partsTotal: done))
            step = "Sending the manifest"
            _ = try await api.putManifest(scanId: scanId, manifest: manifest)
            step = "Finishing the upload"
            let (status, detail) = try await api.complete(scanId: scanId)
            log.info("complete: \(status.rawValue, privacy: .public)")
            set(scanId, .init(phase: status == .failed ? .failed : .processing, partsDone: done, partsTotal: done, detail: detail))
        } catch {
            let detail = "\(step) failed: \(APIError.explain(error))"
            log.error("\(detail, privacy: .public)")
            set(scanId, .init(phase: .failed, partsDone: progress[scanId]?.partsDone ?? 0,
                              partsTotal: progress[scanId]?.partsTotal ?? 0, detail: detail))
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

    private func set(_ scanId: String, _ p: UploadProgress) {
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
                                                          error: error.map { APIError.explain($0) }))
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let done = backgroundCompletion
        backgroundCompletion = nil
        DispatchQueue.main.async { done?() }
    }
}

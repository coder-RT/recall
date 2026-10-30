import Foundation
import RecallDomain
import RecallNetworking

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
    private var waiting: [String: CheckedContinuation<Bool, Never>] = [:]
    private var progress: [String: UploadProgress] = [:]
    private var listeners: [@Sendable (String, UploadProgress) -> Void] = []

    public init() {
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.timeoutIntervalForRequest = 120
        session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        delegate.onFinish = { [weak self] key, ok in Task { await self?.finished(key, ok: ok) } }
    }

    /// The app delegate hands over the system's completion handler when relaunched for background events.
    public nonisolated func setBackgroundCompletion(_ handler: @escaping @Sendable () -> Void) { delegate.backgroundCompletion = handler }

    public func observe(_ listener: @escaping @Sendable (String, UploadProgress) -> Void) { listeners.append(listener) }

    public func current(_ scanId: String) -> UploadProgress? { progress[scanId] }

    public func upload(scanId: String, homeId: String, room: String, episode: URL, manifest: Manifest, api: RecallAPI) async {
        set(scanId, .init(phase: .preparing, partsDone: 0, partsTotal: 0))
        do {
            let archive = try EpisodeArchive.make(episode: episode)
            let plan = try await api.createScan(scanId: scanId, homeId: homeId, room: room, size: archive.size,
                                                sha256: archive.sha256, partSize: EpisodeArchive.partSize)
            guard plan.parts.count == archive.parts.count else { throw APIError.server("The upload plan doesn't match the archive.") }
            var done = plan.parts.filter(\.received).count
            set(scanId, .init(phase: .uploading, partsDone: done, partsTotal: archive.parts.count))
            for (planned, part) in zip(plan.parts, archive.parts) where !planned.received {
                var ok = false
                for _ in 0..<3 where !ok {  // a failed part retries alone
                    ok = await send(api.partRequest(path: planned.path, sha256: part.sha256), file: part.file,
                                    key: "\(scanId)#\(part.number)")
                }
                guard ok else { throw APIError.server("Part \(part.number) could not be sent. Check the connection to the Mac.") }
                done += 1
                set(scanId, .init(phase: .uploading, partsDone: done, partsTotal: archive.parts.count))
            }
            set(scanId, .init(phase: .finishing, partsDone: done, partsTotal: done))
            _ = try await api.putManifest(scanId: scanId, manifest: manifest)
            let (status, detail) = try await api.complete(scanId: scanId)
            set(scanId, .init(phase: status == .failed ? .failed : .processing, partsDone: done, partsTotal: done, detail: detail))
        } catch {
            set(scanId, .init(phase: .failed, partsDone: progress[scanId]?.partsDone ?? 0,
                              partsTotal: progress[scanId]?.partsTotal ?? 0, detail: error.localizedDescription))
        }
    }

    private func send(_ request: URLRequest, file: URL, key: String) async -> Bool {
        await withCheckedContinuation { cont in
            waiting[key] = cont
            let task = session.uploadTask(with: request, fromFile: file)
            task.taskDescription = key
            task.resume()
        }
    }

    private func finished(_ key: String, ok: Bool) {
        waiting.removeValue(forKey: key)?.resume(returning: ok)
    }

    private func set(_ scanId: String, _ p: UploadProgress) {
        progress[scanId] = p
        for l in listeners { l(scanId, p) }
    }
}

/// URLSession delegate for the background session; it only forwards completions to the actor.
final class BackgroundDelegate: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate, @unchecked Sendable {
    var onFinish: (@Sendable (String, Bool) -> Void)?
    var backgroundCompletion: (@Sendable () -> Void)?

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let status = (task.response as? HTTPURLResponse)?.statusCode ?? 0
        onFinish?(task.taskDescription ?? "", error == nil && status == 200)
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let done = backgroundCompletion
        backgroundCompletion = nil
        DispatchQueue.main.async { done?() }
    }
}

import Foundation

/// Replies the Watch is waiting for from the iPhone, by request id. Each one is answered exactly once: by the
/// iPhone's reply, or by `WatchReply.phoneDidNotAnswer` when `PendingReplies.timeout` passes first. Whichever
/// comes second finds nothing to take and is dropped, so a late reply can't speak over a newer question.
public final class PendingReplies<Handler>: @unchecked Sendable {
    /// How long the Watch waits for the iPhone before saying so (a spoken question goes through the Guide: a few
    /// seconds normally, never this long).
    public static var timeout: Duration { .seconds(25) }

    private var handlers: [String: Handler] = [:]
    private let lock = NSLock()

    public init() {}

    public func put(_ id: String, _ handler: Handler) {
        lock.withLock { handlers[id] = handler }
    }

    /// The handler for `id`, removed so nothing can call it again; nil if it was already answered.
    public func take(_ id: String) -> Handler? {
        lock.withLock { handlers.removeValue(forKey: id) }
    }

    public var count: Int { lock.withLock { handlers.count } }
}

public extension WatchReply {
    static let phoneDidNotAnswer = WatchReply(say: "Your iPhone didn't answer. Try again with it nearby.")
}

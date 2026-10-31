import Foundation

/// One request at a time for the same data: callers that arrive while it runs wait for the same answer. The work
/// runs in its own task, so a screen that goes away (switching tabs cancels its `.task`) doesn't cancel the request
/// for everyone else, and nobody sees "cancelled".
@MainActor
public final class SingleFlight<Value: Sendable> {
    private var running: Task<Value, Error>?

    public init() {}

    public func run(_ work: @escaping @MainActor () async throws -> Value) async throws -> Value {
        if let running { return try await running.value }
        let task = Task { try await work() }
        running = task
        defer { if running == task { running = nil } }
        return try await task.value
    }
}

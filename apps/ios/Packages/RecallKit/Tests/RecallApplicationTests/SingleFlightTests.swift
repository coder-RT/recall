import Foundation
import RecallDomain
import Testing
@testable import RecallApplication

@Suite("One request at a time") @MainActor
struct SingleFlightTests {
    @MainActor final class Counter { var calls = 0 }

    @Test func callersWhileItRunsShareOneRequest() async throws {
        let flight = SingleFlight<Int>()
        let n = Counter()
        let a = Task { try await flight.run { n.calls += 1; try await Task.sleep(for: .milliseconds(50)); return n.calls } }
        try await Task.sleep(for: .milliseconds(10))
        let b = Task { try await flight.run { n.calls += 1; return -1 } }
        let (x, y) = try await (a.value, b.value)
        #expect(n.calls == 1 && x == 1 && y == 1)
        #expect(try await flight.run { n.calls += 1; return n.calls } == 2)  // a later call runs again
    }

    @Test func aScreenLeavingDoesNotCancelTheRequestForOthers() async throws {
        let flight = SingleFlight<String>()
        let leaving = Task { try await flight.run { try await Task.sleep(for: .milliseconds(80)); return "things" } }
        try await Task.sleep(for: .milliseconds(10))
        leaving.cancel()  // switching tabs cancels that screen's task
        let staying = try await flight.run { "a second request" }
        #expect(staying == "things")  // the same request finished, not cancelled
    }

    @Test func failuresReachEveryCallerAndTheNextCallTriesAgain() async {
        let flight = SingleFlight<Int>()
        await #expect(throws: URLError.self) { try await flight.run { throw URLError(.timedOut) } }
        #expect((try? await flight.run { 7 }) == 7)
    }

    @Test func cancellationIsNotAnErrorToShow() {
        #expect(UserMessage.isCancellation(URLError(.cancelled)))
        #expect(UserMessage.isCancellation(CancellationError()))
        #expect(!UserMessage.isCancellation(URLError(.timedOut)))
        #expect(!UserMessage.isCancellation(RecallError.status(401)))
    }
}

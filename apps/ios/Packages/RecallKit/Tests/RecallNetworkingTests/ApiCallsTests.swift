import Foundation
import HTTPTypes
import OpenAPIRuntime
import RecallDomain
import Testing
@testable import RecallNetworking

/// Answers with one status and body, and remembers what was asked (method and path), like a Mac would.
final class StubTransport: ClientTransport, @unchecked Sendable {
    let status: HTTPResponse.Status
    let body: String?
    private(set) var requests: [(method: HTTPRequest.Method, path: String)] = []

    init(_ status: HTTPResponse.Status, _ body: String? = nil) { self.status = status; self.body = body }

    func send(_ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String) async throws -> (HTTPResponse, HTTPBody?) {
        requests.append((request.method, request.path ?? ""))
        let headers: HTTPFields = self.body == nil ? [:] : [.contentType: "application/json"]
        return (HTTPResponse(status: status, headerFields: headers), self.body.map { HTTPBody($0) })
    }
}

private func api(_ t: StubTransport) -> RecallAPI {
    RecallAPI(baseURL: URL(string: "http://mac.local:8000")!, deviceKey: "k", transport: t)
}

@Suite("Calls to the Mac")
struct ApiCallsTests {
    @Test func eraseSendsDeleteAndAcceptsGoneAlready() async throws {
        let done = StubTransport(.noContent)
        try await api(done).erase(scan: "s1")
        #expect(done.requests.first?.method == .delete && done.requests.first?.path == "/scans/s1")
        try await api(StubTransport(.notFound, #"{"error": "not_found", "detail": "No such scan."}"#)).erase(scan: "s1")
    }

    @Test func eraseWhileProcessingSaysWhatTheMacSays() async throws {
        let busy = StubTransport(.conflict, #"{"error": "busy", "detail": "The Mac is processing this scan; erase it when it has finished."}"#)
        await #expect(throws: RecallError.server("The Mac is processing this scan; erase it when it has finished.")) {
            try await api(busy).erase(scan: "s1")
        }
    }

    @Test func privacyDecodes() async throws {
        let json = """
        {"stored_on": "This Mac", "robot_access": false, "audit_days": 90, "sent": [
          {"what": "Scan photos", "to": "Meta Model API: SAM 3.1", "when": "While this Mac processes a scan", "on_this_mac": false},
          {"what": "Your question as text", "to": "Nobody: Muse Glimmer runs on this Mac (LM Studio)", "when": "Each time you ask", "on_this_mac": true},
          {"what": "One photo from the camera", "to": "Meta Model API: SAM 3.1", "when": "When you check on arrival"}]}
        """
        let p = try await api(StubTransport(.ok, json)).privacy()
        #expect(p.storedOn == "This Mac" && !p.robotAccess && p.auditDays == 90)
        #expect(p.sent.map(\.onThisMac) == [false, true, false])
        #expect(p.robotLine == "Robot Access is off: robots get nothing.")
    }

    @Test func anAnswerDecodesAndAnUnavailableGuideSaysSo() async throws {
        let json = #"{"text": "Your keys are on the desk.", "grounded": true, "object_id": "obj_1", "tool_calls": 1, "model": "m", "latency_ms": 900}"#
        let a = try await api(StubTransport(.ok, json)).ask(home: "flat", question: "Where are my keys?")
        #expect(a.text == "Your keys are on the desk." && a.thingId == "obj_1" && a.grounded)
        let down = StubTransport(.serviceUnavailable, #"{"error": "model_unavailable", "detail": "x"}"#)
        await #expect(throws: RecallError.server("The Guide isn't available right now. Try again in a moment.")) {
            _ = try await api(down).ask(home: "flat", question: "Where are my keys?")
        }
    }
}

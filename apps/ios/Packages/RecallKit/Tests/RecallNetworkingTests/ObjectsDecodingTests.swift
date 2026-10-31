import Foundation
import HTTPTypes
import OpenAPIRuntime
import RecallDomain
import Testing
@testable import RecallNetworking

/// Answers every request with one fixed JSON body, like the Mac would.
struct FixedTransport: ClientTransport {
    let body: String
    func send(_ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String) async throws -> (HTTPResponse, HTTPBody?) {
        (HTTPResponse(status: .ok, headerFields: [.contentType: "application/json"]), HTTPBody(self.body))
    }
}

/// The shape GET /homes/{id}/objects returns (FastAPI: fractional seconds, nulls for unset fields).
let objectsJSON = """
[{"object_id": "obj_3076e9a6796e4fb4", "label": "bag", "position": [-0.444, 0.794, 0.401], "height_band": "knee",
  "room": "Living room", "landmark": "desk", "relation": "near", "shelf_level": null,
  "seen_at": "2026-10-30T03:21:01.123632Z", "confidence": 0.621, "stale": false, "color": "grey",
  "size_m": [0.128, 0.113, 0.277],
  "corrections": {"name": null, "color": null, "height_m": null, "note": null, "confirmed": false},
  "needs_review": true},
 {"object_id": "obj_1", "label": "keys", "position": [0, 0, 0.71], "height_band": "waist", "room": null,
  "landmark": null, "relation": null, "shelf_level": null, "seen_at": "2026-10-30T03:21:01Z", "confidence": 1.0,
  "stale": false, "color": null, "size_m": null,
  "corrections": {"name": "spare keys", "color": "red", "height_m": 0.75, "note": "in the bowl", "confirmed": true},
  "needs_review": false}]
"""

@Test func objectListFromTheMacDecodes() async throws {
    let api = RecallAPI(baseURL: URL(string: "http://mac.local:8000")!, deviceKey: "k",
                        transport: FixedTransport(body: objectsJSON))
    let objects = try await api.things(home: "flat")
    #expect(objects.count == 2)
    #expect(objects[0].title == "grey bag" && objects[0].needsReview && objects[0].place == "near the desk, knee height")
    #expect(objects[1].title == "spare keys" && objects[1].confirmed && objects[1].userHeightM == 0.75)
    #expect(objects[1].place == "in the room, waist height")
}

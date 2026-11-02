import Foundation
import RecallDomain
import Testing

/// The phone's text limits are the Mac's: read from the openapi.json the client is generated from.
@Suite("Text limits match the Mac's spec")
struct LimitsMatchTheSpecTests {
    private func schema(_ name: String) throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "Sources/RecallNetworking/openapi.json")
        let spec = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let schemas = try #require((spec["components"] as? [String: Any])?["schemas"] as? [String: Any])
        return try #require((schemas[name] as? [String: Any])?["properties"] as? [String: Any])
    }

    private func maxLength(_ schema: [String: Any], _ field: String) -> Int? {
        (schema[field] as? [String: Any])?["maxLength"] as? Int
    }

    @Test func everyLimitIsTheMacs() throws {
        #expect(maxLength(try schema("AskRequest"), "question") == TextInput.question)
        #expect(maxLength(try schema("ScanCreate"), "room") == TextInput.roomName)
        #expect(maxLength(try schema("ObjectCorrection"), "name") == TextInput.thingName)
        #expect(maxLength(try schema("ObjectCorrection"), "note") == TextInput.note)
        let homePattern = (try schema("AskRequest")["home_id"] as? [String: Any])?["pattern"] as? String
        #expect(homePattern == "^[a-z0-9-]{1,\(TextInput.homeId)}$")
    }
}

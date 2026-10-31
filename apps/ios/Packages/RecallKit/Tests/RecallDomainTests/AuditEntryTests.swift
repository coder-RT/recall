import Foundation
import Testing
@testable import RecallDomain

@Suite("Robot activity")
struct AuditEntryTests {
    func entry(_ action: String, _ actor: String, _ outcome: String = "ok", _ detail: [String: String] = [:]) -> AuditEntry {
        AuditEntry(id: "e", at: Date(timeIntervalSince1970: 0), actor: actor, action: action, outcome: outcome, detail: detail)
    }

    @Test func eachEntryReadsAsASentence() {
        #expect(entry("robot_access.changed", "owner", "ok", ["on": "true"]).summary == "You turned robot access on")
        #expect(entry("robot_export.read", "robot", "ok", ["room": "Living room"]).summary == "A robot read the map of Living room")
        #expect(entry("robot_export.read", "owner").summary == "You exported the robot map")
        #expect(entry("robot_export.read", "robot", "refused").summary == "A robot tried to read the map: refused, robot access was off")
        #expect(entry("home_memory.query", "robot", "ok", ["asked": "keys", "found": "true"]).summary == "A robot asked for keys: answered")
        #expect(entry("home_memory.query", "robot", "ok", ["asked": "passport", "found": "false"]).summary
                == "A robot asked for passport: not found")
        #expect(entry("home_memory.query", "robot", "refused", ["screen": "injection"]).summary
                == "A robot sent a name that looked like an instruction: refused")
        #expect(entry("home_memory.query", "robot", "refused", ["screen": "structure"]).summary
                == "A robot sent something other than an object name: refused")
        #expect(entry("home_memory.query", "robot", "refused", ["screen": "unavailable"]).summary
                == "A robot asked, but the safety check couldn't run: refused")
        #expect(entry("scan.erased", "owner", "ok", ["room": "Living room"]).summary
                == "You erased a scan of Living room from the Mac")
        #expect(entry("auth.refused", "unknown", "refused", ["why": "wrong key", "path": "/a2a/home-memory"]).summary
                == "Refused: wrong key (/a2a/home-memory)")
    }

    @Test func onlyRobotMattersAreShown() {
        #expect(entry("home_memory.query", "robot").isAboutRobots)
        #expect(!entry("object.corrected", "owner").isAboutRobots)
        #expect(!entry("scan.ingested", "pipeline").isAboutRobots)
    }
}

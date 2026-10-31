import Foundation
import RecallDomain

/// Made-up things for the UI tests (launch argument `-UITestSampleThings`), so Find and Found can be checked in the
/// simulator, which has no Mac paired. Only the tests pass the argument; the app never shows these otherwise.
enum UITestSamples {
    static let enabled = ProcessInfo.processInfo.arguments.contains("-UITestSampleThings")

    static let things: [Thing] = {
        let at = Date(timeIntervalSince1970: 1_800_000_000)
        func t(_ id: String, _ label: String, _ color: String?, room: String?, landmark: String?, band: String = "waist",
               relation: String = "near", sure: Bool = true) -> Thing {
            Thing(id: id, label: label, color: color, heightM: 0.8, heightBand: band, landmark: landmark,
                  relation: relation, room: room, confidence: sure ? 0.85 : 0.6, needsReview: !sure, seenAt: at)
        }
        return [
            t("s1", "keys", "beige", room: "Living room", landmark: "desk"),
            t("s2", "bag", "grey", room: "Living room", landmark: "desk", band: "knee", sure: false),
            t("s3", "book", "red", room: "Living room", landmark: "shelf", relation: "on", sure: false),
            t("s4", "bottle", "grey", room: "Living room", landmark: nil, band: "floor"),
            t("s5", "mug", "white", room: "Kitchen", landmark: "counter", relation: "on"),
            t("s6", "wallet", "brown", room: "Kitchen", landmark: "counter", relation: "on"),
        ]
    }()

    /// A room's first scan and its rescan, with what the rescan found different.
    static let scans: [Scan] = {
        let first = Scan(id: "scan-1", room: "Living room", createdAt: Date(timeIntervalSince1970: 1_800_000_000),
                         grade: .usable, directions: 10, frames: 56, state: .processed)
        var again = Scan(id: "scan-2", room: "Living room", createdAt: Date(timeIntervalSince1970: 1_800_090_000),
                         grade: .good, directions: 12, frames: 64, state: .processed, alignedTo: "scan-1")
        again.changes = [
            ScanChange(kind: .moved, objectId: "s1", label: "keys", color: "beige", from: "near the desk", to: "on the shelf"),
            ScanChange(kind: .new, objectId: "s7", label: "mug", color: "white", to: "on the desk"),
            ScanChange(kind: .gone, objectId: "s2", label: "bag", color: "grey", from: "near the desk"),
        ]
        return [again, first]
    }()

    /// Robot Access for the UI tests: kept in memory, with a small made-up map.
    final class Sharing: RobotSharing, @unchecked Sendable {
        private var on = false
        func robotAccess() async throws -> RobotAccessStatus { status }
        func setRobotAccess(_ on: Bool) async throws -> RobotAccessStatus { self.on = on; return status }
        func robotMap(home: String) async throws -> RobotMapPackage {
            let free = [UInt8](repeating: 254, count: 40)
            var shades = [UInt8](repeating: 0, count: 10) + free + [UInt8](repeating: 128, count: 10)
            shades[25] = 0
            let map = RobotMap(width: 10, height: 6, resolution: 0.25, origin: (0, 0), shades: shades)
            return RobotMapPackage(room: "Living room", map: map,
                                   things: [.init(label: "keys", color: "beige", x: 1.0, y: 0.6)],
                                   files: ["map.yaml": Data("image: map.pgm\n".utf8)])
        }
        private var status: RobotAccessStatus {
            RobotAccessStatus(on: on, a2aURL: "http://mac.local:8000/a2a/home-memory",
                              agentCardURL: "http://mac.local:8000/a2a/home-memory/.well-known/agent-card.json",
                              exportURL: "http://mac.local:8000/homes/flat/robot-export")
        }
    }
}

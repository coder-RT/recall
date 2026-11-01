import Foundation
import Observation
import RecallDomain

/// Made-up things for the UI tests (launch argument `-UITestSampleThings`), so Find and Found can be checked in the
/// simulator, which has no Mac paired. Only the tests pass the argument; the app never shows these otherwise.
enum UITestSamples {
    static let enabled = ProcessInfo.processInfo.arguments.contains("-UITestSampleThings")
    /// The usability tests read what was spoken from one invisible element ("spoken-log").
    static let logSpeech = ProcessInfo.processInfo.arguments.contains("-UITestSpokenLog")

    /// A paired-looking Mac, whatever an earlier run left in the simulator's settings or Keychain (the key outlives an
    /// uninstall there), so every screen starts the same and shows no setup notice. Nothing listens on port 9, so a
    /// request that slips past the samples fails at once instead of reaching a real Mac. Changes last until the app quits.
    final class Connections: ConnectionStore, @unchecked Sendable {
        private var connection = Connection(address: "127.0.0.1:9", key: "ui-test-sample-key", home: "flat")
        func load() -> Connection { connection }
        func save(_ connection: Connection) { self.connection = connection }
    }

    /// Every line spoken since launch, newest last.
    @MainActor @Observable final class SpokenLog {
        static let shared = SpokenLog()
        var lines: [String] = []
    }

    /// The Guide for the UI tests: answers like the recorded Muse Spark Open replies, about the sample things.
    struct Guide: GuideService {
        func ask(home: String, question: String, about: String?) async throws -> Answer {
            try await Task.sleep(for: .milliseconds(300))  // the acknowledgement is spoken first, as on the Mac
            let q = question.lowercased()
            if q.contains("key") {
                return Answer(text: "Your keys are near the desk in the Living room, at waist height.", thingId: "s1",
                              grounded: true, answerId: "ans-sample")
            }
            if q.contains("wallet") {
                return Answer(text: "Your brown wallet is on the counter in the Kitchen, at waist height.", thingId: "s6",
                              grounded: true)
            }
            return Answer(text: "I haven't seen that yet. Scan the room it might be in, and I'll remember it.",
                          thingId: nil, grounded: true)
        }
        func route(home: String, to thing: String, from pose: Pose, tracking: TrackingState) async throws -> Route {
            throw RecallError.server("Directions need the camera, which the UI tests don't have.")
        }
        func verify(session: String, frame: ArrivalFrame) async throws -> ArrivalCheck {
            throw RecallError.server("The arrival check needs the camera, which the UI tests don't have.")
        }
    }

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

    /// An answer's evidence for the UI tests (as the Mac returns it for the sample keys; no camera view).
    struct EvidenceSample: EvidenceSource {
        func evidence(answer: String) async throws -> Evidence {
            Evidence(question: "Where are my keys?", text: "Your keys are near the desk in the Living room, at waist height.",
                     model: "meta-models/muse-spark-open-1026", latencyMs: 2300, tools: ["find_object"], sightings: [
                        Sighting(observationId: "ob1", label: "keys", room: "Living room",
                                 seenAt: Date(timeIntervalSince1970: 1_800_000_000), confidence: 0.92, current: true,
                                 segmenter: "sam-3.1", reconstructor: "map-anything-apache@00f9c24"),
                     ])
        }
        func crop(path: String) async throws -> Data { throw RecallError.status(404) }
    }

    /// The Mac's privacy facts for the UI tests (as a Mac with the default settings reports them).
    struct Privacy: PrivacySource {
        func privacy() async throws -> PrivacyStatus {
            PrivacyStatus(storedOn: "This Mac", sent: [
                DataFlow(what: "Scan photos, about 50 per room (no depth, no sound)", to: "Meta Model API: SAM 3.1",
                         when: "While this Mac processes a scan, to find furniture and things"),
                DataFlow(what: "Your question as text", to: "Baseten: Muse Spark Open", when: "Each time you ask"),
            ], robotAccess: false, auditDays: 90)
        }
    }

    /// A robot package for the UI tests: a few bytes standing in for the Mac's .zip.
    struct Packages: RobotPackages {
        func robotPackage(home: String, room: String?) async throws -> Data { Data("sample robot package".utf8) }
    }

    /// The trust level for the UI tests: Balanced, kept in memory.
    final class Trust: TrustSettings, @unchecked Sendable {
        private var level = TrustLevel.balanced
        func trustLevel() async throws -> TrustLevel { level }
        func setTrustLevel(_ level: TrustLevel) async throws -> TrustLevel { self.level = level; return level }
    }

    /// Robot Access for the UI tests: kept in memory, with a small made-up map.
    final class Sharing: RobotSharing, @unchecked Sendable {
        private var on = false
        func robotAccess() async throws -> RobotAccessStatus { status }
        func setRobotAccess(_ on: Bool) async throws -> RobotAccessStatus { self.on = on; return status }
        func activity(limit: Int) async throws -> [AuditEntry] {
            let now = Date()
            var out = [AuditEntry(id: "a1", at: now.addingTimeInterval(-120), actor: "robot", action: "home_memory.query",
                                  outcome: "ok", detail: ["asked": "keys", "found": "true"]),
                       AuditEntry(id: "a2", at: now.addingTimeInterval(-3600), actor: "unknown", action: "auth.refused",
                                  outcome: "refused", detail: ["why": "wrong key", "path": "/a2a/home-memory"])]
            if on { out.insert(AuditEntry(id: "a0", at: now, actor: "owner", action: "robot_access.changed", outcome: "ok",
                                          detail: ["on": "true"]), at: 0) }
            return out
        }
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

    /// Room maps for the UI tests: a small made-up map for each sample room, its things as dots.
    struct Maps: RoomMaps {
        func roomMap(home: String, room: String) async throws -> RobotMapPackage {
            guard room == "Living room" || room == "Kitchen" else { throw RecallError.status(404) }
            // a 10 x 6 room: a wall along the top, unseen along the bottom, one piece of furniture
            var shades = [UInt8](repeating: 0, count: 10) + [UInt8](repeating: 254, count: 40) + [UInt8](repeating: 128, count: 10)
            shades[room == "Kitchen" ? 22 : 25] = 0
            let map = RobotMap(width: 10, height: 6, resolution: 0.25, origin: (0, 0), shades: shades)
            let here = things.filter { $0.room == room }
            let dots = here.enumerated().map { i, t in
                RobotMapPackage.Thing(label: t.label, color: t.color, x: 0.4 + Double(i) * 0.5, y: 0.6)
            }
            return RobotMapPackage(room: room, map: map, things: dots, files: [:])
        }
    }
}

import Foundation
import Testing
@testable import RecallDomain

@Suite("Connection")
struct ConnectionTests {
    @Test func addressIsCleanedAndCompleted() {
        #expect(Connection(address: " 192.168.1.20:8000\n", key: "k", home: "").url?.absoluteString == "http://192.168.1.20:8000")
        #expect(Connection(address: "https://mac.ts.net:8445", key: "k", home: "").url?.host == "mac.ts.net")
        #expect(Connection(address: "ftp://x", key: "k", home: "").url == nil)
    }

    @Test func saysWhatIsMissing() {
        #expect(Connection(address: "", key: "", home: "").issue == .nothingSet)
        #expect(Connection(address: "::", key: "k", home: "").issue == .badAddress)
        #expect(Connection(address: "mac:8000", key: "  ", home: "").issue == .noKey)
        #expect(Connection(address: "mac:8000", key: "k", home: "").issue == nil)
    }

    @Test func keySummaryAndDefaultHome() {
        let c = Connection(address: "", key: " abcd6GSO\n", home: " ")
        #expect(c.keySummary == "8 characters, ending in 6 G S O.")
        #expect(c.homeId == "flat")
    }

    @Test func pairingLink() throws {
        let link = try #require(try PairingLink(URL(string: "recall://pair?url=https://mac:8445&key=abc&home=loft")!))
        #expect(link.address == "https://mac:8445" && link.key == "abc" && link.home == "loft")
        #expect(try PairingLink(URL(string: "https://example.com")!) == nil)
        #expect(throws: RecallError.incompletePairing) { try PairingLink(URL(string: "recall://pair?url=x")!) }
    }
}

@Suite("Scan")
struct ScanTests {
    let scan = Scan(id: "s1", room: "Kitchen", createdAt: Date(timeIntervalSince1970: 0), grade: .good, directions: 10, frames: 50)

    @Test func uploadStateMovesAndReportsStageChanges() {
        var s = scan
        #expect(s.canUpload)
        let started = s.apply(.uploading(fraction: 0.2))
        let progressed = s.apply(.uploading(fraction: 0.6))  // progress, not a new stage
        #expect(started && !progressed && !s.canUpload)
        let failed = s.apply(.failed(reason: "no answer"))
        #expect(failed && s.canUpload)
    }

    @Test func readsTheScanListOlderBuildsWrote() throws {
        let old = #"[{"id":"a","room":"Living room","createdAt":"2026-10-30T03:59:00Z","grade":"usable","directions":10,"#
            + #""frames":56,"uploadPhase":"processed"},{"id":"b","room":"Hall","createdAt":"2026-10-30T04:00:00Z","#
            + #""grade":"good","directions":12,"frames":40,"uploadPhase":"failed","uploadDetail":"Part 2 failed"}]"#
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        let scans = try d.decode([Scan].self, from: Data(old.utf8))
        #expect(scans[0].state == .processed)
        #expect(scans[1].state == .failed(reason: "Part 2 failed"))
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        #expect(try d.decode([Scan].self, from: e.encode(scans)) == scans)  // and writes the same shape back
    }
}

@Suite("Thing")
struct ThingTests {
    let bag = Thing(id: "1", label: "bag", color: "grey", heightM: 0.4, heightBand: "knee", landmark: "desk",
                    relation: "near", confidence: 0.62, needsReview: true, seenAt: .now)

    @Test func wordsForLists() {
        #expect(bag.title == "grey bag")
        #expect(bag.place == "near the desk, knee height")
        #expect(bag.certainty == "Unsure, 62 percent sure")
    }

    @Test func correctionFromTheForm() {
        let c = Correction.from(name: "  work bag ", color: "", heightCm: nil, note: "")
        #expect(c.name == .set("work bag") && c.color == .clear && c.heightM == .clear && c.note == .clear)
        #expect(c.confirmed == true)
        #expect(Correction.from(name: "", color: "red", heightCm: 75, note: "x").heightM == .set(0.75))
    }
}

@Suite("Guidance values")
struct GuidanceValueTests {
    @Test func poseGivesFloorPositionAndFacing() {
        let identity = Pose.identity
        #expect(identity.position == SIMD2(0, 0))
        #expect(identity.forward == SIMD2(0, -1))  // ARKit cameras look along −z
    }

    @Test func cueThrottleSpeaksChangesOnly() {
        var t = CueThrottle(reminderSeconds: 6)
        let start = Date(timeIntervalSince1970: 0)
        let cue = { (clock: Int, m: Double) in RouteFollower.Cue(clock: clock, metres: m, arrived: false, waypoint: 1) }
        let said = [
            t.shouldSay(cue(12, 3), at: start),
            t.shouldSay(cue(12, 2.6), at: start.addingTimeInterval(1)),  // same way, under a metre closer
            t.shouldSay(cue(2, 2.5), at: start.addingTimeInterval(2)),  // new direction
            t.shouldSay(cue(2, 2.4), at: start.addingTimeInterval(9)),  // reminder
        ]
        #expect(said == [true, false, true, true])
    }

    @Test func followerMeasuresHowFarOffTheRoute() {
        var f = RouteFollower(waypoints: [[0, 0], [0, -4]])
        let near = f.update(position: [0.2, -1], forward: [0, -1])?.offRouteMetres ?? 0
        let away = f.update(position: [2, -2], forward: [0, -1])?.offRouteMetres ?? 0
        #expect(near < 0.25 && away > 1.9)
    }

    @Test func errorsReadAsSentences() {
        #expect(UserMessage.explain(RecallError.status(401)) == "The device key is wrong. Check it in Settings.")
        #expect(UserMessage.explain(URLError(.cannotFindHost)).hasPrefix("The address can't be found."))
    }
}

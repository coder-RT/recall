import Foundation
import Testing
@testable import RecallDomain

private func c(_ kind: ScanChange.Kind, _ label: String, color: String? = nil, name: String? = nil, from: String? = nil,
               to: String? = nil) -> ScanChange {
    ScanChange(kind: kind, objectId: "\(kind)-\(label)", label: label, name: name, color: color, from: from, to: to)
}

@Suite("What changed")
struct ChangeSummaryTests {
    @Test func movedNewAndGoneInOneBreath() {
        let say = ChangeSummary.say(room: "Living room", changes: [
            c(.moved, "keys", color: "beige", from: "near the desk", to: "on the shelf"),
            c(.new, "mug", color: "white", to: "on the desk"), c(.new, "apple"),
            c(.gone, "bag", name: "Mum's purse", from: "near the desk"),
        ])
        #expect(say == "Living room is ready. 4 changes: Your beige keys moved from near the desk to on the shelf. "
                + "New: a white mug and an apple. Gone: your Mum's purse.")
    }

    @Test func longListsAreCounted() {
        let new = ["mug", "book", "bottle", "phone", "charger"].map { c(.new, $0) }
        #expect(ChangeSummary.say(room: "Hall", changes: new) == "Hall is ready. 5 changes: New: a mug, a book, a bottle and 2 more.")
        #expect(ChangeSummary.say(room: "Hall", changes: [c(.gone, "keys")]) == "Hall is ready. 1 change: Gone: your keys.")
        #expect(ChangeSummary.say(room: "Hall", changes: []) == "Hall is ready. Nothing has moved since the last scan.")
    }

    @Test func eachChangeAsALineAndItsIcon() {
        let moved = c(.moved, "bag", color: "grey", from: "near the desk", to: "on the cabinet")
        #expect(moved.line == "Moved from near the desk to on the cabinet")
        #expect(moved.places == "near the desk → on the cabinet")
        #expect(c(.gone, "book", from: "on the shelf").places == "was on the shelf")
        #expect(moved.title == "grey bag" && moved.thingKind == .handbag)
        #expect(c(.new, "mug", to: "on the desk").line == "New, on the desk")
        #expect(c(.gone, "book", from: "on the shelf").line == "Gone from on the shelf")
    }

    @Test func aScanKeepsItsChangesOnThePhone() throws {
        var scan = Scan(id: "r", room: "Living room", createdAt: Date(timeIntervalSince1970: 0), grade: .good,
                        directions: 10, frames: 40, state: .processed, alignedTo: "a")
        scan.changes = [c(.moved, "keys", from: "near the desk", to: "on the shelf")]
        let back = try JSONDecoder().decode(Scan.self, from: JSONEncoder().encode(scan))
        #expect(back == scan && back.showsChanges)
        // a first scan doesn't show the card; scans saved by older builds still load
        let first = Scan(id: "f", room: "Hall", createdAt: Date(timeIntervalSince1970: 0), grade: .good, directions: 10,
                         frames: 40, state: .processed)
        #expect(!first.showsChanges)
        let old = #"{"id":"o","room":"Hall","createdAt":0,"grade":"good","directions":9,"frames":30,"uploadPhase":"processed"}"#
        let loaded = try JSONDecoder().decode(Scan.self, from: Data(old.utf8))
        #expect(loaded.changes.isEmpty && loaded.alignedTo == nil && !loaded.fresh)
    }

    @Test func aRescanFirstRecognisesTheRoom() {
        var guide = ScanGuide(recognising: true)
        #expect(guide.step == .recognise)
        let p = ScanGuide.Progress(elapsed: 30, directions: 12, walls: 12, floorSeenM2: 9, areaWalkedM2: 9, walkedM: 9,
                                   fromStartM: 0, map: .mapped)
        #expect(guide.update(p) == nil)  // nothing advances until the room is recognised
        #expect(guide.endRecognise(recognised: true, at: 10).hasPrefix("Room recognised. Stand by the door"))
        #expect(guide.step == .start)
        var fresh = ScanGuide(recognising: true)
        #expect(fresh.endRecognise(recognised: false, at: 25).hasPrefix("I couldn't recognise the room, so this scan starts fresh."))
        #expect(ScanGuide().step == .start)  // a first scan starts as before
    }
}

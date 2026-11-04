import Foundation
import Testing
@testable import RecallDomain

@Suite("Labels over the camera, and the live scan readouts")
struct ArLabelTests {
    private func label(trusted: Bool = true, review: Bool = false, photos: Int? = 5) -> ArLabel {
        ArLabel(id: "o", title: "grey bag", place: "near the desk, at knee height", confidence: 0.876, photos: photos,
                trusted: trusted, needsReview: review, position: .zero)
    }

    @Test func eachLabelIsColouredByWhatRecallDoesWithIt() {
        #expect(label().mark == .told)
        #expect(label(review: true).mark == .check)
        #expect(label(trusted: false, review: true, photos: 1).mark == .seenOnce)
    }

    @Test func theTagSaysTheThingTheScoreAndThePhotos() {
        #expect(label().headline == "GREY BAG")
        #expect(label().detail == "88% · 5 photos")
        #expect(label(photos: 1).detail == "88% · 1 photo")
        #expect(label(photos: nil).detail == "88%")
        #expect(label().spoken == "Grey bag, near the desk, at knee height. 88 percent, seen in 5 photos. Recall tells you.")
    }

    @Test func thePointTrailKeepsTheNewestAndStaysUnderItsCap() {
        var trail = PointTrail(cap: 100)
        for i in 0..<12 { trail.add((0..<20).map { SIMD3<Float>(Float(i), Float($0), 0) }) }
        #expect(trail.total == 240)
        #expect(trail.points.count <= 100)
        #expect(trail.points.last == SIMD3<Float>(11, 19, 0))  // the newest point is always kept
    }

    @Test func walkingFasterThanTheCoachAllowsTurnsTheSpeedAmber() {
        #expect(!ScanSpeed.isTooFast(0.4))
        #expect(ScanSpeed.isTooFast(0.7))
        #expect(ScanSpeed.text(0.42) == "0.4 m/s")
    }
}

@Suite("What a spoken question settles on in AR")
struct ARPickTests {
    private func label(_ id: String, _ title: String) -> ArLabel {
        ArLabel(id: id, title: title, place: "near the desk", confidence: 0.9, photos: 3, trusted: true, needsReview: false,
                position: .zero)
    }
    private var room: [ArLabel] { [label("a", "grey laptop"), label("b", "black laptop"), label("c", "brown keys")] }

    @Test func oneOfAKindWalks() {
        #expect(ARPick.settle(thingId: "c", noun: "keys", question: "where are my keys?", labels: room) == .walk(room[2]))
    }

    @Test func severalAlikeAskWhichEvenThoughTheAnswerNamedOne() {
        let pick = ARPick.settle(thingId: "a", noun: "laptop", question: "where is my laptop", labels: room)
        #expect(pick == .which([room[0], room[1]]))
    }

    @Test func theWordsSaidChooseAmongThem() {
        // the answer was about the grey one, but the person said black
        #expect(ARPick.settle(thingId: "a", noun: "laptop", question: "the black laptop", labels: room) == .walk(room[1]))
        #expect(ARPick.settle(thingId: "a", noun: "laptop", question: "take me to the black one", labels: room) == .walk(room[1]))
    }

    @Test func twoTheSameStillAsk() {
        let bottles = [label("a", "grey bottle"), label("b", "grey bottle")]
        #expect(ARPick.settle(thingId: "a", noun: "bottle", question: "the grey bottle", labels: bottles) == .which(bottles))
    }

    @Test func aThingElsewhereIsNotWalkedTo() {
        #expect(ARPick.settle(thingId: "z", noun: "passport", question: "my passport", labels: room) == .elsewhere)
        #expect(ARPick.settle(thingId: nil, noun: nil, question: "my umbrella", labels: room) == .elsewhere)
    }

    @Test func aThingWithItsOwnNameWalks() {
        let named = [label("a", "Dad's mug"), label("b", "blue mug")]
        #expect(ARPick.settle(thingId: "a", noun: nil, question: "dad's mug", labels: named) == .walk(named[0]))
    }
}

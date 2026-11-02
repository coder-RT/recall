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

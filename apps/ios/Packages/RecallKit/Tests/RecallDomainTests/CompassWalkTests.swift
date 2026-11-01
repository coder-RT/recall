import Foundation
import Testing
@testable import RecallDomain

@Suite("Walking by compass")
struct CompassWalkTests {
    private let route = [CompassLeg(bearing: 90, metres: 3), CompassLeg(bearing: 180, metres: 2)]

    @Test func theOffsetTakesTheShortWayRound() {
        #expect(CompassWalk.offset(heading: 350, bearing: 10) == 20)  // right, across north
        #expect(CompassWalk.offset(heading: 10, bearing: 350) == -20)  // left
        #expect(CompassWalk.offset(heading: 0, bearing: 180) == 180)
    }

    @Test func itSaysWhichWayToTurnUntilFacingTheLeg() {
        var walk = CompassWalk(legs: route)
        #expect(walk.update(heading: 0, metresWalked: 0) == .turn(.right, degrees: 90))
        #expect(walk.update(heading: 180, metresWalked: 0) == .turn(.left, degrees: 90))
        #expect(walk.update(heading: 85, metresWalked: 0) == .onCourse(metresLeft: 3))
    }

    @Test func smallWobblesWhileWalkingDontSayTurn() {
        var walk = CompassWalk(legs: route)
        _ = walk.update(heading: 90, metresWalked: 0)
        #expect(walk.update(heading: 110, metresWalked: 1) == .onCourse(metresLeft: 2))  // 20° off: still on course
        if case .turn = walk.update(heading: 130, metresWalked: 1.5) {} else { Issue.record("40° off should say turn") }
    }

    @Test func legsEndByDistanceThenItArrives() {
        var walk = CompassWalk(legs: route)
        _ = walk.update(heading: 90, metresWalked: 0)
        #expect(walk.update(heading: 90, metresWalked: 3.1) == .nextLeg(1))
        #expect(walk.update(heading: 90, metresWalked: 3.1) == .turn(.right, degrees: 90))  // the next leg goes south
        #expect(walk.update(heading: 180, metresWalked: 5.2) == .arrived)
        #expect(walk.update(heading: 0, metresWalked: 9) == .arrived)
    }

    @Test func walkingFarPastALegSaysStop() {
        var walk = CompassWalk(legs: route)
        _ = walk.update(heading: 90, metresWalked: 0)
        #expect(walk.update(heading: 90, metresWalked: 6) == .overshot)
    }

    @Test func eachCueHasShortWords() {
        #expect(CompassWalk.say(.turn(.left, degrees: 40), leg: nil) == "Turn left")
        #expect(CompassWalk.say(.turn(.right, degrees: 170), leg: nil) == "Turn around")
        #expect(CompassWalk.say(.onCourse(metresLeft: 2.4), leg: nil) == "Straight on, 2 metres")
        #expect(CompassWalk.say(.nextLeg(1), leg: CompassLeg(bearing: 0, metres: 1)) == "Next, 1 metre")
    }
}

import Testing
@testable import RecallDomain

@Suite("Route follower")
struct RouteFollowerTests {
    // ARKit: facing −z is straight ahead for a phone held upright with no turn
    let ahead = SIMD2<Double>(0, -1)

    @Test func clockFacesFollowARKitsAxes() {
        #expect(RouteFollower.clock(forward: ahead, to: [0, -2]) == 12)
        #expect(RouteFollower.clock(forward: ahead, to: [2, 0]) == 3)
        #expect(RouteFollower.clock(forward: ahead, to: [0, 2]) == 6)
        #expect(RouteFollower.clock(forward: ahead, to: [-2, 0]) == 9)
        #expect(RouteFollower.clock(forward: ahead, to: [1, -1]) == 2)  // 45° right rounds to 2 o'clock
    }

    @Test func passesWaypointsAndArrives() {
        var f = RouteFollower(waypoints: [[0, 0], [0, -2], [2, -2]])
        let first = f.update(position: [0, 0], forward: ahead)
        #expect(first?.clock == 12 && first?.waypoint == 1 && first?.arrived == false)
        let corner = f.update(position: [0, -1.8], forward: ahead)
        #expect(corner?.waypoint == 2 && corner?.clock == 3)
        let end = f.update(position: [1.7, -2], forward: [1, 0])
        #expect(end?.arrived == true)
    }

    @Test func spokenDirections() {
        #expect(Directions.say(.init(clock: 12, metres: 2.1, arrived: false, waypoint: 1)) == "Straight ahead, 2 metres.")
        #expect(Directions.say(.init(clock: 3, metres: 0.42, arrived: false, waypoint: 1)) == "At 3 o'clock, 40 centimetres.")
        #expect(Directions.metres(1.4) == "1.5 metres")
        #expect(Directions.metres(1.1) == "1 metre")
    }
}

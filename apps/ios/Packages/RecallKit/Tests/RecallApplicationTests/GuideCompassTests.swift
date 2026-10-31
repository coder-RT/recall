import Foundation
import RecallDomain
import RecallTestSupport
import Testing
@testable import RecallApplication

@Suite("Guide with a compass and an arrow") @MainActor
struct GuideCompassTests {
    private let keys = Thing.sample()

    private func make(map: Data?, locator: FakeLocator, route: Route, compass: FakeCompass)
        -> (GuideToThing, FakeSpeech, FakeHaptics) {
        let speech = FakeSpeech(), haptics = FakeHaptics()
        var settings = GuideToThing.Settings()
        settings.locateTimeout = 2
        settings.faceTimeout = 5
        let g = GuideToThing(home: "flat", thing: keys, roomMap: map, locator: locator, guide: FakeGuide(routes: [route]),
                             speech: speech, haptics: haptics, clock: FakeClock(), compass: compass, settings: settings)
        return (g, speech, haptics)
    }

    @Test func directionsNameTheCompassPointAndTheArrowMarksTheThing() async {
        let locator = FakeLocator(readings: [
            (.at(x: 0, z: 0), .normal), (.at(x: 0, z: 0), .normal),
            (.at(x: 0, z: -1.8), .normal),  // at the corner: the thing is to the right
            (.at(x: 0, z: -1.8), .normal),
            (.at(x: 1.7, z: -2, yawDegrees: 90), .normal),
        ])
        let route = Route(sessionId: "gs", landmarksOnly: false, reason: nil,
                          steps: [.init(clock: 12, metres: 2, say: "Straight ahead, 2 metres.")],
                          waypoints: [[0, 0], [0, -2], [2, -2]], arriveSay: "There.", target: [2, 0.8, -2])
        let compass = FakeCompass(.init(magneticDeg: 0, accuracyDeg: 5))
        let (g, speech, _) = make(map: Data("map".utf8), locator: locator, route: route, compass: compass)
        await g.run()
        #expect(compass.running)
        #expect(locator.marks.first == SIMD3(2, 0.8, -2))
        #expect(speech.lines.contains { $0.hasPrefix("At 3 o'clock, east,") })
        g.stop()
        #expect(locator.marks.last == .some(nil))
        #expect(!compass.running)
    }

    @Test func anUnreliableCompassLeavesOutTheCompassPoint() async {
        let locator = FakeLocator(readings: [
            (.at(x: 0, z: 0), .normal), (.at(x: 0, z: 0), .normal), (.at(x: 0, z: -1.8), .normal),
            (.at(x: 0, z: -1.8), .normal), (.at(x: 1.7, z: -2, yawDegrees: 90), .normal),
        ])
        let route = Route(sessionId: "gs", landmarksOnly: false, reason: nil, steps: [],
                          waypoints: [[0, 0], [0, -2], [2, -2]], arriveSay: "There.")
        let (g, speech, _) = make(map: Data("map".utf8), locator: locator, route: route,
                                  compass: FakeCompass(.init(magneticDeg: 0, accuracyDeg: 45)))
        await g.run()
        #expect(speech.lines.contains("At 3 o'clock, 2 metres."))
    }

    @Test func landmarkModeTicksWhileFacingTheThing() async {
        let locator = FakeLocator(readings: [(.at(x: 0, z: 0), .normal)])
        let route = Route(sessionId: "gs", landmarksOnly: true, reason: "no map match",
                          steps: [.init(clock: 12, metres: 0, say: "Your keys are on the desk.")], waypoints: [],
                          arriveSay: nil, bearingDeg: 45)
        let (g, speech, haptics) = make(map: nil, locator: locator, route: route,
                                        compass: FakeCompass(.init(magneticDeg: 50, accuracyDeg: 5)))
        await g.run()
        #expect(g.phase == .landmarks("Your keys are on the desk. It's to the north-east. Turn until I tick."))
        #expect(speech.lines.filter { $0 == "That way." }.count == 1)
        #expect(haptics.events.filter { $0 == "tap" }.count >= 5)  // ticking until held for 2 s
        #expect(locator.marks.isEmpty)  // no arrow without a map match
    }

    @Test func landmarkModeWithoutACompassJustSaysIt() async {
        let locator = FakeLocator(readings: [(.at(x: 0, z: 0), .normal)])
        let route = Route(sessionId: "gs", landmarksOnly: true, reason: nil,
                          steps: [.init(clock: 12, metres: 0, say: "Your keys are on the desk.")], waypoints: [],
                          arriveSay: nil, bearingDeg: 45)
        let (g, speech, _) = make(map: nil, locator: locator, route: route, compass: FakeCompass())
        await g.run()
        #expect(g.phase == .landmarks("Your keys are on the desk."))
        #expect(!speech.lines.contains("That way."))
    }
}

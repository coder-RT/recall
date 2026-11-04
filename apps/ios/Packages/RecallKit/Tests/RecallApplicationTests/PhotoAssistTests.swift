import Foundation
import RecallDomain
import RecallTestSupport
import Testing
@testable import RecallApplication

private let mapPose = Pose(columnMajor: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 2, 1.4, -1, 1])

/// A locator that hasn't recognised the room, whose camera moves a little between photos (a live session).
@MainActor private func limitedLocator() -> FakeLocator {
    let l = FakeLocator(readings: [(.identity, .limited)])
    l.moves = true
    return l
}

@MainActor private func assist(_ locator: FakeLocator, _ places: FakePlaces, _ speech: FakeSpeech, _ clock: FakeClock,
                               room: String? = "Living room") -> PhotoAssist {
    var s = PhotoAssist.Settings()
    s.maxAsks = 6
    return PhotoAssist(home: "flat", scan: "s1", room: room, locator: locator, places: places, speech: speech, clock: clock,
                       settings: s)
}

@MainActor @Test func whenARKitMatchesFirstNoPhotoIsSent() async {
    let locator = FakeLocator(readings: [(.identity, .normal)])
    let places = FakePlaces([.success(PlaceFix(room: nil, pose: nil, inliers: 0, hint: []))])
    let a = assist(locator, places, FakeSpeech(), FakeClock())
    await a.run()
    #expect(places.asked.isEmpty && !a.fixed)
}

@MainActor @Test func twoAgreeingFixesLocateThePhoneAtOnce() async {
    let locator = limitedLocator(), clock = FakeClock()
    let places = FakePlaces([.success(PlaceFix(room: "Living room", pose: mapPose, inliers: 80, hint: ["tv"]))])
    let speech = FakeSpeech()
    let a = assist(locator, places, speech, clock)
    await a.run()
    #expect(a.fixed && places.asked.count == 2 && places.asked[0].scan == "s1")
    #expect(locator.correction != nil)
    #expect(locator.reading()?.tracking == .normal)  // the guide can plan now
    #expect(speech.lines.isEmpty)  // the opening line said how to move; it was found before another was due
}

@MainActor @Test func itNeverSendsAnyoneToFindFurniture() async {
    let locator = limitedLocator(), clock = FakeClock()
    let places = FakePlaces([.success(PlaceFix(room: "Living room", pose: nil, inliers: 4, hint: ["tv", "shelf"]))])
    let speech = FakeSpeech()
    var s = PhotoAssist.Settings()
    s.maxAsks = 12
    let a = PhotoAssist(home: "flat", scan: "s1", room: "Living room", locator: locator, places: places, speech: speech,
                        clock: clock, settings: s)
    await a.run()
    #expect(!speech.lines.isEmpty && speech.lines.allSatisfy { $0.hasPrefix("Keep turning") })
}

@MainActor @Test func inAnotherRoomItSaysSoOnceAndGivesNoFix() async {
    let locator = limitedLocator(), clock = FakeClock()
    let places = FakePlaces([.success(PlaceFix(room: "Bedroom", pose: nil, inliers: 0, hint: ["bed"]))])
    let speech = FakeSpeech()
    let a = assist(locator, places, speech, clock)
    await a.run()
    #expect(!a.fixed && locator.corrections.isEmpty && places.asked.count == 6)
    #expect(speech.lines == ["You seem to be in Bedroom, not Living room. Walk to Living room and I'll keep looking."])
}

@MainActor @Test func withoutTheMacNothingChanges() async {
    let locator = limitedLocator(), clock = FakeClock()
    let speech = FakeSpeech()
    let a = assist(locator, FakePlaces([.failure(RecallError.status(503))]), speech, clock)
    await a.run()
    #expect(!a.fixed && locator.corrections.isEmpty && speech.lines.isEmpty)
}

@MainActor @Test func fixesThatDisagreeAreNotUsed() async {
    let locator = limitedLocator(), clock = FakeClock()
    let elsewhere = Pose(columnMajor: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, -2, 1.4, 3, 1])
    let fix = { (p: Pose) in Result<PlaceFix, any Error>.success(PlaceFix(room: nil, pose: p, inliers: 40, hint: [])) }
    let places = FakePlaces([fix(mapPose), fix(elsewhere), fix(mapPose), fix(elsewhere), fix(mapPose), fix(elsewhere)])
    let a = assist(locator, places, FakeSpeech(), clock)
    await a.run()
    #expect(!a.fixed && locator.corrections.isEmpty)
}

@MainActor @Test func theGuideIsLocatedByPhotosWhenARKitIsSlow() async {
    let locator = limitedLocator(), clock = FakeClock()
    let places = FakePlaces([.success(PlaceFix(room: "Office", pose: mapPose, inliers: 80, hint: []))])
    let service = FakeGuide(routes: [Route(sessionId: "gs", landmarksOnly: true, reason: "no clear path",
                                           steps: [.init(clock: 12, metres: 2, say: "Your keys are on the desk.")],
                                           waypoints: [], arriveSay: "")])
    var settings = GuideToThing.Settings()
    settings.locateTimeout = 10
    let g = GuideToThing(home: "flat", thing: Thing.sample(), roomMap: Data("map".utf8), locator: locator, guide: service,
                         speech: FakeSpeech(), haptics: FakeHaptics(), clock: clock, photos: (places: places, scan: "s1"),
                         settings: settings)
    await g.run()
    #expect(locator.correction != nil || !locator.corrections.isEmpty)
    #expect(service.routeRequests.first?.tracking == .normal)  // planned as located, not landmarks-only for weak tracking
}

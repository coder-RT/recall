import Foundation
import Testing
@testable import RecallApplication
import RecallDomain
import RecallTestSupport

@Suite("The iPhone answering its Watch")
struct AnswerWatchTests {
    private func answer(memory: FakeHomeMemory = FakeHomeMemory(things: [.sample()]), guide: FakeGuide = FakeGuide(),
                        words: FakeWords = FakeWords(), routes: FakeCompassRoutes = FakeCompassRoutes()) -> AnswerWatch {
        AnswerWatch(memory: memory, guide: guide, transcriber: words, routes: routes)
    }

    @Test func theDialListsTrustedThingsByName() async {
        let seenOnce = Thing(id: "w", label: "wallet", color: "green", heightM: 0.4, heightBand: "knee", confidence: 0.55,
                             photos: 1, trusted: false, seenAt: .now)
        let reply = await answer(memory: FakeHomeMemory(things: [.sample(), seenOnce]))(.things, home: "flat")
        #expect(reply.things?.map(\.title) == ["Red keys"])  // the wallet seen once waits in Found
    }

    @Test func aPickedThingComesWithItsRouteAndWhereToStart() async {
        let routes = FakeCompassRoutes()
        let reply = await answer(routes: routes)(.route(thingId: "obj_1"), home: "flat")
        #expect(routes.asked == ["obj_1"])
        #expect(reply.route?.legs.count == 1)
        #expect(reply.say == "Your red keys: on the desk, at waist height. To walk there, stand where you started the scan of Living room, then double tap.")
    }

    @Test func aSpokenQuestionIsTranscribedAnsweredAndRouted() async {
        let reply = await answer()(.ask(audioFile: "q.wav"), home: "flat", audio: Data([1, 2, 3]))
        #expect(reply.say?.hasPrefix("On the desk.") == true)
        #expect(reply.route?.thingId == "obj_1")
    }

    @Test func notFoundIsSaidWithoutARoute() async {
        let guide = FakeGuide(answer: Answer(text: "I haven't seen your passport yet.", thingId: nil, grounded: true))
        let reply = await answer(guide: guide)(.ask(audioFile: "q.wav"), home: "flat", audio: Data([1]))
        #expect(reply.say == "I haven't seen your passport yet.")
        #expect(reply.route == nil)
    }

    @Test func troubleComesBackAsWords() async {
        let routes = FakeCompassRoutes(error: RecallError.server("This room was scanned without a reliable compass; scan it again."))
        let reply = await answer(routes: routes)(.route(thingId: "obj_1"), home: "flat")
        #expect(reply.say == "This room was scanned without a reliable compass; scan it again.")
        let silent = await answer()(.ask(audioFile: "q.wav"), home: "flat", audio: Data())
        #expect(silent.say == "I didn't hear anything. Try again.")
    }
}

import Foundation
import RecallDomain

/// The iPhone answering its Watch: the things to pick from, the compass route to a picked thing, or a spoken question
/// (Muse Voice Transcribe, then the Guide) and the route to what it found. The Watch never holds a key; this is the
/// only way its questions reach the Mac. Failures come back as words for the Watch to say.
public struct AnswerWatch: Sendable {
    private let memory: any HomeMemory
    private let guide: any GuideService
    private let transcriber: any Transcriber
    private let routes: any CompassRoutes

    public init(memory: any HomeMemory, guide: any GuideService, transcriber: any Transcriber, routes: any CompassRoutes) {
        self.memory = memory; self.guide = guide; self.transcriber = transcriber; self.routes = routes
    }

    public func callAsFunction(_ request: WatchRequest, home: String, audio: Data? = nil) async -> WatchReply {
        do {
            switch request {
            case .things:
                // only what the owner's trust level counts: the same things Find offers
                let things = try await memory.things(home: home).filter(\.trusted).sorted { $0.title < $1.title }
                guard !things.isEmpty else { return WatchReply(things: [], say: "I don't remember anything yet. Scan a room first.") }
                return WatchReply(things: things.map { WatchThing(id: $0.id, title: $0.title.capitalizedFirstLetter, place: $0.place) })
            case .route(let id):
                return try await walk(to: id, home: home, answer: nil)
            case .ask:
                guard let audio, !audio.isEmpty else { return WatchReply(say: "I didn't hear anything. Try again.") }
                let question = try await transcriber.transcribe(wav: audio)
                guard !question.trimmingCharacters(in: .whitespaces).isEmpty else {
                    return WatchReply(say: "I didn't catch that. Turn the crown to pick a thing instead.")
                }
                let answer = try await guide.ask(home: home, question: question, about: nil)
                guard let id = answer.thingId, answer.grounded else { return WatchReply(say: answer.text) }
                return try await walk(to: id, home: home, answer: answer.text)
            }
        } catch {
            return WatchReply(say: UserMessage.explain(error))
        }
    }

    private func walk(to id: String, home: String, answer: String?) async throws -> WatchReply {
        let route = try await routes.compassRoute(home: home, thing: id)
        let first = answer ?? "Your \(route.title): \(route.place)."
        return WatchReply(say: "\(first) To walk there, stand \(route.start), then double tap.", route: route)
    }
}

private extension String {
    var capitalizedFirstLetter: String { prefix(1).uppercased() + dropFirst() }
}

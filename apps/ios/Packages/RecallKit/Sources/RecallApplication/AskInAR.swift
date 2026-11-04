import Foundation
import RecallDomain

/// A question asked with the AR view open: the Guide answers from the Mac's memory as it does on Find, then the answer
/// is matched to the labels in this room. One thing here: walk there. Several alike: ask which. Anywhere else: just
/// the answer, because walking there needs that room's map.
public struct AskInAR: Sendable {
    public enum Outcome: Sendable, Equatable {
        case walk(Thing, say: String)
        case which(say: String)
        case answer(String)
    }

    private let ask: AskWhereIs

    public init(ask: AskWhereIs) { self.ask = ask }

    public func callAsFunction(_ question: String, home: String, known: [Thing], labels: [ArLabel],
                               about: String? = nil) async throws -> Outcome {
        let result = try await ask(question, home: home, known: known, about: about)
        let text = result.answer.text
        switch ARPick.settle(thingId: result.answer.thingId, noun: result.thing?.label, question: question, labels: labels) {
        case .walk(let label):
            guard let thing = known.first(where: { $0.id == label.id }) else { return .answer(text) }
            return .walk(thing, say: text)
        case .which:
            return .which(say: text + " Double tap the one you mean, or say which.")
        case .elsewhere:
            return .answer(text)
        }
    }
}

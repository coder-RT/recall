import Foundation
import RecallDomain

/// "Where are my keys?": the Guide answers from the Mac's memory (tool output only), and the answer comes with the
/// thing it found, so the user can be walked there.
public struct AskWhereIs: Sendable {
    public struct Result: Sendable, Equatable {
        public let answer: Answer
        public let thing: Thing?
    }

    private let guide: any GuideService

    public init(guide: any GuideService) { self.guide = guide }

    /// `known`: the things already listed, to name the one the answer is about.
    public func callAsFunction(_ question: String, home: String, known: [Thing], about: String? = nil) async throws -> Result {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { throw RecallError.server("Type or say what you're looking for first.") }
        let answer = try await guide.ask(home: home, question: q, about: about)
        return Result(answer: answer, thing: answer.thingId.flatMap { id in known.first { $0.id == id } })
    }
}

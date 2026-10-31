import Foundation

/// What the phone says the moment it has the question, before the Guide answers, so nobody waits in silence.
/// Spoken with the system voice; it only repeats a word the person said, never a place.
public enum Acknowledgement {
    public static let checking = "Checking."

    /// "Looking for your keys." when the question names something Recall remembers, else "Checking.".
    public static func line(for question: String, known: [Thing]) -> String {
        let words = question.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let said = " " + words.joined(separator: " ") + " "
        var best: String?
        for thing in known {
            for candidate in [thing.name, thing.label].compactMap({ $0?.lowercased() }) where !candidate.isEmpty {
                let forms = [candidate, candidate.hasSuffix("s") ? String(candidate.dropLast()) : candidate + "s"]
                if forms.contains(where: { said.contains(" \($0) ") }), candidate.count > (best?.count ?? 0) {
                    best = candidate
                }
            }
        }
        return best.map { "Looking for your \($0)." } ?? checking
    }
}

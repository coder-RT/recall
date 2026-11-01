import Foundation

/// How sure Recall must be before it tells you about a thing, by the photos it was seen in. One photo is one angle,
/// where a book cover can pass for a wallet; seen again from another place, it is very likely there. Kept on the Mac,
/// so the voice Guide, Find, room maps and robots all follow it. A thing you confirmed always counts.
public enum TrustLevel: String, CaseIterable, Identifiable, Sendable {
    case careful, balanced, everything

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .careful: "Careful"
        case .balanced: "Balanced"
        case .everything: "Everything"
        }
    }

    /// What the level means, said once under the choice.
    public var explanation: String {
        switch self {
        case .careful: "Only things seen in at least 3 photos. Fewer mistakes; some real things wait for you to confirm them."
        case .balanced: "Things seen in at least 2 photos. A thing seen once waits in Found until you confirm it."
        case .everything: "Every find, even from one photo. More mistakes, like a wallet that is really a book."
        }
    }
}

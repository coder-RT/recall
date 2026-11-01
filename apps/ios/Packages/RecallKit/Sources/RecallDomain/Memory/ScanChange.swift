import Foundation

/// One difference a rescan found against what Recall remembered in that room, with the places in words.
public struct ScanChange: Sendable, Equatable, Codable, Identifiable {
    public enum Kind: String, Sendable, Codable { case moved, new, gone }

    public let kind: Kind
    public let objectId: String
    public let label: String
    public let name: String?
    public let color: String?
    public let from: String?
    public let to: String?

    public init(kind: Kind, objectId: String, label: String, name: String? = nil, color: String? = nil,
                from: String? = nil, to: String? = nil) {
        self.kind = kind; self.objectId = objectId; self.label = label; self.name = name; self.color = color
        self.from = from; self.to = to
    }

    public var id: String { "\(kind.rawValue)-\(objectId)" }

    /// "beige keys", or the user's own name for it.
    public var title: String { name ?? [color, label].compactMap { $0 }.joined(separator: " ") }

    /// The icon kind: a change is about something Recall saw clearly enough to match, so it gets its own icon.
    public var thingKind: ThingKind { ThingKind.of(label: label, name: name) }

    /// The places alone, under a "Moved" / "New" / "Gone" badge: "near the desk → on the shelf".
    public var places: String {
        switch kind {
        case .moved: "\(from ?? "where it was") → \(to ?? "somewhere new")"
        case .new: to ?? "in the room"
        case .gone: "was \(from ?? "here")"
        }
    }

    /// The same as a sentence, for VoiceOver: "Moved from near the desk to on the shelf".
    public var line: String {
        switch kind {
        case .moved: "Moved from \(from ?? "where it was") to \(to ?? "somewhere new")"
        case .new: "New, \(to ?? "in the room")"
        case .gone: "Gone from \(from ?? "where it was")"
        }
    }
}

/// What a processed rescan says aloud: "Living room is ready. 3 changes: your beige keys moved from near the desk
/// to on the shelf. New: a white mug. Gone: your grey bag."
public enum ChangeSummary {
    public static let most = 3  // per kind; the rest are counted ("and 2 more")

    /// A rescan that didn't line up with the last one: a complete new map, nothing lost, but no comparison. Said as
    /// what Recall did and what to do next time, never as a failure.
    public static func freshTitle(room: String) -> String { "A fresh map of \(room)" }
    public static let freshBody = "This walk didn't line up with your last scan, so Recall can't say what moved this "
        + "time. Everything it found is mapped, and your earlier scan is kept below."
    public static let freshTip = "To see what moved next time, start Scan again where your last scan began."

    /// Spoken: the same, shorter.
    public static func sayFresh(room: String) -> String {
        "A fresh map of \(room). This walk didn't line up with your last scan, so I can't say what moved this time."
    }

    public static func say(room: String, changes: [ScanChange]) -> String {
        guard !changes.isEmpty else { return "\(room) is ready. Nothing has moved since the last scan." }
        let n = changes.count == 1 ? "1 change" : "\(changes.count) changes"
        var parts: [String] = []
        let moved = changes.filter { $0.kind == .moved }
        if !moved.isEmpty {
            parts.append(capitalised(list(moved.map { "your \($0.title) moved from \($0.from ?? "where it was") to \($0.to ?? "somewhere new")" })) + ".")
        }
        let new = changes.filter { $0.kind == .new }
        if !new.isEmpty { parts.append("New: " + list(new.map { article($0.title) }) + ".") }
        let gone = changes.filter { $0.kind == .gone }
        if !gone.isEmpty { parts.append("Gone: " + list(gone.map { "your \($0.title)" }) + ".") }
        return "\(room) is ready. \(n): " + parts.joined(separator: " ")
    }

    /// "a, b and c", at most `most`, then "and N more".
    static func list(_ items: [String]) -> String {
        let shown = Array(items.prefix(most))
        let rest = items.count - shown.count
        if rest > 0 { return shown.joined(separator: ", ") + " and \(rest) more" }
        if shown.count <= 1 { return shown.first ?? "" }
        return shown.dropLast().joined(separator: ", ") + " and " + shown.last!
    }

    static func article(_ title: String) -> String {
        guard let first = title.lowercased().first else { return title }
        return ("aeiou".contains(first) ? "an " : "a ") + title
    }

    static func capitalised(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }
}

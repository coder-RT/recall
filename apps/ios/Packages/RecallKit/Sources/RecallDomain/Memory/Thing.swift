import Foundation

/// One thing Recall remembers in a home, as the user meets it: what it is, where, and how sure Recall is.
/// The user's corrections (name, colour, height, note) are already folded in by the Mac.
public struct Thing: Identifiable, Sendable, Equatable {
    public let id: String
    public let label: String
    public let name: String?
    public let color: String?
    /// The colour the scan measured, when the user hasn't set one (shown as "As seen: grey").
    public let measuredColor: String?
    public let heightM: Double
    public let userHeightM: Double?
    public let heightBand: String
    public let landmark: String?
    public let relation: String?
    /// The room it was found in (the furniture's room, else the scan's).
    public let room: String?
    public let sizeCm: [Int]?
    public let note: String?
    public let confidence: Double
    public let confirmed: Bool
    public let needsReview: Bool
    /// How many of the scan's photos showed it (nil for sightings kept before the Mac counted them).
    public let photos: Int?
    /// Seen in enough photos for the owner's level, or confirmed: Find and the Guide use only trusted things.
    public let trusted: Bool
    public let seenAt: Date

    public init(id: String, label: String, name: String? = nil, color: String? = nil, measuredColor: String? = nil,
                heightM: Double, userHeightM: Double? = nil, heightBand: String, landmark: String? = nil,
                relation: String? = nil, room: String? = nil, sizeCm: [Int]? = nil, note: String? = nil, confidence: Double,
                confirmed: Bool = false, needsReview: Bool = false, photos: Int? = nil, trusted: Bool = true,
                seenAt: Date) {
        self.id = id; self.label = label; self.name = name; self.color = color; self.measuredColor = measuredColor
        self.heightM = heightM; self.userHeightM = userHeightM; self.heightBand = heightBand; self.landmark = landmark
        self.relation = relation; self.room = room; self.sizeCm = sizeCm; self.note = note; self.confidence = confidence
        self.confirmed = confirmed; self.needsReview = needsReview; self.photos = photos; self.trusted = trusted
        self.seenAt = seenAt
    }

    /// What VoiceOver and the lists say: "grey bag", or the user's own name for it.
    public var title: String { name ?? [color, label].compactMap { $0 }.joined(separator: " ") }

    /// "near the desk, knee height"; "in the room, waist height" without a landmark.
    public var place: String {
        let rel = (relation ?? "near").replacingOccurrences(of: "_", with: " ")
        let at = landmark.map { "\(rel) the \($0)" } ?? "in the room"
        return "\(at), \(heightBand) height"
    }

    /// "Checked by you", "Unsure, 62 percent sure", "70 percent sure".
    public var certainty: String {
        if confirmed { return "Checked by you" + (note.map { ". \($0)" } ?? "") }
        let sure = "\(Int((confidence * 100).rounded())) percent sure"
        return needsReview ? "Unsure, \(sure)" : sure.prefix(1).uppercased() + sure.dropFirst()
    }

    /// The evidence, in words: "Seen in 1 photo, 55 percent sure".
    public var evidence: String {
        let sure = "\(Int((confidence * 100).rounded())) percent sure"
        guard let photos else { return sure.prefix(1).uppercased() + sure.dropFirst() }
        return "Seen in \(photos == 1 ? "1 photo" : "\(photos) photos"), \(sure)"
    }

    /// Found's short mark for a thing to check: "Seen once" while it waits for a second look, else "Check".
    public var checkMark: String { !trusted && photos == 1 ? "Seen once" : "Check" }

    /// Unsure things first, then by name: the order of every list.
    public static func listOrder(_ a: Thing, _ b: Thing) -> Bool {
        (a.needsReview ? 0 : 1, a.title) < (b.needsReview ? 0 : 1, b.title)
    }
}

/// What the user changes about a thing. `.clear` puts the measured value back; saving also confirms it.
public struct Correction: Sendable, Equatable {
    public enum Edit<T: Sendable & Equatable>: Sendable, Equatable { case keep, set(T), clear }

    public var name: Edit<String> = .keep
    public var color: Edit<String> = .keep
    public var heightM: Edit<Double> = .keep
    public var note: Edit<String> = .keep
    public var confirmed: Bool?

    public init() {}

    /// The edit form's values as a correction: empty text clears, an untouched height clears the user's height.
    public static func from(name: String, color: String, heightCm: Int?, note: String) -> Correction {
        var c = Correction()
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        c.name = n.isEmpty ? .clear : .set(n)
        c.color = color.isEmpty ? .clear : .set(color)
        c.heightM = heightCm.map { .set(Double($0) / 100) } ?? .clear
        let t = note.trimmingCharacters(in: .whitespacesAndNewlines)
        c.note = t.isEmpty ? .clear : .set(t)
        c.confirmed = true
        return c
    }

    /// The colours the user can pick (the pipeline names the same set).
    public static let colors = ["black", "white", "grey", "red", "orange", "yellow", "green", "blue", "purple", "pink",
                                "brown", "beige"]
}

/// The Guide's spoken answer to "where is…?", and the thing it found, if any.
public struct Answer: Sendable, Equatable {
    public let text: String
    public let thingId: String?
    public let grounded: Bool
    /// The Mac's log entry for this answer: its evidence explains why ("Why?").
    public let answerId: String?

    public init(text: String, thingId: String?, grounded: Bool, answerId: String? = nil) {
        self.text = text; self.thingId = thingId; self.grounded = grounded; self.answerId = answerId
    }
}

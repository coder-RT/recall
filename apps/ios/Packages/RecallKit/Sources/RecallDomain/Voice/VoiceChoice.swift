import Foundation

/// Which kind of voice the owner wants Recall to speak in (Settings → Voice).
public enum VoicePreference: String, CaseIterable, Sendable {
    case automatic, female, male

    public var title: String {
        switch self {
        case .automatic: "Automatic"
        case .female: "Female"
        case .male: "Male"
        }
    }
}

/// One of the iPhone's own voices, as the speech framework describes it (an OS feature, not a model).
public struct VoiceOption: Sendable, Equatable {
    public enum Gender: Sendable { case female, male, unspecified }

    public let id: String
    public let name: String
    public let language: String  // "en-GB"
    /// 0 default, 1 enhanced, 2 premium: the downloadable voices sound the most natural
    public let quality: Int
    public let gender: Gender
    /// novelty voices (Bells, Bubbles…) and the owner's Personal Voice are never chosen automatically
    public let special: Bool

    public init(id: String, name: String, language: String, quality: Int, gender: Gender, special: Bool = false) {
        self.id = id; self.name = name; self.language = language; self.quality = quality
        self.gender = gender; self.special = special
    }

    public var qualityName: String { ["", "Enhanced", "Premium"][min(max(quality, 0), 2)] }

    /// "Ava (Premium)", "Daniel".
    public var title: String { qualityName.isEmpty ? name : "\(name) (\(qualityName))" }
}

public enum VoiceChoice {
    /// The best voice for `language` ("en-GB"): the same language, never a novelty or Personal Voice, premium before
    /// enhanced before default, then the same region, then by name. With a gender preference, voices of that gender
    /// come first; if none is installed, the best of any gender speaks rather than none.
    public static func best(_ voices: [VoiceOption], preference: VoicePreference, language: String) -> VoiceOption? {
        let base = language.split(separator: "-").first.map(String.init) ?? language
        let usable = voices.filter { !$0.special && $0.language.split(separator: "-").first.map(String.init) == base }
        let wanted: VoiceOption.Gender? = switch preference {
        case .automatic: nil
        case .female: .female
        case .male: .male
        }
        let pool = wanted.map { g in usable.filter { $0.gender == g } }.flatMap { $0.isEmpty ? nil : $0 } ?? usable
        return pool.max { a, b in
            if a.quality != b.quality { return a.quality < b.quality }
            let (ra, rb) = (a.language == language, b.language == language)
            if ra != rb { return !ra }
            return a.name > b.name
        }
    }
}

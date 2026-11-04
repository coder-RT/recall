import Foundation

/// What the person meant after "Do you want to go back, or are you done?". Plain word rules on what Muse Voice
/// Transcribe heard, because a wrong guess here only costs a sentence; anything else is a new question for the Guide.
public enum FoundReply: Sendable, Equatable {
    case goBack, done, question

    public static func read(_ said: String) -> FoundReply {
        let words = said.lowercased().replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "\u{2019}", with: "")
            .split(whereSeparator: { !$0.isLetter }).map(String.init)
        let has = { (list: Set<String>) in words.contains(where: list.contains) }
        if has(["where", "wheres", "find", "looking", "locate"]) { return .question }
        let refused = has(["dont", "not", "never"]) || (words.contains("no") && words.contains("need"))
        if has(["back", "return"]) { return refused ? .done : .goBack }
        if has(["yes", "yeah", "yep", "yup", "sure"]) { return .goBack }
        if refused || has(["no", "nope", "done", "thanks", "thank", "nothing", "finished", "stop", "ok", "okay", "bye",
                           "goodbye", "fine"]) { return .done }
        return .question
    }
}

/// Roughly how long a line takes to say: under VoiceOver the app can't hear when VoiceOver has finished, and the
/// microphone mustn't open over it.
public enum SpokenLength {
    public static func seconds(_ line: String) -> Double {
        Double(line.split(separator: " ").count) * 0.42 + 0.6
    }
}

/// Ends a recording when the person has finished talking: the microphone's level, nothing more (no speech recognition).
public struct SilenceGate: Sendable {
    public enum Verdict: Sendable, Equatable { case listen, finished, nothingSaid }

    public var speechLevel = -34.0  // dB: louder than this is someone talking
    public var quietAfter = 1.2  // seconds of quiet after speech that end the turn
    public var giveUpAfter = 8.0  // seconds with no speech at all
    private var lastSpeech: Double?

    public init() {}

    public mutating func hear(level: Double, at seconds: Double) -> Verdict {
        if level > speechLevel { lastSpeech = seconds }
        if let lastSpeech { return seconds - lastSpeech >= quietAfter ? .finished : .listen }
        return seconds >= giveUpAfter ? .nothingSaid : .listen
    }
}

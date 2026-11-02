import AVFoundation
import RecallDomain
import UIKit

/// Speaks short lines. With VoiceOver on, lines go through VoiceOver (the user's own voice and rate); otherwise through
/// AVSpeechSynthesizer, an OS feature, not a speech model (CLAUDE.md rule 8), in the iPhone's best voice for the
/// owner's choice (Settings → Voice: automatic, female or male; premium voices first when downloaded).
@MainActor
public final class Announcer: NSObject, SpeechOutput, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()
    public var rate: Float = AVSpeechUtteranceDefaultSpeechRate
    /// Sees every line as it is spoken (the UI tests' log of what was said; nil in the app).
    public var onSay: ((String) -> Void)?
    public var onFinished: (() -> Void)?

    public override init() {
        super.init()
        synth.delegate = self
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
    }

    public var isSpeaking: Bool { synth.isSpeaking }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in if !self.synth.isSpeaking { self.onFinished?() } }
    }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in if !self.synth.isSpeaking { self.onFinished?() } }
    }

    /// The owner's choice in Settings → Voice, kept on this iPhone.
    public static let voiceKey = "recall.voice"

    public var voicePreference: VoicePreference {
        get { VoicePreference(rawValue: UserDefaults.standard.string(forKey: Self.voiceKey) ?? "") ?? .automatic }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Self.voiceKey) }
    }

    /// Every voice on this iPhone, as Recall's domain describes them.
    public static func installedVoices() -> [VoiceOption] {
        AVSpeechSynthesisVoice.speechVoices().map { v in
            VoiceOption(
                id: v.identifier, name: v.name, language: v.language,
                quality: v.quality == .premium ? 2 : v.quality == .enhanced ? 1 : 0,
                gender: v.gender == .female ? .female : v.gender == .male ? .male : .unspecified,
                special: v.voiceTraits.contains(.isNoveltyVoice) || v.voiceTraits.contains(.isPersonalVoice)
            )
        }
    }

    /// The voice Recall would speak in for `preference`: the best installed one in the iPhone's language.
    public static func chosenVoice(_ preference: VoicePreference) -> VoiceOption? {
        VoiceChoice.best(installedVoices(), preference: preference, language: AVSpeechSynthesisVoice.currentLanguageCode())
    }

    public func currentVoice() -> VoiceOption? { Self.chosenVoice(voicePreference) }

    public func say(_ text: String, interrupt: Bool = false) {
        onSay?(text)
        if UIAccessibility.isVoiceOverRunning {
            let s = NSAttributedString(string: text, attributes: [.accessibilitySpeechQueueAnnouncement: !interrupt])
            UIAccessibility.post(notification: .announcement, argument: s)
            return
        }
        if interrupt { synth.stopSpeaking(at: .immediate) }
        try? AVAudioSession.sharedInstance().setActive(true)
        let u = AVSpeechUtterance(string: text)
        u.rate = rate
        if let id = currentVoice()?.id { u.voice = AVSpeechSynthesisVoice(identifier: id) }  // else the system default
        synth.speak(u)
    }

    public func stop() { synth.stopSpeaking(at: .immediate) }
}

/// One haptic vocabulary for the whole app (and the Watch later): never colour or sound alone.
@MainActor
public final class Haptics: HapticsOutput {
    public init() {}
    public func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    public func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    public func tap() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
}

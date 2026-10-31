import AVFoundation
import RecallDomain
import UIKit

/// Speaks short lines. With VoiceOver on, lines go through VoiceOver (the user's own voice and rate); otherwise through
/// AVSpeechSynthesizer, an OS feature, not a speech model (CLAUDE.md rule 8).
@MainActor
public final class Announcer: SpeechOutput {
    private let synth = AVSpeechSynthesizer()
    public var rate: Float = AVSpeechUtteranceDefaultSpeechRate

    public init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
    }

    public func say(_ text: String, interrupt: Bool = false) {
        if UIAccessibility.isVoiceOverRunning {
            let s = NSAttributedString(string: text, attributes: [.accessibilitySpeechQueueAnnouncement: !interrupt])
            UIAccessibility.post(notification: .announcement, argument: s)
            return
        }
        if interrupt { synth.stopSpeaking(at: .immediate) }
        try? AVAudioSession.sharedInstance().setActive(true)
        let u = AVSpeechUtterance(string: text)
        u.rate = rate
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

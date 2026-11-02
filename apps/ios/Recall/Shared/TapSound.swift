import AudioToolbox
import UIKit

/// The soft tap when the user switches tabs or presses a button, with a light haptic. Our own sound (scripts/make_tap_sound.py),
/// played as a system sound: it follows the ring/silent switch, and it doesn't touch the audio session, so it never
/// stops music, speech or VoiceOver. Settings → Tap sounds turns it off.
@MainActor
final class TapSound {
    static let shared = TapSound()
    /// The Settings switch (on unless turned off).
    static let enabledKey = "tapSounds"

    enum Kind { case tab, press }

    private var sound: SystemSoundID = 0
    private let selection = UISelectionFeedbackGenerator()
    private let soft = UIImpactFeedbackGenerator(style: .soft)

    private init() {
        if let url = Bundle.main.url(forResource: "tap", withExtension: "wav") {
            AudioServicesCreateSystemSoundID(url as CFURL, &sound)
        }
    }

    /// A tab switch: a selection tick. A press on a button or row: a soft bump. Both with the soft tap sound.
    func play(_ kind: Kind = .tab) {
        // the UI tests run silent; elsewhere the user's switch decides
        guard !UITestSamples.enabled, UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true else { return }
        switch kind {
        case .tab: selection.selectionChanged()
        case .press: soft.impactOccurred(intensity: 0.6)
        }
        if sound != 0 { AudioServicesPlaySystemSound(sound) }
    }
}

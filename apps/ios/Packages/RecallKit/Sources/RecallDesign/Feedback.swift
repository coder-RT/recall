import RecallDomain
import SwiftUI
import UIKit

/// The soft tap (sound and haptic) every press gives. The app connects it to its sound at launch (TapSound); the
/// shared button styles call it, so a new screen gets it by using them.
@MainActor
public enum TapFeedback {
    public static var play: () -> Void = {}
}

/// A plain button (rows, cards) that still gives the soft tap when pressed.
public struct PlainTapStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .onChange(of: configuration.isPressed) { _, down in if down { TapFeedback.play() } }
    }
}

extension ButtonStyle where Self == PlainTapStyle {
    public static var plainTap: PlainTapStyle { PlainTapStyle() }
}

extension View {
    /// Keeps a text field within the Mac's limit, without control characters (or line breaks, unless `multiline`).
    /// In a one-line field that grows with large text (`axis: .vertical`), Return types a line break instead of
    /// ending the edit: the break is dropped and the keyboard goes away, as Return does in any one-line field.
    public func limited(_ text: Binding<String>, to limit: Int, multiline: Bool = false) -> some View {
        onChange(of: text.wrappedValue) { _, typed in
            let kept = TextInput.clean(typed, limit: limit, multiline: multiline)
            if kept != typed { text.wrappedValue = kept }
            if TextInput.pressedReturn(typed, multiline: multiline) { Keyboard.hide() }
        }
    }

    /// The keyboard hides when the list or form is scrolled. A tap outside a field hides it app-wide
    /// (KeyboardDismissal), and Return hides it in one-line fields (`limited`), which VoiceOver users reach easily.
    /// (No Done bar above the keyboard: SwiftUI keeps its invisible node on screen, which the accessibility audit flags.)
    public func keyboardDismissable() -> some View {
        scrollDismissesKeyboard(.interactively)
    }
}

/// Hides the keyboard, whichever field has it.
@MainActor
public enum Keyboard {
    public static func hide() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

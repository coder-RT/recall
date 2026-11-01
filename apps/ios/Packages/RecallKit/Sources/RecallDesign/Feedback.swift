import RecallDomain
import SwiftUI

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
    public func limited(_ text: Binding<String>, to limit: Int, multiline: Bool = false) -> some View {
        onChange(of: text.wrappedValue) { _, typed in
            let kept = TextInput.clean(typed, limit: limit, multiline: multiline)
            if kept != typed { text.wrappedValue = kept }
        }
    }
}

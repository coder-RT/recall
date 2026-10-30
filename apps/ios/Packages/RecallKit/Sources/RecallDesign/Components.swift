import SwiftUI

/// A full-width Liquid Glass button with a large target, an icon and a spoken hint.
public struct BigButton: View {
    let title: String
    let systemImage: String
    let hint: String
    let style: Style
    let action: () -> Void

    public enum Style: Sendable { case primary, secondary, stop }

    public init(_ title: String, systemImage: String, hint: String, style: Style = .primary, action: @escaping () -> Void) {
        self.title = title; self.systemImage = systemImage; self.hint = hint; self.style = style; self.action = action
    }

    public var body: some View {
        let label = Label(title, systemImage: systemImage)
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: Tokens.minTarget - 14)
        Group {
            if style == .secondary {
                Button(action: action) { label.foregroundStyle(Tokens.blueDark) }.buttonStyle(.glass)
            } else {
                Button(action: action) { label }.buttonStyle(.glassProminent).tint(style == .stop ? Tokens.danger : Tokens.cta)
            }
        }
        .controlSize(.large)
        .accessibilityHint(hint)
    }
}

/// A big number with a label, read by VoiceOver as one sentence.
public struct StatTile: View {
    let value: String
    let label: String

    public init(_ value: String, _ label: String) { self.value = value; self.label = label }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title2.weight(.bold)).monospacedDigit().foregroundStyle(Tokens.ink)
            Text(label).font(.footnote).foregroundStyle(Tokens.muted)
        }
        .card(padding: 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(label)")
    }
}

/// A banner for coaching cues: text, an icon and a colour, never colour alone.
public struct CueBanner: View {
    let text: String
    public init(_ text: String) { self.text = text }

    public var body: some View {
        Label(text, systemImage: "tortoise.fill")
            .font(.title2.weight(.bold))
            .foregroundStyle(Tokens.ink)
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(Tokens.amber, in: .rect(cornerRadius: 22))
            .glassRim(.rect(cornerRadius: 22))
            .accessibilityAddTraits(.updatesFrequently)
    }
}

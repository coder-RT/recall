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

    // text sits on a solid fill (contrast never depends on what is behind); glass is the rim and the touch response
    public var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: Tokens.minTarget)
                .padding(.horizontal, 16)
                .foregroundStyle(style == .secondary ? Tokens.blueDeep : .white)
                .background(fill, in: Capsule())
                .overlay(Capsule().stroke(style == .secondary ? Tokens.line : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .glassRim(.capsule, .regular.interactive())
        .accessibilityHint(hint)
    }

    private var fill: Color {
        switch style {
        case .primary: Tokens.cta
        case .secondary: .white
        case .stop: Tokens.danger
        }
    }
}

/// A big number with a label on glass, read by VoiceOver as one sentence.
public struct StatTile: View {
    let value: String
    let label: String

    public init(_ value: String, _ label: String) { self.value = value; self.label = label }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title.weight(.bold)).monospacedDigit().foregroundStyle(Tokens.ink)
            Text(label).font(.subheadline).foregroundStyle(Tokens.muted)
        }
        .glassCard(cornerRadius: 18, padding: 12)
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

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
            switch style {
            case .secondary:
                Button(action: action) { label.foregroundStyle(Tokens.accent) }.buttonStyle(.glass)
            case .primary:
                Button(action: action) { label.foregroundStyle(Tokens.onGo) }.buttonStyle(.glassProminent).tint(Tokens.go)
            case .stop:
                Button(action: action) { label.foregroundStyle(Tokens.onDanger) }.buttonStyle(.glassProminent)
                    .tint(Tokens.dangerFill)
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
            .hudRim(RoundedRectangle(cornerRadius: 22))
            .accessibilityAddTraits(.updatesFrequently)
    }
}

/// A capsule button with its words on a solid fill (glass would tint them and cost contrast); the glass is the rim
/// and the touch response.
public struct SolidPillStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let fill: Color
    let text: Color
    let edge: Color?
    let compact: Bool

    /// `compact`: sized to its words (44 pt tall) for a row of small actions, instead of full width.
    public init(fill: Color, text: Color, edge: Color? = nil, compact: Bool = false) {
        self.fill = fill; self.text = text; self.edge = edge; self.compact = compact
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(compact ? .subheadline.weight(.semibold) : .headline)
            .foregroundStyle(text)
            .frame(maxWidth: compact ? nil : .infinity, minHeight: compact ? 44 : Tokens.minTarget)
            .padding(.horizontal, compact ? 14 : 12)
            .background(fill, in: Capsule())
            .overlay(Capsule().stroke(edge ?? .clear, lineWidth: 1.5))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(MotionTokens.animation(MotionTokens.press, reduceMotion: reduceMotion), value: configuration.isPressed)
            .glassRim(.capsule, .regular.interactive())
    }
}

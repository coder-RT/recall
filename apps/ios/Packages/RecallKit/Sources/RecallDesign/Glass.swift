import SwiftUI

/// The sky behind every screen: deep old-Facebook blue at the top (where the white titles sit) fading to pale, with a
/// few soft lights. Static, so nothing moves for people who turn motion off.
public struct GlassBackground: View {
    public init() {}

    public var body: some View {
        ZStack {
            LinearGradient(stops: [
                .init(color: Tokens.blueDeep, location: 0),
                .init(color: Tokens.blueDark, location: 0.22),
                .init(color: Tokens.blue, location: 0.42),
                .init(color: Tokens.bluePale, location: 0.78),
                .init(color: Tokens.grey, location: 1),
            ], startPoint: .top, endPoint: .bottom)
            GeometryReader { geo in
                let w = geo.size.width
                // lights stay below the titles, so white headings keep the deep blue behind them
                Circle().fill(Color(red: 0.55, green: 0.62, blue: 0.95).opacity(0.5))
                    .frame(width: w * 0.9).blur(radius: 70).offset(x: w * 0.35, y: geo.size.height * 0.45)
                Circle().fill(.white.opacity(0.35))
                    .frame(width: w * 0.7).blur(radius: 60).offset(x: -w * 0.3, y: geo.size.height * 0.62)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

extension View {
    /// A Liquid Glass card. The glass is a layer behind a frosted white fill, never around the text: glass gives text
    /// "vibrancy" (its colour shifts with what is behind), which breaks contrast. So ink reads at full strength.
    public func glassCard(cornerRadius: CGFloat = 24, padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tokens.glassTint, in: .rect(cornerRadius: cornerRadius))
            .glassRim(.rect(cornerRadius: cornerRadius))
    }

    /// Liquid Glass behind a view (its rim and light), without putting the view's own content inside the glass.
    public func glassRim(_ shape: some Shape, _ glass: Glass = .regular) -> some View {
        self.background { Color.clear.glassEffect(glass, in: shape) }
    }

    /// Glass screen chrome: the sky behind the content, and white navigation titles and buttons on its dark top.
    public func recallScreen() -> some View {
        self.scrollContentBackground(.hidden)
            .background { GlassBackground() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            // iOS 26 fades content under the bars with a light blur; on the deep sky it washed out the white titles
            .scrollEdgeEffectHidden(true, for: .top)
    }
}

/// The big round button at the heart of the Home screen: a glowing glass orb with an icon and a word under it.
public struct GlowOrb: View {
    let title: String
    let systemImage: String
    let hint: String
    let action: () -> Void

    public init(_ title: String, systemImage: String, hint: String, action: @escaping () -> Void) {
        self.title = title; self.systemImage = systemImage; self.hint = hint; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [.white.opacity(0.95), Color(red: 0.62, green: 0.70, blue: 1.0), Tokens.blue],
                                             center: .init(x: 0.4, y: 0.35), startRadius: 4, endRadius: 90))
                        .frame(width: 150, height: 150)
                        .shadow(color: Color(red: 0.6, green: 0.7, blue: 1).opacity(0.8), radius: 30)
                    Image(systemName: systemImage)
                        .font(.system(size: 48, weight: .semibold))
                        .foregroundStyle(Tokens.blueDeep)
                }
                .glassEffect(.clear.interactive(), in: .circle)
                .accessibilityHidden(true)
                // the word sits on its own deep-blue glass, so it reads wherever the sky has turned pale
                Text(title).font(.title2.weight(.bold)).foregroundStyle(.white)
                    .padding(.horizontal, 22).padding(.vertical, 10)
                    .background(Tokens.blueDeep, in: Capsule())
                    .glassRim(.capsule)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(hint)
    }
}

/// The directions covered while scanning, as a dial of 12 ticks (one per 30°), lit when covered.
public struct CoverageDial: View {
    let covered: Set<Int>
    let count: Int

    public init(covered: Set<Int>, count: Int) { self.covered = covered; self.count = count }

    public var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.35), lineWidth: 2)
            ForEach(0..<12, id: \.self) { i in
                Capsule()
                    .fill(covered.contains(i) ? Tokens.amber : .white.opacity(0.45))
                    .frame(width: 6, height: covered.contains(i) ? 18 : 12)
                    .offset(y: -46)
                    .rotationEffect(.degrees(Double(i) * 30))
            }
            VStack(spacing: 0) {
                Text("\(count)").font(.system(size: 34, weight: .bold)).monospacedDigit().foregroundStyle(.white)
                Text("of 12").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
            }
        }
        .frame(width: 112, height: 112)
        .padding(10)
        .background(Tokens.blueDeep.opacity(0.85), in: .circle)
        .glassRim(.circle)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) of 12 directions covered")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// A choice among a few (room names): white pill with deep-blue text inside a glass rim.
public struct PillButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(Tokens.blueDeep)
            .frame(maxWidth: .infinity, minHeight: Tokens.minTarget)
            .padding(.horizontal, 10)
            .background(.white, in: Capsule())
            .overlay(Capsule().stroke(Tokens.line, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .glassRim(.capsule, .regular.interactive())
    }
}

import SwiftUI

// The content layer: a light canvas and white cards. Liquid Glass belongs to the layer above it (tab bar, toolbars,
// search, buttons, the scan HUD over the camera), which the system draws; we don't paint behind the bars.

extension View {
    /// A white card on the canvas: rounded, a hairline edge and a soft shadow. Ink text keeps full contrast.
    public func card(padding: CGFloat = Tokens.cardPadding) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: .rect(cornerRadius: Tokens.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Tokens.cardRadius).stroke(Tokens.line.opacity(0.6), lineWidth: 0.5))
            .shadow(color: Tokens.blueDeep.opacity(0.06), radius: 10, y: 4)
    }

    /// Liquid Glass behind a view (its rim and light), not around its text: glass gives text "vibrancy" (its colour
    /// shifts with what is behind), which breaks contrast.
    public func glassRim(_ shape: some Shape, _ glass: Glass = .regular) -> some View {
        self.background { Color.clear.glassEffect(glass, in: shape) }
    }

    /// The canvas behind a screen's scroll view (light grey, like the reference); bars stay the system's own glass.
    public func recallScreen() -> some View {
        self.scrollContentBackground(.hidden)
            .background(Tokens.grey.ignoresSafeArea())
    }
}

/// Recall's mark: a rounded tile in old-Facebook blue with the viewfinder glyph and the warm ring as a thin edge.
public struct AppMark: View {
    let size: CGFloat
    public init(size: CGFloat = 52) { self.size = size }

    public var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28)
            .fill(LinearGradient(colors: [Tokens.blue, Tokens.blueDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.28)
                    .strokeBorder(LinearGradient(colors: [Tokens.ringWarm, Tokens.ringCool], startPoint: .topLeading,
                                                 endPoint: .bottomTrailing), lineWidth: 1.5)
            }
            .overlay {
                Image(systemName: "viewfinder").font(.system(size: size * 0.46, weight: .semibold)).foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A section title with an optional count on the right ("Your scans · 3 scans").
public struct SectionTitle: View {
    let title: String
    let count: String?
    public init(_ title: String, count: String? = nil) { self.title = title; self.count = count }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.weight(.bold)).foregroundStyle(Tokens.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let count { Text(count).font(.subheadline).foregroundStyle(Tokens.muted) }
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }
}

/// A small square with an SF Symbol on pale blue, at the start of a row.
public struct IconTile: View {
    let systemImage: String
    let tint: Color
    @ScaledMetric(relativeTo: .title3) private var side: CGFloat = 44  // grows with the text beside it
    public init(_ systemImage: String, tint: Color = Tokens.blueDark) { self.systemImage = systemImage; self.tint = tint }

    public var body: some View {
        Image(systemName: systemImage)
            .font(.title3.weight(.semibold))
            .foregroundStyle(tint)
            .frame(width: side, height: side)
            .background(Tokens.bluePale.opacity(0.7), in: .rect(cornerRadius: 12))
            .accessibilityHidden(true)
    }
}

/// A status chip: an icon and a word on a pale fill in the same hue, never colour alone.
public struct Chip: View {
    let title: String
    let systemImage: String
    let color: Color
    public init(_ title: String, systemImage: String, color: Color) {
        self.title = title; self.systemImage = systemImage; self.color = color
    }

    public var body: some View {
        Label(title, systemImage: systemImage)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(color.opacity(0.1), in: Capsule())
    }
}

/// A filter choice in a row of chips (like "All · To check · Checked"); the selected one is filled.
public struct FilterChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    public init(_ title: String, selected: Bool, action: @escaping () -> Void) {
        self.title = title; self.selected = selected; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? .white : Tokens.ink)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(selected ? Tokens.blueDark : .white, in: Capsule())
                .overlay(Capsule().stroke(selected ? .clear : Tokens.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A centred icon and a sentence for an empty list.
public struct EmptyState: View {
    let systemImage: String
    let text: String
    public init(_ systemImage: String, _ text: String) { self.systemImage = systemImage; self.text = text }

    public var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage).font(.system(size: 44, weight: .regular)).foregroundStyle(Tokens.line)
                .accessibilityHidden(true)
            Text(text).font(.body.weight(.medium)).foregroundStyle(Tokens.muted).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
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
        // solid enough that white text reads over any camera image; the glass is the rim and the light
        .background(Tokens.blueDeep.opacity(0.85), in: .circle)
        .glassRim(.circle)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) of 12 directions covered")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

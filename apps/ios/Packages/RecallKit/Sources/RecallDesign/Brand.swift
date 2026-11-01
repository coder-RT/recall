import SwiftUI

/// The top of every tab: the Braille mark and RECALL wordmark with the tab's line under it, then the tab's title.
/// Tabs hide the navigation bar and show this instead, so the brand is the same everywhere.
public struct BrandHeader: View {
    let title: String
    let subtitle: String

    public init(_ title: String, subtitle: String) { self.title = title; self.subtitle = subtitle }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                BrailleMark()
                VStack(alignment: .leading, spacing: 2) {
                    Wordmark()
                    Text(subtitle).font(.subheadline).foregroundStyle(Tokens.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("brand-header")
            Text(title).font(.largeTitle.weight(.bold)).foregroundStyle(Tokens.ink)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("screen-title")
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    /// A tab's root screen: the canvas, no navigation bar (the BrandHeader is the title), and the soft fade iOS 26
    /// draws where content scrolls under the status bar.
    public func tabScreen() -> some View {
        self.recallScreen()
            .toolbar(.hidden, for: .navigationBar)
            .scrollEdgeEffectStyle(.soft, for: .top)
    }
}

/// The app's motion, as SwiftUI springs (no third-party engine). Every animation goes through `MotionTokens.animation`,
/// which gives none when Reduce Motion is on.
public enum MotionTokens {
    public static let press = Animation.spring(duration: 0.25, bounce: 0.15)
    public static let reveal = Animation.spring(duration: 0.45, bounce: 0.1)
    public static let turn = Animation.spring(duration: 0.35, bounce: 0.05)  // the guide arrow

    public static func animation(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

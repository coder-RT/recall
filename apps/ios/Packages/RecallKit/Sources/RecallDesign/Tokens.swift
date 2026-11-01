import SwiftUI
import UIKit

/// The user's theme choice (Settings → Appearance). Colours follow it through dynamic tokens below.
public enum Appearance: String, CaseIterable, Sendable {
    case system, light, dark

    public var title: String { self == .system ? "Automatic" : self == .light ? "Light" : "Dark" }
    public var scheme: ColorScheme? { self == .system ? nil : self == .light ? .light : .dark }
}

/// The theme's switches, kept in UserDefaults. High contrast also follows iOS's Increase Contrast setting.
public enum Theme {
    public static let appearanceKey = "appearance"
    public static let highContrastKey = "highContrast"

    /// Read when a dynamic colour resolves (on the main thread); the app root re-renders when it changes.
    nonisolated(unsafe) public static var highContrast = UserDefaults.standard.bool(forKey: highContrastKey)
}

/// Colours shared with the website (apps/web/app/globals.css), as roles that resolve per theme:
/// light and dark in old-Facebook blue, and high contrast in black, white and yellow like the website's.
/// Every text/background pair used meets WCAG 2.2 AA in every theme (body text aims for 7:1).
public enum Tokens {
    // Brand colours, the same in every theme (gradients, decoration, the scan HUD over the camera).
    public static let blue = Color(hex: 0x3b5998)
    public static let blueDeep = Color(hex: 0x1d335c)
    public static let bluePale = Color(hex: 0xdfe3ee)
    public static let amber = Color(hex: 0xf2b33d)  // accents only, never text
    public static let ringWarm = Color(hex: 0xfeda75)  // decoration only
    public static let ringCool = Color(hex: 0x4f5bd5)  // decoration only

    // Surfaces and text.                     light      dark       high contrast (light / dark)
    public static let canvas = dynamic(0xf0f2f5, 0x0e1320, hcLight: 0xe8e8e8, hcDark: 0x000000)
    public static let card = dynamic(0xffffff, 0x1a2234, hcLight: 0xffffff, hcDark: 0x000000)
    public static let line = dynamic(0xbdc7d8, 0x34405a, hcLight: 0x000000, hcDark: 0xffffff)
    public static let ink = dynamic(0x1c1e21, 0xf0f2f5, hcLight: 0x000000, hcDark: 0xffffff)
    public static let muted = dynamic(0x4b4f56, 0xb9c1cf, hcLight: 0x1c1e21, hcDark: 0xf2f2f2)
    public static let tile = dynamic(0xe6eaf2, 0x24304a, hcLight: 0xffffff, hcDark: 0x1f1f1f)

    // Accent: `accent` for text and icons on cards; `accentFill` behind `onAccent` text (buttons, selected chips).
    public static let accent = dynamic(0x29487d, 0xa9bce3, hcLight: 0x1d335c, hcDark: 0xffd400)
    public static let accentFill = dynamic(0x29487d, 0x3b5998, hcLight: 0x1d335c, hcDark: 0xffd400)
    public static let onAccent = dynamic(0xffffff, 0xffffff, hcLight: 0xffffff, hcDark: 0x000000)

    // The main action (old-Facebook "Sign up" green) and its text colour on cards.
    public static let go = dynamic(0x1f6516, 0x1f6516, hcLight: 0x0b3d06, hcDark: 0xffd400)
    public static let onGo = dynamic(0xffffff, 0xffffff, hcLight: 0xffffff, hcDark: 0x000000)
    public static let goText = dynamic(0x1f6516, 0x7bd389, hcLight: 0x0b3d06, hcDark: 0xffd400)

    public static let danger = dynamic(0xa81c1c, 0xff8a80, hcLight: 0x8a0000, hcDark: 0xff9e9e)
    public static let dangerFill = dynamic(0xa81c1c, 0xb3261e, hcLight: 0x8a0000, hcDark: 0xff9e9e)
    public static let onDanger = dynamic(0xffffff, 0xffffff, hcLight: 0xffffff, hcDark: 0x000000)

    public static let minTarget: CGFloat = 56

    // spacing: 16 pt gutters, 12 between cards, 24 between sections
    public static let gutter: CGFloat = 16
    public static let stack: CGFloat = 12  // between cards and blocks on a screen
    public static let sectionGap: CGFloat = 12  // extra space above a section title (12 + 12 = 24 between sections)
    public static let cardRadius: CGFloat = 20
    public static let cardPadding: CGFloat = 16

    /// True when the high-contrast palette is showing (the user's switch or iOS Increase Contrast).
    public static func isHighContrast(_ traits: UITraitCollection) -> Bool {
        Theme.highContrast || traits.accessibilityContrast == .high
    }

    private static func dynamic(_ light: UInt32, _ dark: UInt32, hcLight: UInt32, hcDark: UInt32) -> Color {
        Color(uiColor: UIColor { t in
            let isDark = t.userInterfaceStyle == .dark
            let hex = isHighContrast(t) ? (isDark ? hcDark : hcLight) : (isDark ? dark : light)
            return UIColor(hex: hex)
        })
    }
}

/// Whether the high-contrast palette is on, for layout choices colours alone can't make (thicker edges, no
/// gradients). Set at the app root.
extension EnvironmentValues {
    @Entry public var highContrast = false
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                  blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }
}

extension Color {
    init(hex: UInt32) { self.init(uiColor: UIColor(hex: hex)) }
}

import SwiftUI

/// Colours shared with the website (apps/web/app/globals.css). Every text/background pair used meets WCAG 2.2 AA.
public enum Tokens {
    public static let blue = Color(red: 0x3b / 255, green: 0x59 / 255, blue: 0x98 / 255)       // 6.8:1 on white
    public static let blueDark = Color(red: 0x29 / 255, green: 0x48 / 255, blue: 0x7d / 255)   // 9:1 on white
    public static let blueDeep = Color(red: 0x1d / 255, green: 0x33 / 255, blue: 0x5c / 255)   // the sky's top: 12:1 with white
    public static let bluePale = Color(red: 0xdf / 255, green: 0xe3 / 255, blue: 0xee / 255)
    public static let grey = Color(red: 0xf0 / 255, green: 0xf2 / 255, blue: 0xf5 / 255)
    public static let line = Color(red: 0xbd / 255, green: 0xc7 / 255, blue: 0xd8 / 255)
    public static let ink = Color(red: 0x1c / 255, green: 0x1e / 255, blue: 0x21 / 255)
    public static let muted = Color(red: 0x4b / 255, green: 0x4f / 255, blue: 0x56 / 255)     // 8:1 on white
    public static let cta = Color(red: 0x1f / 255, green: 0x65 / 255, blue: 0x16 / 255)       // cta-dark: 7.2:1 with white
    public static let amber = Color(red: 0xf2 / 255, green: 0xb3 / 255, blue: 0x3d / 255)     // accents only, never text
    public static let danger = Color(red: 0xa8 / 255, green: 0x1c / 255, blue: 0x1c / 255)   // 7.6:1 on white

    /// White tint of the glass cards: enough that ink text keeps its contrast over any part of the sky.
    public static let glassTint = Color.white.opacity(0.78)

    public static let minTarget: CGFloat = 56
}

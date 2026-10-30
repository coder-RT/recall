import SwiftUI

/// Colours shared with the website (apps/web/app/globals.css). Every text/background pair used meets WCAG 2.2 AA.
public enum Tokens {
    public static let blue = Color(red: 0x3b / 255, green: 0x59 / 255, blue: 0x98 / 255)       // 6.8:1 on white
    public static let blueDark = Color(red: 0x29 / 255, green: 0x48 / 255, blue: 0x7d / 255)   // 9:1 on white
    public static let blueDeep = Color(red: 0x1d / 255, green: 0x33 / 255, blue: 0x5c / 255)   // 12:1 with white
    public static let bluePale = Color(red: 0xdf / 255, green: 0xe3 / 255, blue: 0xee / 255)
    public static let grey = Color(red: 0xf0 / 255, green: 0xf2 / 255, blue: 0xf5 / 255)      // the canvas
    public static let line = Color(red: 0xbd / 255, green: 0xc7 / 255, blue: 0xd8 / 255)
    public static let ink = Color(red: 0x1c / 255, green: 0x1e / 255, blue: 0x21 / 255)
    public static let muted = Color(red: 0x4b / 255, green: 0x4f / 255, blue: 0x56 / 255)     // 8:1 on white, 7.3:1 on grey
    public static let cta = Color(red: 0x1f / 255, green: 0x65 / 255, blue: 0x16 / 255)       // cta-dark: 7.2:1 with white
    public static let amber = Color(red: 0xf2 / 255, green: 0xb3 / 255, blue: 0x3d / 255)     // accents only, never text
    public static let danger = Color(red: 0xa8 / 255, green: 0x1c / 255, blue: 0x1c / 255)   // 7.6:1 on white
    public static let ringWarm = Color(red: 0xfe / 255, green: 0xda / 255, blue: 0x75 / 255)  // decoration only
    public static let ringCool = Color(red: 0x4f / 255, green: 0x5b / 255, blue: 0xd5 / 255)  // decoration only

    public static let minTarget: CGFloat = 56

    // spacing: 16 pt gutters, 12 between cards, 24 between sections
    public static let gutter: CGFloat = 16
    public static let cardRadius: CGFloat = 20
    public static let cardPadding: CGFloat = 16
}

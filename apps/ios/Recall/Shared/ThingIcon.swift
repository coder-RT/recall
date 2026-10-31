import RecallDesign
import RecallDomain
import SwiftUI

/// A thing's picture: our own two-layer icon (Resources/Assets.xcassets/Things, drawn by scripts/make_thing_icons.py),
/// its body in the colour the scan measured, on a white tile so it reads in every theme. An unsure thing shows the
/// box: the picture never claims more than the scan knows. Hidden from VoiceOver: the row already says the name.
struct ThingIcon: View {
    let thing: Thing
    var side: CGFloat = 44
    @ScaledMetric(relativeTo: .title3) private var scale: CGFloat = 1

    var body: some View {
        let kind = thing.iconKind
        ZStack {
            Image("thing-\(kind.rawValue)-fill").resizable().renderingMode(.template)
                .foregroundStyle(kind == .unknown ? Tokens.bluePale : (ThingColors.named(thing.color) ?? Tokens.bluePale))
            Image("thing-\(kind.rawValue)-line").resizable().renderingMode(.original)
        }
        .scaledToFit()
        .padding(side * scale * 0.12)
        .frame(width: side * scale, height: side * scale)
        .background(.white, in: .rect(cornerRadius: side * scale * 0.27))
        .overlay(RoundedRectangle(cornerRadius: side * scale * 0.27).stroke(Tokens.line.opacity(0.7), lineWidth: 1))
        .accessibilityHidden(true)
        .accessibilityIdentifier("icon-\(kind.rawValue)")
    }
}

/// The colour names the scan and the user use, as colours (one map for icons and swatches).
enum ThingColors {
    static let all: [String: Color] = [
        "black": Color(red: 0.16, green: 0.16, blue: 0.17), "white": .white, "grey": .gray, "gray": .gray,
        "red": Color(red: 0.86, green: 0.23, blue: 0.2), "orange": .orange, "yellow": .yellow, "green": .green,
        "blue": Color(red: 0.23, green: 0.35, blue: 0.6), "purple": .purple, "pink": .pink, "brown": .brown,
        "beige": Color(red: 0.89, green: 0.82, blue: 0.69),
    ]

    static func named(_ name: String?) -> Color? { name.flatMap { all[$0.lowercased()] } }
}

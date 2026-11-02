import RecallDesign
import RecallDomain
import SwiftUI

/// A room's map as robots see it: free floor white, furniture and walls dark, unseen parts faint, and the things
/// Recall remembers as blue dots. Used by Find (one card per room) and Robot Access, so both always look the same.
/// Hidden from VoiceOver: the card around it says what it shows.
struct RoomMapCanvas: View {
    let package: RobotMapPackage

    var body: some View {
        Canvas { ctx, size in
            let m = package.map
            let k = min(size.width / CGFloat(m.width), size.height / CGFloat(m.height))
            let ox = (size.width - CGFloat(m.width) * k) / 2, oy = (size.height - CGFloat(m.height) * k) / 2
            for r in 0..<m.height {
                for c in 0..<m.width {
                    let colour: Color = switch m.cell(row: r, column: c) {
                    case .free: .white
                    case .occupied: Tokens.ink
                    case .unknown: Tokens.line.opacity(0.5)
                    }
                    ctx.fill(Path(CGRect(x: ox + CGFloat(c) * k, y: oy + CGFloat(r) * k, width: k + 0.5, height: k + 0.5)),
                             with: .color(colour))
                }
            }
            for t in package.things {
                let p = m.pixel(x: t.x, y: t.y)
                let at = CGPoint(x: ox + CGFloat(p.column) * k, y: oy + CGFloat(p.row) * k)
                ctx.fill(Path(ellipseIn: CGRect(x: at.x - 6, y: at.y - 6, width: 12, height: 12)), with: .color(.white))
                ctx.fill(Path(ellipseIn: CGRect(x: at.x - 4.5, y: at.y - 4.5, width: 9, height: 9)), with: .color(Tokens.blue))
            }
        }
        .background(Tokens.tile, in: .rect(cornerRadius: 14))
    }
}

/// Floor · Furniture and walls · Things: what the map's colours mean.
struct RoomMapLegend: View {
    @ViewBuilder private var swatches: some View {
        Swatch(colour: .white, edge: true, "Floor")
        Swatch(colour: Tokens.ink, "Furniture and walls")
        Swatch(colour: Tokens.blue, "Things")
    }

    var body: some View {
        // one line when it fits, else one swatch per line (large text)
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { swatches }
            VStack(alignment: .leading, spacing: 6) { swatches }
        }
        .font(.footnote).foregroundStyle(Tokens.muted)
        // visible words are never hidden from VoiceOver: the key's words are read together, and wrap at large text
        .accessibilityElement(children: .combine)
    }
}

private struct Swatch: View {
    let colour: Color
    let edge: Bool
    let text: String
    init(colour: Color, edge: Bool = false, _ text: String) { self.colour = colour; self.edge = edge; self.text = text }
    var body: some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3).fill(colour).frame(width: 12, height: 12)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Tokens.line, lineWidth: edge ? 1 : 0))
            Text(text)
        }
    }
}

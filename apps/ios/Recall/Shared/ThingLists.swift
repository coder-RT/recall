import RecallDesign
import RecallDomain
import SwiftUI

/// What a row in a grouped list is for: Found reviews (a tap opens the editor), Find goes (a tap walks you there).
enum ThingListMode { case review, find }

/// A room (or height, or kind): its heading with counts, folding away with a tap, then its things in compact cards,
/// one card per piece of furniture when grouped by place. Shared by Find and Found.
struct GroupSection: View {
    let group: ThingGroup
    let folded: Bool
    let inSpots: Bool
    let mode: ThingListMode
    let toggle: () -> Void
    let open: (Thing) -> Void
    let guide: (Thing) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(reduceMotion ? nil : .snappy) { toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(group.title).font(.title3.weight(.bold)).foregroundStyle(Tokens.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Text(counts).font(.subheadline).foregroundStyle(Tokens.muted)
                    Image(systemName: "chevron.down").font(.footnote.weight(.bold)).foregroundStyle(Tokens.muted)
                        .rotationEffect(.degrees(folded ? -90 : 0))
                }
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plainTap)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(mode == .review ? group.summary : summaryWithoutChecks)
            .accessibilityValue(folded ? "Folded" : "Open")
            .accessibilityHint(folded ? "Shows its things." : "Hides its things.")
            .accessibilityAddTraits([.isHeader, .isButton])
            .accessibilityIdentifier("\(mode == .find ? "find-" : "")group-\(group.id)")
            if !folded {
                if inSpots && !group.spots.isEmpty {
                    ForEach(group.spots) { spot in
                        Text(spot.title.uppercased()).font(.caption.weight(.bold)).foregroundStyle(Tokens.muted)
                            .padding(.top, 2)
                            .accessibilityAddTraits(.isHeader)
                        RowsCard(things: spot.things, atFurniture: true, mode: mode, open: open, guide: guide)
                    }
                } else {
                    RowsCard(things: group.things, atFurniture: false, mode: mode, open: open, guide: guide)
                }
            }
        }
        .padding(.top, 6)
    }

    // Find doesn't ask the user to check things, so its headings just count them
    private var counts: String {
        let n = group.count == 1 ? "1 thing" : "\(group.count) things"
        return group.toCheck == 0 || mode == .find ? n : "\(n) · \(group.toCheck) to check"
    }

    private var summaryWithoutChecks: String { "\(group.title), \(group.count == 1 ? "1 thing" : "\(group.count) things")" }
}

/// Several things in one card, a divider between them.
struct RowsCard: View {
    let things: [Thing]
    let atFurniture: Bool
    let mode: ThingListMode
    let open: (Thing) -> Void
    let guide: (Thing) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(things.enumerated()), id: \.element.id) { i, thing in
                if i > 0 { Divider().overlay(Tokens.line.opacity(0.5)).padding(.leading, 58) }
                switch mode {
                case .review:
                    Button { open(thing) } label: { ThingListRow(thing: thing, atFurniture: atFurniture, mode: mode) }
                        .buttonStyle(.plainTap)
                        .accessibilityHint("Opens it to correct or confirm.")
                        .accessibilityAction(named: "Take me there") { guide(thing) }
                        .contextMenu { Button("Take me there", systemImage: "figure.walk") { guide(thing) } }
                case .find:
                    Button { guide(thing) } label: { ThingListRow(thing: thing, atFurniture: atFurniture, mode: mode) }
                        .buttonStyle(.plainTap)
                        .accessibilityHint("Walks you there with spoken directions.")
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 4)
        .background(Tokens.card, in: .rect(cornerRadius: Tokens.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Tokens.cardRadius).stroke(Tokens.line.opacity(0.6), lineWidth: 0.5))
    }
}

/// One thing, compact: its icon, its name, and where (just "on, waist height" under a furniture heading that
/// already names the place). Found adds a small Check mark when unsure and a chevron; Find a Go pill.
struct ThingListRow: View {
    let thing: Thing
    let atFurniture: Bool
    let mode: ThingListMode

    var body: some View {
        HStack(spacing: 12) {
            ThingIcon(thing: thing, side: 44)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(thing.title.capitalizedFirst).font(.headline).foregroundStyle(Tokens.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if mode == .review {
                        if thing.needsReview && !thing.confirmed {
                            Label(thing.checkMark, systemImage: "questionmark.circle.fill").labelStyle(.titleAndIcon)
                                .font(.caption.weight(.bold)).foregroundStyle(Tokens.danger).fixedSize()
                        } else if thing.confirmed {
                            Image(systemName: "checkmark.seal.fill").font(.caption).foregroundStyle(Tokens.goText)
                                .accessibilityLabel("Checked")
                        }
                    }
                }
                Text(line).font(.subheadline).foregroundStyle(Tokens.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            switch mode {
            case .review:
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Tokens.muted)
                    .accessibilityHidden(true)
            case .find:
                Label("Go", systemImage: "figure.walk")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Tokens.onAccent)
                    .padding(.horizontal, 14).frame(minHeight: 40)
                    .background(Tokens.accentFill, in: Capsule())
                    .fixedSize()
            }
        }
        .frame(minHeight: Tokens.minTarget)
        .padding(.vertical, 6)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private var line: String {
        guard atFurniture, thing.landmark != nil else { return thing.place.capitalizedFirst }
        let rel = (thing.relation ?? "near").replacingOccurrences(of: "_", with: " ")
        return "\(rel.capitalizedFirst) · \(thing.heightBand) height"
    }

    // VoiceOver reads the whole place, even where the screen shortens it under a furniture heading:
    // "Grey bag, near the desk, knee height, Go"
    private var label: String {
        switch mode {
        case .review: "\(thing.title.capitalizedFirst). \(thing.place.capitalizedFirst). \(thing.certainty)."
        case .find: "\(thing.title.capitalizedFirst), \(thing.place), Go"
        }
    }
}

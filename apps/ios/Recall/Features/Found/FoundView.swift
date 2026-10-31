import RecallDesign
import RecallDomain
import SwiftUI

/// After a scan: everything Recall found, grouped by room and the furniture it's on or near (or by height, or by
/// kind), the unsure ones first in each group. Tapping one lets the user fix its name, colour, height or note,
/// confirm it, or forget it. The user's values win over what the models measured.
struct FoundView: View {
    @Environment(ThingsModel.self) private var things
    @Environment(Router.self) private var router
    @State private var editing: Thing?
    @State private var query = ""
    @State private var filter = Filter.all
    @State private var folded: Set<String> = []
    @AppStorage("found.groupBy") private var groupBy = ThingGroups.By.place

    enum Filter { case all, unsure, checked }

    private var shown: [Thing] {
        things.things.filter { t in
            (filter == .all || (filter == .unsure ? t.needsReview : t.confirmed))
                && (query.isEmpty || "\(t.title) \(t.label) \(t.place) \(t.room ?? "")".localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    BrandHeader("Found", subtitle: "Check what Recall found")
                    if things.loading && !things.loaded {
                        ProgressView("Loading what Recall found…").frame(maxWidth: .infinity).padding(.vertical, 32)
                    } else if let error = things.error {
                        ErrorBox(text: error)
                        Button("Open Settings", systemImage: "gearshape") { router.tab = .settings }
                            .buttonStyle(SolidPillStyle(fill: Tokens.card, text: Tokens.accent, edge: Tokens.line, compact: true))
                    } else if things.things.isEmpty {
                        EmptyState("shippingbox", "Nothing remembered yet. Scan a room and upload it first.")
                    } else {
                        SearchField(text: $query)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                FilterChip("All", selected: filter == .all) { filter = .all }
                                FilterChip("To check (\(things.unsureCount))", selected: filter == .unsure) { filter = .unsure }
                                FilterChip("Checked", selected: filter == .checked) { filter = .checked }
                            }
                        }
                        GroupByBar(by: $groupBy)
                        if shown.isEmpty {
                            EmptyState("magnifyingglass", "Nothing matches.")
                        }
                        ForEach(ThingGroups.group(shown, by: groupBy)) { group in
                            GroupSection(group: group, folded: folded.contains(group.id), inSpots: groupBy == .place,
                                         toggle: { toggle(group.id) }, open: { editing = $0 },
                                         guide: { router.guiding = $0 })
                        }
                    }
                }
                .padding(.horizontal, Tokens.gutter)
                .padding(.bottom, 24)
            }
            .tabScreen()
            .task { if !things.loaded { await things.refresh() } }
            .refreshable { await things.refresh() }
            .sheet(item: $editing) { EditThingView(thing: $0) }
        }
    }

    private func toggle(_ id: String) {
        if folded.contains(id) { folded.remove(id) } else { folded.insert(id) }
    }
}

/// Place · Height · Kind: how the list is grouped (remembered).
private struct GroupByBar: View {
    @Binding var by: ThingGroups.By

    var body: some View {
        HStack(spacing: 8) {
            Text("Group by").font(.subheadline.weight(.semibold)).foregroundStyle(Tokens.muted)
            ForEach(ThingGroups.By.allCases, id: \.self) { option in
                FilterChip(option.title, selected: by == option) { by = option }
                    .accessibilityLabel("Group by \(option.title.lowercased())")
            }
        }
    }
}

extension ThingGroups.By {
    var title: String {
        switch self {
        case .place: "Place"
        case .height: "Height"
        case .kind: "Kind"
        }
    }
}

/// A room (or height, or kind): its heading with counts, folding away with a tap, then its things in compact cards,
/// one card per piece of furniture when grouped by place.
private struct GroupSection: View {
    let group: ThingGroup
    let folded: Bool
    let inSpots: Bool
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
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(group.summary)
            .accessibilityValue(folded ? "Folded" : "Open")
            .accessibilityHint(folded ? "Shows its things." : "Hides its things.")
            .accessibilityAddTraits([.isHeader, .isButton])
            .accessibilityIdentifier("group-\(group.id)")
            if !folded {
                if inSpots && !group.spots.isEmpty {
                    ForEach(group.spots) { spot in
                        Text(spot.title.uppercased()).font(.caption.weight(.bold)).foregroundStyle(Tokens.muted)
                            .padding(.top, 2)
                            .accessibilityAddTraits(.isHeader)
                        RowsCard(things: spot.things, atFurniture: true, open: open, guide: guide)
                    }
                } else {
                    RowsCard(things: group.things, atFurniture: false, open: open, guide: guide)
                }
            }
        }
        .padding(.top, 6)
    }

    private var counts: String {
        let n = group.count == 1 ? "1 thing" : "\(group.count) things"
        return group.toCheck == 0 ? n : "\(n) · \(group.toCheck) to check"
    }
}

/// Several things in one card, a divider between them.
private struct RowsCard: View {
    let things: [Thing]
    let atFurniture: Bool
    let open: (Thing) -> Void
    let guide: (Thing) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(things.enumerated()), id: \.element.id) { i, thing in
                if i > 0 { Divider().overlay(Tokens.line.opacity(0.5)).padding(.leading, 58) }
                Button { open(thing) } label: { FoundRow(thing: thing, atFurniture: atFurniture) }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens it to correct or confirm.")
                    .accessibilityAction(named: "Take me there") { guide(thing) }
                    .contextMenu { Button("Take me there", systemImage: "figure.walk") { guide(thing) } }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 4)
        .background(Tokens.card, in: .rect(cornerRadius: Tokens.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Tokens.cardRadius).stroke(Tokens.line.opacity(0.6), lineWidth: 0.5))
    }
}

/// Search within the list (in the page, so it shows with the brand header instead of a navigation bar).
private struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Tokens.muted).accessibilityHidden(true)
            TextField("Search things or places", text: $text, prompt: Text("Search things or places").foregroundStyle(Tokens.muted),
                      axis: .vertical)  // grows with large text instead of clipping
                .foregroundStyle(Tokens.ink)
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .accessibilityIdentifier("search")
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Tokens.muted) }
                    .accessibilityLabel("Clear the search")
                    .frame(minWidth: 44, minHeight: 44)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .background(Tokens.card, in: Capsule())
        .overlay(Capsule().stroke(Tokens.line, lineWidth: 1))
    }
}

/// One thing, compact: its icon, its name with a small Check mark when unsure, and where (just "on, waist height"
/// under a furniture heading that already names the place).
private struct FoundRow: View {
    let thing: Thing
    let atFurniture: Bool

    var body: some View {
        HStack(spacing: 12) {
            ThingIcon(thing: thing, side: 44)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(thing.title.capitalizedFirst).font(.headline).foregroundStyle(Tokens.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if thing.needsReview && !thing.confirmed {
                        Label("Check", systemImage: "questionmark.circle.fill").labelStyle(.titleAndIcon)
                            .font(.caption.weight(.bold)).foregroundStyle(Tokens.danger).fixedSize()
                    } else if thing.confirmed {
                        Image(systemName: "checkmark.seal.fill").font(.caption).foregroundStyle(Tokens.goText)
                            .accessibilityLabel("Checked")
                    }
                }
                Text(line).font(.subheadline).foregroundStyle(Tokens.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Tokens.muted)
                .accessibilityHidden(true)
        }
        .frame(minHeight: Tokens.minTarget)
        .padding(.vertical, 6)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(thing.title.capitalizedFirst). \(thing.place.capitalizedFirst). \(thing.certainty).")
    }

    private var line: String {
        guard atFurniture, thing.landmark != nil else { return thing.place.capitalizedFirst }
        let rel = (thing.relation ?? "near").replacingOccurrences(of: "_", with: " ")
        return "\(rel.capitalizedFirst) · \(thing.heightBand) height"
    }
}

import RecallDesign
import RecallDomain
import SwiftUI

/// After a scan: everything Recall found, the unsure ones first. Tapping one lets the user fix its name, colour,
/// height or note, confirm it, or forget it. The user's values win over what the models measured.
struct FoundView: View {
    @Environment(ThingsModel.self) private var things
    @Environment(Router.self) private var router
    @State private var editing: Thing?
    @State private var query = ""
    @State private var filter = Filter.all

    enum Filter { case all, unsure, checked }

    private var shown: [Thing] {
        things.things.filter { t in
            (filter == .all || (filter == .unsure ? t.needsReview : t.confirmed))
                && (query.isEmpty || "\(t.title) \(t.label) \(t.place)".localizedCaseInsensitiveContains(query))
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
                        SectionTitle(heading, count: shown.count == 1 ? "1 thing" : "\(shown.count) things")
                        if shown.isEmpty {
                            EmptyState("magnifyingglass", "Nothing matches.")
                        }
                        ForEach(shown) { thing in
                            Button { editing = thing } label: { FoundRow(thing: thing) }
                                .buttonStyle(.plain)
                                .accessibilityHint("Opens it to correct or confirm.")
                                .accessibilityAction(named: "Take me there") { router.guiding = thing }
                                .contextMenu {
                                    Button("Take me there", systemImage: "figure.walk") { router.guiding = thing }
                                }
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

    private var heading: String {
        switch filter {
        case .all: "Everything"
        case .unsure: "Please check"
        case .checked: "Checked by you"
        }
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

private struct FoundRow: View {
    let thing: Thing
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: 12) {
            Swatch(color: thing.color)
            VStack(alignment: .leading, spacing: 3) {
                // the chip moves under the name when the text is large
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                    : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
                layout {
                    Text(thing.title.capitalizedFirst).font(.headline).foregroundStyle(Tokens.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                    if thing.needsReview {
                        Chip("Check", systemImage: "questionmark.circle.fill", color: Tokens.danger).fixedSize()
                    } else if thing.confirmed {
                        Chip("Checked", systemImage: "checkmark.circle.fill", color: Tokens.goText).fixedSize()
                    }
                }
                Text(thing.place.capitalizedFirst).font(.subheadline).foregroundStyle(Tokens.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(thing.certainty).font(.footnote).foregroundStyle(Tokens.muted)
            }
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Tokens.muted)
                .accessibilityHidden(true)
        }
        .frame(minHeight: Tokens.minTarget)
        .card(padding: 14)
        .accessibilityElement(children: .combine)
    }
}

private struct Swatch: View {
    let color: String?
    @ScaledMetric(relativeTo: .title3) private var side: CGFloat = 44

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(Tokens.tile)
            if let c = color.flatMap(Self.colors.index(forKey:)).map({ Self.colors.values[$0] }) {
                Circle().fill(c).frame(width: 22, height: 22).overlay(Circle().stroke(Tokens.line, lineWidth: 1))
            } else {
                Image(systemName: "shippingbox").font(.title3.weight(.semibold)).foregroundStyle(Tokens.accent)
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }

    static let colors: [String: Color] = [
        "black": .black, "white": .white, "grey": .gray, "gray": .gray, "red": .red, "orange": .orange,
        "yellow": .yellow, "green": .green, "blue": .blue, "purple": .purple, "pink": .pink, "brown": .brown,
        "beige": Color(red: 0.89, green: 0.82, blue: 0.69),
    ]
}


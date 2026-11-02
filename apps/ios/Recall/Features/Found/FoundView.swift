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
                VStack(alignment: .leading, spacing: Tokens.stack) {
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
                                         mode: .review, toggle: { toggle(group.id) }, open: { editing = $0 },
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
            .keyboardDismissable()  // scroll or Done hides the keyboard; a tap outside does too (KeyboardDismissal)
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
                .limited($text, to: TextInput.search)
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

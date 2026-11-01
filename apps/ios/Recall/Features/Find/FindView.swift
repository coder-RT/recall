import RecallApplication
import RecallDesign
import RecallDomain
import SwiftUI

/// Find: ask where something is (typed or spoken), hear the answer, and be walked there; or pick a room's map and a
/// thing from the list below it, grouped by room and the furniture it's on or near, and go.
struct FindView: View {
    @Environment(\.container) private var container
    @Environment(ThingsModel.self) private var things
    @Environment(ScansModel.self) private var scans
    @Environment(RoomMapsModel.self) private var maps
    @Environment(Router.self) private var router
    @State private var model: FindModel?
    /// The room picked on its map card; nil shows every room.
    @State private var room: String?
    @State private var folded: Set<String> = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    BrandHeader("Find", subtitle: "Ask where something is")
                    if let model { AskCard(model: model) { router.guiding = $0 } }

                    if !rooms.isEmpty {
                        SectionTitle("Your rooms", count: rooms.count == 1 ? "1 room" : "\(rooms.count) rooms")
                            .padding(.top, 12)
                        RoomCarousel(rooms: rooms, things: things.things, picked: $room)
                    }

                    SectionTitle("Your things", count: things.things.isEmpty ? nil : count)
                        .padding(.top, 12)
                    if let error = things.error {
                        ErrorBox(text: error)
                    } else if things.things.isEmpty, things.loaded {
                        EmptyState("shippingbox", "Nothing remembered yet. Scan a room and upload it first.")
                    }
                    // like Found: a heading per room (even just one), then a card per piece of furniture
                    ForEach(ThingGroups.byPlace(shown)) { group in
                        GroupSection(group: group, folded: folded.contains(group.id), inSpots: true, mode: .find,
                                     toggle: { toggle(group.id) }, open: { router.guiding = $0 },
                                     guide: { router.guiding = $0 })
                    }
                }
                .padding(.horizontal, Tokens.gutter)
                .padding(.bottom, 24)
            }
            .tabScreen()
            .task {
                if model == nil { model = container?.findModel() }
                if !things.loaded { await things.refresh() }
            }
            .refreshable {
                maps.forget()
                await things.refresh()
            }
            // a room that's gone (erased, or renamed) stops filtering the list
            .onChange(of: rooms) { if let room, !rooms.contains(room) { self.room = nil } }
        }
    }

    /// Rooms with things, most first, then rooms scanned on this phone that have nothing found yet.
    private var rooms: [String] {
        ThingGroups.rooms(things.things, scanned: scans.scans.filter { $0.state == .processed }.map(\.room))
    }

    private var shown: [Thing] { room.map { r in things.things.filter { $0.room == r } } ?? things.things }

    private var count: String {
        let n = shown.count
        return (n == 1 ? "1 thing" : "\(n) things") + (room.map { " in \($0)" } ?? "")
    }

    private func toggle(_ id: String) {
        if folded.contains(id) { folded.remove(id) } else { folded.insert(id) }
    }
}

/// One map card per room, side by side: swipe to see the next room, tap one to show only its things below.
private struct RoomCarousel: View {
    let rooms: [String]
    let things: [Thing]
    @Binding var picked: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if rooms.count > 1 {
                FilterChip("All rooms", selected: picked == nil) { pick(nil) }
                    .accessibilityHint("Shows every room's things.")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(rooms, id: \.self) { room in
                        RoomMapCard(room: room, count: things.filter { $0.room == room }.count, picked: picked == room) {
                            pick(picked == room ? nil : room)
                        }
                        // one room fills the width; with more, the next one peeks in so it's clear there's more
                        .containerRelativeFrame(.horizontal) { width, _ in rooms.count == 1 ? width : width * 0.86 }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
            .accessibilityIdentifier("room-maps")
            RoomMapLegend().padding(.top, 2)
        }
    }

    private func pick(_ room: String?) {
        withAnimation(reduceMotion ? nil : .snappy) { picked = room }
    }
}

/// A room's map in a card: its name, how many things, and the map with the things as dots.
private struct RoomMapCard: View {
    let room: String
    let count: Int
    let picked: Bool
    let tap: () -> Void
    @Environment(RoomMapsModel.self) private var maps

    var body: some View {
        Button(action: tap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(room).font(.headline).foregroundStyle(Tokens.ink)
                        .fixedSize(horizontal: false, vertical: true)  // wraps at large text instead of clipping
                    Spacer(minLength: 8)
                    Text(things).font(.subheadline).foregroundStyle(Tokens.muted)
                }
                Group {
                    switch maps.maps[room] {
                    case .ready(let package): RoomMapCanvas(package: package)
                    case .notReady:
                        Text("Map not ready yet. It appears once your Mac has processed a scan of this room.")
                            .font(.subheadline).foregroundStyle(Tokens.muted).multilineTextAlignment(.center)
                            .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Tokens.tile, in: .rect(cornerRadius: 14))
                    case .loading, nil:
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Tokens.tile, in: .rect(cornerRadius: 14))
                    }
                }
                .frame(height: 190)
            }
            .card()
            .overlay(RoundedRectangle(cornerRadius: Tokens.cardRadius).stroke(Tokens.accent, lineWidth: picked ? 3 : 0))
        }
        .buttonStyle(.plain)
        .task { await maps.load(room) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(room) map, \(things)")
        .accessibilityValue(picked ? "Selected" : "Not selected")
        .accessibilityHint(picked ? "Shows every room's things again." : "Shows only this room's things.")
        .accessibilityAddTraits(picked ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("room-map-\(room)")
    }

    private var things: String { count == 1 ? "1 thing" : "\(count) things" }
}

/// The question, the two ways to ask it, and the answer.
private struct AskCard: View {
    @Bindable var model: FindModel
    let go: (Thing) -> Void
    @FocusState private var typing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Where is…?").font(.headline).foregroundStyle(Tokens.ink).accessibilityAddTraits(.isHeader)
                TextField("Your question", text: $model.question,
                          prompt: Text("e.g. where are my keys?").foregroundStyle(Tokens.muted), axis: .vertical)
                    .font(.body).foregroundStyle(Tokens.ink)
                    .focused($typing)
                    .submitLabel(.search)
                    .onSubmit { Task { await model.submit() } }
                    .padding(12)
                    .frame(minHeight: 48, alignment: .leading)
                    .background(Tokens.canvas, in: .rect(cornerRadius: 14))
                    .accessibilityIdentifier("question")
                HStack(spacing: 10) {
                    if model.state == .listening {
                        Button { Task { await model.toggleListening() } } label: { Label("Stop", systemImage: "stop.circle.fill") }
                            .buttonStyle(SolidPillStyle(fill: Tokens.dangerFill, text: Tokens.onDanger))
                            .accessibilityHint("Stops listening and asks.")
                    } else {
                        Button {
                            typing = false
                            Task { await model.toggleListening() }
                        } label: { Label("Speak", systemImage: "mic.fill") }
                            .buttonStyle(SolidPillStyle(fill: Tokens.card, text: Tokens.accent, edge: Tokens.line))
                            .accessibilityHint("Tap, say your question, then tap again.")
                            .disabled(model.busy)
                    }
                    Button {
                        typing = false
                        Task { await model.submit() }
                    } label: { Label("Ask", systemImage: "magnifyingglass") }
                        .buttonStyle(SolidPillStyle(fill: Tokens.go, text: Tokens.onGo))
                        .disabled(model.busy || model.state == .listening)
                }
            }
            .card()

            switch model.state {
            case .answered(let result): AnswerCard(result: result, go: go)
            case .failed(let message): ErrorBox(text: message)
            case .listening: ProgressView("Listening… tap Stop when you're done.").frame(maxWidth: .infinity).padding()
            case .transcribing: ProgressView("Listening to your question…").frame(maxWidth: .infinity).padding()
            case .thinking: ProgressView("Asking Recall…").frame(maxWidth: .infinity).padding()
            case .idle: EmptyView()
            }
        }
    }
}

/// The Guide's answer, with the way there.
private struct AnswerCard: View {
    let result: AskWhereIs.Result
    let go: (Thing) -> Void
    @State private var showingWhy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                IconTile("text.bubble.fill")
                Text(result.answer.text).font(.body).foregroundStyle(Tokens.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            HStack(spacing: 10) {
                if let thing = result.thing {
                    Button { go(thing) } label: { Label("Take me there", systemImage: "figure.walk") }
                        .buttonStyle(SolidPillStyle(fill: Tokens.accentFill, text: Tokens.onAccent))
                        .accessibilityHint("Spoken directions to your \(thing.title).")
                }
                if let id = result.answer.answerId, result.thing != nil {
                    Button { showingWhy = true } label: { Label("Why?", systemImage: "questionmark.circle") }
                        .buttonStyle(SolidPillStyle(fill: Tokens.card, text: Tokens.accent, edge: Tokens.line))
                        .accessibilityHint("What the camera saw, when, and which models found it.")
                        .sheet(isPresented: $showingWhy) { NavigationStack { EvidenceView(answerId: id) } }
                }
            }
        }
        .card()
    }
}

import RecallApplication
import RecallDesign
import RecallDomain
import SwiftUI

/// Find: ask where something is (typed or spoken), hear the answer, and be walked there; or pick a thing from the
/// list and go.
struct FindView: View {
    @Environment(\.container) private var container
    @Environment(ThingsModel.self) private var things
    @Environment(Router.self) private var router
    @State private var model: FindModel?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    BrandHeader("Find", subtitle: "Ask where something is")
                    if let model { AskCard(model: model) { router.guiding = $0 } }

                    SectionTitle("Your things", count: things.things.isEmpty ? nil : count)
                        .padding(.top, 12)
                    if let error = things.error {
                        ErrorBox(text: error)
                    } else if things.things.isEmpty, things.loaded {
                        EmptyState("shippingbox", "Nothing remembered yet. Scan a room and upload it first.")
                    }
                    ForEach(things.things) { thing in
                        Button { router.guiding = thing } label: { ThingRow(thing: thing) }
                            .buttonStyle(.plain)
                            .accessibilityHint("Walks you there with spoken directions.")
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
            .refreshable { await things.refresh() }
        }
    }

    private var count: String { things.things.count == 1 ? "1 thing" : "\(things.things.count) things" }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                IconTile("text.bubble.fill")
                Text(result.answer.text).font(.body).foregroundStyle(Tokens.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            if let thing = result.thing {
                Button { go(thing) } label: { Label("Take me there", systemImage: "figure.walk") }
                    .buttonStyle(SolidPillStyle(fill: Tokens.accentFill, text: Tokens.onAccent))
                    .accessibilityHint("Spoken directions to your \(thing.title).")
            }
        }
        .card()
    }
}

/// A thing in the list: what it is, where it is, and a Go arrow.
private struct ThingRow: View {
    let thing: Thing

    var body: some View {
        HStack(spacing: 12) {
            IconTile("shippingbox")
            VStack(alignment: .leading, spacing: 3) {
                Text(thing.title.capitalizedFirst).font(.headline).foregroundStyle(Tokens.ink)
                Text(thing.place.capitalizedFirst).font(.subheadline).foregroundStyle(Tokens.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Label("Go", systemImage: "figure.walk")
                .font(.subheadline.weight(.semibold)).foregroundStyle(Tokens.onAccent)
                .padding(.horizontal, 14).frame(minHeight: 40)
                .background(Tokens.accentFill, in: Capsule())
                .fixedSize()
        }
        .frame(minHeight: Tokens.minTarget)
        .card(padding: 14)
        // VoiceOver reads the row's own words: "Grey bag, near the desk, knee height, Go"
        .accessibilityElement(children: .combine)
    }
}

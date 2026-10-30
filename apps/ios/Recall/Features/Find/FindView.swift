import RecallDesign
import RecallNetworking
import RecallVoice
import SwiftUI

/// Find: ask where something is (typed or spoken), hear the answer, and be walked there; or pick a thing from the
/// list and go.
struct FindView: View {
    @Environment(AppModel.self) private var model
    @State private var question = ""
    @State private var state = AskState.idle
    @State private var objects: [RememberedObject] = []
    @State private var listError: String?
    @State private var recorder = VoiceRecorder()
    @State private var listening = false
    @FocusState private var typing: Bool

    enum AskState: Equatable {
        case idle, transcribing, thinking
        case answered(Answer)
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    askCard
                    switch state {
                    case .answered(let answer): AnswerCard(answer: answer, title: title(for: answer)) { go(answer) }
                    case .failed(let message): ErrorBox(text: message)
                    case .transcribing: ProgressView("Listening to your question…").frame(maxWidth: .infinity).padding()
                    case .thinking: ProgressView("Asking Recall…").frame(maxWidth: .infinity).padding()
                    case .idle: EmptyView()
                    }

                    SectionTitle("Your things", count: objects.isEmpty ? nil : objects.count == 1 ? "1 thing" : "\(objects.count) things")
                        .padding(.top, 12)
                    if let listError {
                        ErrorBox(text: listError)
                    } else if objects.isEmpty {
                        EmptyState("shippingbox", "Nothing remembered yet. Scan a room and upload it first.")
                    }
                    ForEach(objects) { obj in
                        Button { model.guiding = GuideTarget(id: obj.id, title: obj.title) } label: { ThingRow(object: obj) }
                            .buttonStyle(.plain)
                            .accessibilityHint("Walks you there with spoken directions.")
                    }
                }
                .padding(.horizontal, Tokens.gutter)
                .padding(.bottom, 24)
            }
            .recallScreen()
            .navigationTitle("Find")
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private var askCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Where is…?").font(.headline).foregroundStyle(Tokens.ink).accessibilityAddTraits(.isHeader)
            TextField("Your question", text: $question, prompt: Text("e.g. where are my keys?").foregroundStyle(Tokens.muted),
                      axis: .vertical)
                .font(.body).foregroundStyle(Tokens.ink)
                .focused($typing)
                .submitLabel(.search)
                .onSubmit { Task { await ask(question) } }
                .padding(12)
                .frame(minHeight: 48, alignment: .leading)
                .background(Tokens.canvas, in: .rect(cornerRadius: 14))
                .accessibilityIdentifier("question")
            HStack(spacing: 10) {
                Group {
                    if listening {
                        Button { Task { await toggleListening() } } label: { Label("Stop", systemImage: "stop.circle.fill") }
                            .buttonStyle(SolidPillStyle(fill: Tokens.dangerFill, text: Tokens.onDanger))
                        .accessibilityHint("Stops listening and asks.")
                    } else {
                        Button { Task { await toggleListening() } } label: { Label("Speak", systemImage: "mic.fill") }
                            .buttonStyle(SolidPillStyle(fill: Tokens.card, text: Tokens.accent, edge: Tokens.line))
                        .accessibilityHint("Tap, say your question, then tap again.")
                    }
                }
                .disabled(busy)
                Button { Task { await ask(question) } } label: { Label("Ask", systemImage: "magnifyingglass") }
                    .buttonStyle(SolidPillStyle(fill: Tokens.go, text: Tokens.onGo))
                    .disabled(busy)
            }
        }
        .card()
    }

    private var busy: Bool { state == .thinking || state == .transcribing }

    private func title(for answer: Answer) -> String {
        objects.first { $0.id == answer.objectId }?.title ?? "it"
    }

    private func go(_ answer: Answer) {
        guard let id = answer.objectId else { return }
        model.guiding = GuideTarget(id: id, title: title(for: answer))
    }

    private func toggleListening() async {
        if listening {
            listening = false
            guard let wav = recorder.stop(), let api = model.api else { return }
            state = .transcribing
            do {
                let text = try await api.transcribe(wav: wav)
                question = text
                await ask(text)
            } catch {
                state = .failed(APIError.explain(error))
            }
        } else {
            typing = false
            Haptics.tap()
            listening = await recorder.start()
            if !listening {
                state = .failed("Recall can't use the microphone. Allow it in Settings → Privacy → Microphone, or type the question.")
            }
        }
    }

    private func ask(_ text: String) async {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            model.announcer.say("Type or say what you're looking for first.")
            return
        }
        guard let api = model.api else {
            state = .failed(model.setupProblem ?? "Set up the Mac in Settings first.")
            return
        }
        typing = false
        state = .thinking
        do {
            let answer = try await api.ask(homeId: model.homeId, question: q)
            state = .answered(answer)
            model.announcer.say(answer.text + (answer.objectId == nil ? "" : " Tap Take me there for directions."), interrupt: true)
        } catch {
            state = .failed(APIError.explain(error))
        }
    }

    private func load() async {
        guard let api = model.api else {
            listError = model.setupProblem
            return
        }
        do {
            objects = try await api.objects(homeId: model.homeId).sorted { $0.title < $1.title }
            listError = nil
        } catch {
            listError = APIError.explain(error)
        }
    }
}

/// The Guide's answer, with the way there.
private struct AnswerCard: View {
    let answer: Answer
    let title: String
    let go: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                IconTile("text.bubble.fill")
                Text(answer.text).font(.body).foregroundStyle(Tokens.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            if answer.objectId != nil {
                Button(action: go) { Label("Take me there", systemImage: "figure.walk") }
                    .buttonStyle(SolidPillStyle(fill: Tokens.accentFill, text: Tokens.onAccent))
                .accessibilityHint("Spoken directions to your \(title).")
            }
        }
        .card()
    }
}

/// A thing in the list: what it is, where it is, and a Go arrow.
private struct ThingRow: View {
    let object: RememberedObject

    var body: some View {
        HStack(spacing: 12) {
            IconTile("shippingbox")
            VStack(alignment: .leading, spacing: 3) {
                Text(object.title.capitalizedFirst).font(.headline).foregroundStyle(Tokens.ink)
                Text(object.place.capitalizedFirst).font(.subheadline).foregroundStyle(Tokens.muted)
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

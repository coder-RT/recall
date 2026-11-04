import ARKit
import RecallCapture
import RecallDesign
import RecallDomain
import SceneKit
import SwiftUI

/// "See it in AR": the camera with a label over everything Recall found in the room, and the same things as a list
/// underneath, for VoiceOver and for anyone who can't hold the phone up. Double tap a label (on the camera or in the
/// list) or tap Speak for directions: the walk runs here, with the camera open, and its panel takes the list's place.
struct ARLabelsView: View {
    @State var model: ARLabelsModel
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                if ARLocator.isSupported {
                    LabelsCamera(session: model.locator.session, scene: model.locator.scene) { point, view in
                        model.doubleTapped(at: point, in: view)
                    }
                        .ignoresSafeArea(edges: .top)
                        .accessibilityHidden(true)
                    LiveLook(session: model.locator.session, look: model.look)
                } else {
                    Color.black.ignoresSafeArea(edges: .top)
                }
                VStack(spacing: 10) {
                    HStack {
                        Text(status).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(.black.opacity(0.6), in: Capsule())
                            .accessibilityIdentifier("ar-status")
                        Spacer()
                        Button("Done", action: close).buttonStyle(.glass).accessibilityIdentifier("ar-done")
                    }
                    if ARLocator.isSupported {
                        LookChips(look: $model.look, choices: [.camera, .edges])
                    }
                }
                .padding(16)
            }
            .frame(maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                if model.canGo {
                    BigButton(speakTitle, systemImage: model.hearing == .listening ? "stop.fill" : "mic.fill",
                              hint: "Say what you're looking for and Recall walks you there.", style: .secondary) {
                        Task { await model.toggleListening() }
                    }
                    .disabled(model.hearing == .thinking)
                    .accessibilityIdentifier("ar-speak")
                    .padding(16)
                }
            }
            if let guide = model.guide {
                GuidePanel(model: guide) { model.walkEnded() }
                    .padding(16)
                    .accessibilityIdentifier("ar-guide")
            } else {
                labelList
            }
        }
        .background(Tokens.canvas)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .accessibilityAction(.magicTap) {
            if let guide = model.guide { guide.repeatLast() } else { model.goToLabelInView() }
        }
    }

    private var labelList: some View {
        List {
            Section {
                ForEach(model.labels) { label in
                    HStack(spacing: 12) {
                        Circle().fill(Color(ARLocator.colour(label.mark))).frame(width: 12, height: 12)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(label.title.prefix(1).uppercased() + label.title.dropFirst()).font(.headline)
                            Text("\(label.place) · \(label.detail)").font(.subheadline).foregroundStyle(Tokens.muted)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { model.go(to: label) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(label.spoken)
                    .accessibilityHint("Double tap for directions.")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { model.go(to: label) }
                    .accessibilityIdentifier("ar-label-\(label.id)")
                }
            } header: {
                Text("Found in \(model.room) · double tap for directions · green: Recall tells you · amber: check · red: seen once")
                    .font(.footnote).textCase(nil)
            }
        }
        .frame(maxHeight: 260)
    }

    private var speakTitle: String {
        switch model.hearing {
        case .idle: "Speak"
        case .listening: "Stop"
        case .thinking: "Thinking…"
        }
    }

    private var status: String {
        if let guide = model.guide { return "Walking to \(guide.thing.title)" }
        if model.hearing == .listening { return "Listening…" }
        return switch model.phase {
        case .loading: "Loading what Recall found…"
        case .locating: "Point at the room…"
        case .showing: "\(model.labels.count) things in \(model.room)"
        case .listOnly(let why), .failed(let why): why
        }
    }
}

/// The locator's camera feed with the labels drawn into its scene; a double tap reports where, on the view.
private struct LabelsCamera: UIViewRepresentable {
    let session: ARSession
    let scene: SCNScene
    let doubleTap: (CGPoint, SCNSceneRenderer) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(doubleTap: doubleTap) }

    func makeUIView(context: Context) -> ARSCNView {
        let v = ARSCNView(frame: .zero)
        v.session = session
        v.scene = scene
        v.automaticallyUpdatesLighting = false
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped))
        tap.numberOfTapsRequired = 2
        v.addGestureRecognizer(tap)
        return v
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) { context.coordinator.doubleTap = doubleTap }

    @MainActor final class Coordinator: NSObject {
        var doubleTap: (CGPoint, SCNSceneRenderer) -> Void
        init(doubleTap: @escaping (CGPoint, SCNSceneRenderer) -> Void) { self.doubleTap = doubleTap }

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? ARSCNView else { return }
            doubleTap(gesture.location(in: view), view)
        }
    }
}

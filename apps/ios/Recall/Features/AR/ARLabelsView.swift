import ARKit
import RecallCapture
import RecallDesign
import RecallDomain
import SceneKit
import SwiftUI

/// "See it in AR": the camera with a label over everything Recall found in the room, and the same things as a list
/// underneath, for VoiceOver and for anyone who can't hold the phone up.
struct ARLabelsView: View {
    @State var model: ARLabelsModel
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                if ARLocator.isSupported {
                    LabelsCamera(session: model.locator.session, scene: model.locator.scene)
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
            List {
                Section {
                    ForEach(model.labels) { label in
                        HStack(spacing: 12) {
                            Circle().fill(Color(ARLocator.colour(label.mark))).frame(width: 12, height: 12)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(label.title.prefix(1).uppercased() + label.title.dropFirst()).font(.headline)
                                Text("\(label.place) · \(label.detail)").font(.subheadline).foregroundStyle(Tokens.muted)
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(label.spoken)
                        .accessibilityIdentifier("ar-label-\(label.id)")
                    }
                } header: {
                    Text("Found in \(model.room) · green: Recall tells you · amber: check · red: seen once")
                        .font(.footnote).textCase(nil)
                }
            }
            .frame(maxHeight: 260)
        }
        .background(Tokens.canvas)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .accessibilityAction(.magicTap) { model.sayInView() }
    }

    private var status: String {
        switch model.phase {
        case .loading: "Loading what Recall found…"
        case .locating: "Point at the room…"
        case .showing: "\(model.labels.count) things in \(model.room)"
        case .listOnly(let why), .failed(let why): why
        }
    }
}

/// The locator's camera feed with the labels drawn into its scene.
private struct LabelsCamera: UIViewRepresentable {
    let session: ARSession
    let scene: SCNScene
    func makeUIView(context: Context) -> ARSCNView {
        let v = ARSCNView(frame: .zero)
        v.session = session
        v.scene = scene
        v.automaticallyUpdatesLighting = false
        return v
    }
    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}

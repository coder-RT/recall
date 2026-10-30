import ARKit
import RecallDesign
import RecallDomain
import SwiftUI

/// Spoken directions to an object. Everything is said aloud and the phone ticks when facing the right way; the
/// screen (an arrow and the words) is for a sighted helper.
struct GuideView: View {
    @Environment(AppModel.self) private var app
    @State private var model: GuideModel
    let close: () -> Void

    init(target: GuideTarget, close: @escaping () -> Void) {
        _model = State(initialValue: GuideModel(target: target))
        self.close = close
    }

    var body: some View {
        ZStack {
            GuideCamera(session: model.session).ignoresSafeArea().accessibilityHidden(true)
            VStack(spacing: 12) {
                if model.weakTracking, case .guiding = model.phase { CueBanner("Slow down, tracking is weak") }
                Spacer()
                GlassEffectContainer(spacing: 12) {
                    VStack(spacing: 14) {
                        panel
                        HStack(spacing: 12) {
                            BigButton("Repeat", systemImage: "speaker.wave.2.fill", hint: "Says the direction again.",
                                      style: .secondary) { model.repeatLast(app: app) }
                            BigButton(finished ? "Done" : "Stop", systemImage: finished ? "checkmark" : "stop.fill",
                                      hint: "Ends the directions.", style: finished ? .primary : .stop) {
                                model.stop(app: app)
                                close()
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .onAppear { model.start(app: app) }
        .onDisappear { model.stop(app: app) }
        .accessibilityAction(.magicTap) { model.repeatLast(app: app) }
    }

    private var finished: Bool {
        switch model.phase {
        case .arrived, .landmarks, .failed: true
        default: false
        }
    }

    /// What the panel shows: the arrow and the words for each phase.
    private var panel: some View {
        HStack(spacing: 16) {
            DirectionDial(clock: clock, state: dialState)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.target.title.capitalizedFirst).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Text(headline).font(.title3.weight(.bold)).foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Tokens.blueDeep.opacity(0.88), in: .rect(cornerRadius: 24))
        .glassRim(.rect(cornerRadius: 24))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(model.target.title). \(headline)")
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var clock: Int? {
        if case .guiding(let cue) = model.phase { return cue.clock }
        return nil
    }

    private var dialState: DirectionDial.State {
        switch model.phase {
        case .locating, .planning: .working
        case .guiding: .pointing
        case .arrived: .arrived
        case .landmarks, .failed: .info
        }
    }

    private var headline: String {
        switch model.phase {
        case .locating: "Finding where you are. Turn slowly."
        case .planning: "Planning the way…"
        case .guiding(let cue): Directions.say(cue)
        case .landmarks(let text), .arrived(let text), .failed(let text): text
        }
    }
}

/// A round dial with an arrow pointing to the hour on a clock face (12 = straight ahead), or a symbol.
private struct DirectionDial: View {
    enum State { case working, pointing, arrived, info }
    let clock: Int?
    let state: State
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().fill(.white.opacity(0.12))
            Circle().stroke(.white.opacity(0.4), lineWidth: 2)
            switch state {
            case .working: ProgressView().tint(.white).controlSize(.large)
            case .pointing:
                Image(systemName: "arrow.up").font(.system(size: 40, weight: .bold)).foregroundStyle(Tokens.amber)
                    .rotationEffect(.degrees(Double(clock ?? 12) * 30))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: clock)
            case .arrived: Image(systemName: "checkmark").font(.system(size: 40, weight: .bold)).foregroundStyle(.white)
            case .info: Image(systemName: "signpost.right.fill").font(.system(size: 34, weight: .bold)).foregroundStyle(.white)
            }
        }
        .frame(width: 84, height: 84)
        .accessibilityHidden(true)
    }
}

/// The camera feed of the guidance session, for a sighted helper.
private struct GuideCamera: UIViewRepresentable {
    let session: ARSession
    func makeUIView(context: Context) -> ARSCNView {
        let v = ARSCNView(frame: .zero)
        v.session = session
        v.automaticallyUpdatesLighting = false
        return v
    }
    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}

import ARKit
import SceneKit
import RecallDesign
import RecallDomain
import SwiftUI

/// Spoken directions to an object. Everything is said aloud and the phone ticks when facing the right way; the
/// screen (an arrow and the words) is for a sighted helper.
struct GuideView: View {
    @State private var model: GuideModel
    let close: () -> Void

    init(model: GuideModel, close: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.close = close
    }

    var body: some View {
        ZStack {
            GuideCamera(session: model.session, scene: model.scene).ignoresSafeArea().accessibilityHidden(true)
            VStack(spacing: 12) {
                if case .guiding(_, weakTracking: true) = model.phase { CueBanner("Slow down, tracking is weak") }
                Spacer()
                // the panel keeps its own solid fill (glass in the container was drawn over its words); only the
                // buttons are glass
                panel
                GlassEffectContainer(spacing: 12) {
                    HStack(spacing: 12) {
                        BigButton("Repeat", systemImage: "speaker.wave.2.fill", hint: "Says the direction again.",
                                  style: .secondary) { model.repeatLast() }
                        BigButton(finished ? "Done" : "Stop", systemImage: finished ? "checkmark" : "stop.fill",
                                  hint: "Ends the directions.", style: finished ? .primary : .stop) {
                            model.stop()
                            close()
                        }
                    }
                }
            }
            .padding(16)
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .accessibilityAction(.magicTap) { model.repeatLast() }
    }

    private var finished: Bool {
        switch model.phase {
        case .arrived, .landmarks, .failed: true
        default: false
        }
    }

    /// What the panel shows: the clock dial and the words for each phase (stacked when the text is large).
    private var panel: some View {
        let layout = dynamicType.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                                                     : AnyLayout(HStackLayout(spacing: 16))
        return layout {
            DirectionDial(clock: clock, metres: metres, state: dialState)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.thing.title.capitalizedFirst).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Text(headline).font(.title3.weight(.bold)).foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Tokens.blueDeep.opacity(0.92), in: .rect(cornerRadius: 24))
        .hudRim(RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(model.thing.title). \(headline)")
        .accessibilityAddTraits(.updatesFrequently)
    }

    @Environment(\.dynamicTypeSize) private var dynamicType

    private var clock: Int? {
        if case .guiding(let cue, _) = model.phase { return cue.clock }
        return nil
    }

    private var metres: Double? {
        if case .guiding(let cue, _) = model.phase { return cue.metres }
        return nil
    }

    private var dialState: DirectionDial.State {
        switch model.phase {
        case .locating, .planning, .checking: .working
        case .guiding: .pointing
        case .arrived: .arrived
        case .landmarks, .failed: .info
        }
    }

    private var headline: String {
        switch model.phase {
        case .locating: "Finding where you are. Turn slowly."
        case .checking: "Checking with the camera. Hold the phone towards it."
        case .planning: "Planning the way…"
        case .guiding(let cue, _): Directions.say(cue)
        case .landmarks(let text), .arrived(let text), .failed(let text): text
        }
    }
}

/// A clock face for a sighted helper: 12 ticks, 12 / 3 / 6 / 9, and a Facebook-blue hand pointing to the hour to walk
/// towards (12 = straight ahead), with the distance in the middle; or a symbol while working, on arrival or for
/// landmark directions.
private struct DirectionDial: View {
    enum State { case working, pointing, arrived, info }
    let clock: Int?
    let metres: Double?
    let state: State
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().fill(.white)
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2), r = size.width / 2
                for i in 0..<12 {
                    let a = Double(i) * .pi / 6
                    let long = i % 3 == 0
                    let inner = r - (long ? 12 : 8), outer = r - 4
                    var tick = Path()
                    tick.move(to: CGPoint(x: c.x + inner * sin(a), y: c.y - inner * cos(a)))
                    tick.addLine(to: CGPoint(x: c.x + outer * sin(a), y: c.y - outer * cos(a)))
                    ctx.stroke(tick, with: .color(Tokens.blueDeep.opacity(long ? 1 : 0.55)),
                               style: StrokeStyle(lineWidth: long ? 3 : 2, lineCap: .round))
                }
            }
            ForEach([12, 3, 6, 9], id: \.self) { h in
                Text("\(h)").font(.system(size: 13, weight: .bold)).foregroundStyle(Tokens.blueDeep)
                    .offset(x: 38 * sin(Double(h) * .pi / 6), y: -38 * cos(Double(h) * .pi / 6))
            }
            switch state {
            case .working: ProgressView().tint(Tokens.blueDeep).controlSize(.large)
            case .pointing:
                Hand()
                    .rotationEffect(.degrees(Double(clock ?? 12) * 30))
                    .animation(MotionTokens.animation(MotionTokens.turn, reduceMotion: reduceMotion), value: clock)
                if let metres {
                    Text(Self.short(metres)).font(.system(size: 13, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Tokens.blueDeep, in: .capsule)
                }
            case .arrived: Image(systemName: "checkmark").font(.system(size: 44, weight: .bold)).foregroundStyle(Tokens.goText)
            case .info: Image(systemName: "signpost.right.fill").font(.system(size: 36, weight: .bold)).foregroundStyle(Tokens.blue)
            }
        }
        .frame(width: 120, height: 120)
        .overlay { Circle().stroke(.white.opacity(0.6), lineWidth: 2) }
        .accessibilityHidden(true)
    }

    static func short(_ m: Double) -> String {
        m < 1 ? "\(Int((m * 100 / 10).rounded()) * 10) cm" : String(format: m < 10 ? "%.1f m" : "%.0f m", m)
    }

    /// The hand: a tapered fb-blue arrow from the middle towards 12, with a white edge so it reads over the ticks.
    private struct Hand: View {
        var body: some View {
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                var p = Path()
                p.move(to: CGPoint(x: c.x, y: c.y - 46))
                p.addLine(to: CGPoint(x: c.x + 12, y: c.y - 26))
                p.addLine(to: CGPoint(x: c.x + 5, y: c.y - 26))
                p.addLine(to: CGPoint(x: c.x + 5, y: c.y - 14))
                p.addLine(to: CGPoint(x: c.x - 5, y: c.y - 14))
                p.addLine(to: CGPoint(x: c.x - 5, y: c.y - 26))
                p.addLine(to: CGPoint(x: c.x - 12, y: c.y - 26))
                p.closeSubpath()
                ctx.stroke(p, with: .color(.white), style: StrokeStyle(lineWidth: 4, lineJoin: .round))
                ctx.fill(p, with: .color(Tokens.blue))
            }
            .frame(width: 120, height: 120)
        }
    }
}

/// The camera feed of the guidance session, for a sighted helper, with the blue arrow over the thing.
private struct GuideCamera: UIViewRepresentable {
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

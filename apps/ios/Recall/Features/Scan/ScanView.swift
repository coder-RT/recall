import ARKit
import RecallCapture
import RecallDesign
import SwiftUI

/// The capture screen. Built for use without looking: everything important is spoken; the screen is for a helper.
struct ScanView: View {
    @Environment(AppModel.self) private var app
    @State private var model: ScanModel
    let close: () -> Void

    init(room: String, close: @escaping () -> Void) {
        _model = State(initialValue: ScanModel(room: room))
        self.close = close
    }

    var body: some View {
        Group {
            switch model.phase {
            case .unsupported:
                Unsupported(close: close)
            case .running, .finishing:
                capture
            case .done(let record):
                ReportView(record: record, close: close)
            case .failed(let message):
                Failed(message: message, close: close)
            }
        }
        .onAppear { model.start(model: app) }
    }

    private var capture: some View {
        ZStack {
            CameraView(session: model.capture.session)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            VStack(spacing: 12) {
                if let cue = model.cue { CueBanner(cue) }
                Spacer()
                GlassEffectContainer(spacing: 12) {
                    VStack(spacing: 14) {
                        HStack(spacing: 16) {
                            CoverageDial(covered: model.update.sectors, count: model.update.directionsCovered)
                            VStack(spacing: 10) {
                                StatTile(time, "time")
                                StatTile("\(model.update.keyframes)", "frames")
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(model.spokenProgress)
                        .accessibilityAddTraits(.updatesFrequently)
                        if model.phase == .finishing {
                            ProgressView("Saving the scan…").foregroundStyle(Tokens.ink).card()
                        } else {
                            BigButton("Stop", systemImage: "stop.fill", hint: "Finish the scan and hear the report.", style: .stop) {
                                Task { await model.stop(model: app) }
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .accessibilityAction(.magicTap) { app.announcer.say(model.spokenProgress, interrupt: true) }
    }

    private var time: String {
        let s = Int(model.update.elapsed)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// ARKit's camera feed for a sighted helper. It shows our own session; nothing is added to the scene.
private struct CameraView: UIViewRepresentable {
    let session: ARSession
    func makeUIView(context: Context) -> ARSCNView {
        let v = ARSCNView(frame: .zero)
        v.session = session
        v.automaticallyUpdatesLighting = false
        return v
    }
    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}

private struct Unsupported: View {
    let close: () -> Void
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "sensor.tag.radiowaves.forward").font(.system(size: 56)).foregroundStyle(Tokens.blueDark)
                .accessibilityHidden(true)
            VStack(spacing: 12) {
                Text("Scanning needs an iPhone with LiDAR").font(.title2.weight(.bold)).multilineTextAlignment(.center)
                    .foregroundStyle(Tokens.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Recall measures the room with the LiDAR scanner on iPhone Pro models. This device doesn't have one.")
                    .multilineTextAlignment(.center).foregroundStyle(Tokens.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .card()
            BigButton("Back", systemImage: "chevron.left", hint: "Return to your scans.", style: .secondary, action: close)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tokens.grey.ignoresSafeArea())
    }
}

private struct Failed: View {
    let message: String
    let close: () -> Void
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 56)).foregroundStyle(Tokens.amber)
                .accessibilityHidden(true)
            VStack(spacing: 12) {
                Text("The scan didn't work").font(.title2.weight(.bold)).foregroundStyle(Tokens.ink)
                Text(message).multilineTextAlignment(.center).foregroundStyle(Tokens.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .card()
            BigButton("Back", systemImage: "chevron.left", hint: "Return to your scans.", style: .secondary, action: close)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tokens.grey.ignoresSafeArea())
    }
}

import ARKit
import RecallCapture
import RecallDesign
import RecallDomain
import SwiftUI

/// The capture screen. Built for use without looking: everything important is spoken; the screen is for a helper.
struct ScanView: View {
    @State private var model: ScanModel
    let close: () -> Void

    init(model: ScanModel, close: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.close = close
    }

    var body: some View {
        Group {
            switch model.phase {
            case .unsupported:
                Unsupported(close: close)
            case .running, .finishing:
                capture
            case .done(let scan, let metrics):
                ReportView(scan: scan, metrics: metrics, close: close)
            case .failed(let message):
                Failed(message: message, close: close)
            }
        }
        .onAppear { model.start() }
    }

    private var capture: some View {
        ZStack {
            CameraView(session: model.capture.session)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            VStack(spacing: 12) {
                StepCard(update: model.update, time: time)
                if let cue = model.cue { CueBanner(cue) }
                Spacer()
                // the panels keep their own solid fill; only the buttons are glass (see hudRim)
                HStack(spacing: 16) {
                    CoverageDial(covered: model.update.sectors, count: model.update.directionsCovered)
                    MiniMap(surfaces: model.update.surfaces)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(model.spokenProgress)
                .accessibilityAddTraits(.updatesFrequently)
                if model.phase == .finishing {
                    ProgressView("Saving the scan…").foregroundStyle(Tokens.ink).card()
                } else {
                    GlassEffectContainer(spacing: 12) {
                        if model.confirmingStop {
                            BigButton("Stop anyway", systemImage: "stop.fill",
                                      hint: "The room map isn't ready. Finish the scan without it.", style: .stop) {
                                Task { await model.stop() }
                            }
                        } else {
                            BigButton("Stop", systemImage: "stop.fill", hint: "Finish the scan and hear the report.", style: .stop) {
                                Task { await model.stop() }
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .accessibilityAction(.magicTap) { model.repeatProgress() }
    }

    private var time: String {
        let s = Int(model.update.elapsed)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// The current voice step, the room map's state and the time, for a helper (all of it is also spoken).
private struct StepCard: View {
    let update: CaptureUpdate
    let time: String

    private var number: Int { min(update.step.rawValue + 1, 5) }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(update.step == .finish ? "Last step" : "Step \(number) of 5")
                    .font(.footnote.weight(.semibold)).foregroundStyle(.white)
                Text(update.step.title).font(.title3.weight(.bold)).foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Label(update.mapStatus == .mapped ? "Map ready" : "Mapping",
                      systemImage: update.mapStatus == .mapped ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(update.mapStatus == .mapped ? Tokens.blueDeep : .white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(update.mapStatus == .mapped ? Tokens.amber : .white.opacity(0.18), in: .capsule)
                Text(time).font(.headline).monospacedDigit().foregroundStyle(.white)
            }
        }
        .padding(16)
        .background(Tokens.blueDeep.opacity(0.92), in: .rect(cornerRadius: 22))
        .hudRim(RoundedRectangle(cornerRadius: 22))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(number): \(update.step.title). \(update.mapStatus.spoken). \(time).")
    }
}

/// A top-down sketch of the scan: floor the LiDAR saw (white squares), where the person walked (amber line), and
/// which sides have had a wall in view (ticks round the edge).
private struct MiniMap: View {
    let surfaces: SurfaceCoverage

    var body: some View {
        Canvas { ctx, size in
            let cells = surfaces.floorCells.map { CGPoint(x: CGFloat($0.x) * 0.25, y: CGFloat($0.y) * 0.25) }
            let path = surfaces.path.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
            let all = cells + path
            let inner = size.width - 28
            if let minX = all.map(\.x).min(), let maxX = all.map(\.x).max(),
               let minY = all.map(\.y).min(), let maxY = all.map(\.y).max() {
                let span = max(maxX - minX + 0.25, maxY - minY + 0.25, 2)
                let k = inner / span
                let ox = (size.width - (maxX - minX + 0.25) * k) / 2, oy = (size.height - (maxY - minY + 0.25) * k) / 2
                func at(_ p: CGPoint) -> CGPoint { CGPoint(x: ox + (p.x - minX) * k, y: oy + (p.y - minY) * k) }
                for c in cells {
                    ctx.fill(Path(CGRect(origin: at(c), size: CGSize(width: 0.25 * k, height: 0.25 * k))),
                             with: .color(.white.opacity(0.55)))
                }
                if path.count > 1 {
                    var line = Path()
                    line.addLines(path.map { at(CGPoint(x: $0.x + 0.125, y: $0.y + 0.125)) })
                    ctx.stroke(line, with: .color(Tokens.amber), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }
            }
            // wall sides: 12 ticks, sector 0 (ARKit −z) at the top, clockwise
            let c = CGPoint(x: size.width / 2, y: size.height / 2), r = size.width / 2 - 5
            for i in 0..<12 {
                let a = (Double(i) * 30 + 15) * .pi / 180
                let p = CGPoint(x: c.x + r * sin(a), y: c.y - r * cos(a))
                let seen = surfaces.wallSectors.contains(i)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)),
                         with: .color(seen ? Tokens.amber : .white.opacity(0.35)))
            }
        }
        .frame(width: 112, height: 112)
        .padding(10)
        .background(Tokens.blueDeep.opacity(0.92), in: .rect(cornerRadius: 24))
        .hudRim(RoundedRectangle(cornerRadius: 24))
        .accessibilityHidden(true)
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
            Image(systemName: "sensor.tag.radiowaves.forward").font(.system(size: 56)).foregroundStyle(Tokens.accent)
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
        .background(Tokens.canvas.ignoresSafeArea())
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
        .background(Tokens.canvas.ignoresSafeArea())
    }
}

import ARKit
import RecallCapture
import RecallDesign
import RecallDomain
import SceneKit
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
            if model.showingPlan {
                ScanPlanView(room: model.room, rescan: model.isRescan, readAloud: model.readPlan, start: model.begin,
                             cancel: close)
            } else {
                phase
            }
        }
    }

    @ViewBuilder private var phase: some View {
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
    }

    private var capture: some View {
        ZStack {
            CameraView(session: model.capture.session, scene: model.paint.scene)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            LiveLook(session: model.capture.session, look: model.look)
            VStack(spacing: 12) {
                StepCard(update: model.update, time: time)
                HStack(spacing: 8) {
                    LookChips(look: $model.look)
                    Button { model.showGrid.toggle() } label: {
                        Label("Grid", systemImage: "square.grid.3x3").font(.footnote.weight(.semibold))
                            .padding(.horizontal, 12).frame(minHeight: 44)
                            .foregroundStyle(model.showGrid ? Color.black : Color.white)
                            .background(model.showGrid ? Color(red: 0.49, green: 0.98, blue: 1.0) : Color.black.opacity(0.55),
                                        in: Capsule())
                    }
                    .buttonStyle(.plainTap)
                    .accessibilityLabel("Zone grid")
                    .accessibilityValue(model.showGrid ? "On" : "Off")
                    .accessibilityHint("Neon lines for each metre of floor and each height: knee, waist, chest, head. Zones the scan has seen glow.")
                    .accessibilityIdentifier("grid-toggle")
                }
                if let cue = model.cue { CueBanner(cue) }
                Spacer()
                // the panels keep their own solid fill; only the buttons are glass (see hudRim)
                Readouts(update: model.update, points: model.paint.trail.total)
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

/// The current step for a helper and for anyone who wants to read along: which of the 5 it is, what to do, a meter
/// for how far along it is, how high to hold the phone (measured), the distance to the wall on the walls step, and
/// why the step matters. All of it is also spoken.
private struct StepCard: View {
    let update: CaptureUpdate
    let time: String
    @State private var showingWhy = false

    private var number: Int { min(max(update.step.rawValue + 1, 0), 5) }
    private let white = Color.white
    private let amber = Color(red: 0.95, green: 0.7, blue: 0.24)
    private let green = Color(red: 0.55, green: 0.85, blue: 0.45)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text(update.step == .finish ? "Last step" : update.step == .recognise ? "Scanning again" : "Step \(number) of 5")
                    .font(.footnote.weight(.semibold)).foregroundStyle(white)
                StepDots(current: update.step, done: Set(update.stepsDone.filter(\.completed).map(\.step)))
                Spacer(minLength: 4)
                Label(update.mapStatus == .mapped ? "Map ready" : "Mapping",
                      systemImage: update.mapStatus == .mapped ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(update.mapStatus == .mapped ? Tokens.blueDeep : white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(update.mapStatus == .mapped ? Tokens.amber : white.opacity(0.18), in: .capsule)
                Text(time).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(white)
            }
            Text(update.step.title).font(.title3.weight(.bold)).foregroundStyle(white)
                .fixedSize(horizontal: false, vertical: true)
            Text(update.step.instruction).font(.subheadline).foregroundStyle(white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
            if let p = update.stepProgress {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: p.fraction).tint(green)
                    Text(p.text).font(.footnote.weight(.semibold)).foregroundStyle(white)
                }
            }
            HStack(spacing: 8) {
                chip(heightText, colour: heightColour)
                if update.step == .alongWalls, let d = update.centreDistance { chip(wallText(d), colour: wallColour(d)) }
                Spacer(minLength: 0)
                Button(showingWhy ? "Hide why" : "Why?") { withAnimation(.snappy) { showingWhy.toggle() } }
                    .font(.footnote.weight(.bold)).foregroundStyle(white)
                    .padding(.horizontal, 10).frame(minHeight: 44)
                    .accessibilityHint("Shows why this step matters.")
            }
            if showingWhy {
                Text(update.step.why + " " + update.step.doneWhen).font(.footnote).foregroundStyle(white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Tokens.blueDeep.opacity(0.92), in: .rect(cornerRadius: 22))
        .hudRim(RoundedRectangle(cornerRadius: 22))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken)
        .accessibilityAction(named: "Why this step") { UIAccessibility.post(notification: .announcement, argument: update.step.why) }
        .accessibilityIdentifier("step-card")
    }

    private func chip(_ text: String, colour: Color) -> some View {
        Text(text).font(.caption.weight(.bold)).foregroundStyle(.black)
            .padding(.horizontal, 8).padding(.vertical, 4).background(colour, in: .capsule)
    }

    private var heightText: String {
        guard let h = update.phoneHeight else { return "Phone height: measuring…" }
        let c = HeightCoach.check(h, for: update.step)
        let mark = c == .good ? "✓" : c == .tooLow ? "raise" : "lower"
        return String(format: "Phone %.2f m %@", h, mark)
    }

    private var heightColour: Color {
        guard let h = update.phoneHeight else { return white.opacity(0.7) }
        return HeightCoach.check(h, for: update.step) == .good ? green : amber
    }

    private func wallText(_ d: Double) -> String {
        switch ScanGuide.wallDistance(d) {
        case .good: String(format: "%.1f m from the wall ✓", d)
        case .tooClose: String(format: "Too close: %.1f m", d)
        case .tooFar: String(format: "Too far: %.1f m", d)
        }
    }

    private func wallColour(_ d: Double) -> Color { ScanGuide.wallDistance(d) == .good ? green : amber }

    private var spoken: String {
        let head = update.step == .recognise ? "Scanning again: \(update.step.title)." : "Step \(number) of 5: \(update.step.title)."
        let progress = update.stepProgress.map { " \($0.text)." } ?? ""
        let height = update.phoneHeight.map { String(format: " Phone at %.1f metres, target %@.", $0, update.step.heightLabel) } ?? ""
        return "\(head) \(update.step.instruction)\(progress)\(height) \(update.mapStatus.spoken). \(time)."
    }
}

/// The 5 steps as dots: done (filled with a tick), the current one (ringed), the rest (faint).
private struct StepDots: View {
    let current: ScanGuide.Step
    let done: Set<Int>

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<5, id: \.self) { i in
                Circle()
                    .fill(done.contains(i) ? Color.white : i == current.rawValue ? Color.white.opacity(0.5) : Color.white.opacity(0.2))
                    .frame(width: 8, height: 8)
                    .overlay(Circle().stroke(Color.white, lineWidth: i == current.rawValue ? 1.5 : 0).padding(-2))
            }
        }
        .accessibilityHidden(true)
    }
}

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

/// ARKit's camera feed for a sighted helper, with the captured LiDAR points painted into the scene.
private struct CameraView: UIViewRepresentable {
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


/// The live numbers, scanner style: distance ahead, points captured, photos kept and blurry, walking speed (amber
/// when too fast for sharp photos). Read as one sentence by VoiceOver.
private struct Readouts: View {
    let update: CaptureUpdate
    let points: Int

    var body: some View {
        let fast = ScanSpeed.isTooFast(update.speed)
        HStack(spacing: 0) {
            cell("AHEAD", update.centreDistance.map { String(format: "%.1f m", $0) } ?? "–")
            cell("ZONES", "\(update.zones.zonesSeen)/\(update.zones.zonesTotal)")
            cell("PHOTOS", "\(update.keyframes)")
            cell("BLURRY", "\(update.droppedBlurry)")
            cell("SPEED", ScanSpeed.text(update.speed), warn: fast)
        }
        .padding(.vertical, 8)
        .background(Color(red: 0.05, green: 0.08, blue: 0.14).opacity(0.85), in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.25), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(fast))
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityIdentifier("scan-readouts")
    }

    private func cell(_ name: String, _ value: String, warn: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(.subheadline, design: .monospaced).weight(.bold))
                .foregroundStyle(warn ? Color(red: 0.95, green: 0.7, blue: 0.24) : .white)
                .minimumScaleFactor(0.7).lineLimit(1)
            Text(name).font(.system(.caption2, design: .monospaced)).foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
    }

    private func spoken(_ fast: Bool) -> String {
        let ahead = update.centreDistance.map { String(format: "%.1f metres ahead", $0) } ?? "nothing in range ahead"
        let weak = update.zones.weakestBand.map { ", least seen at \($0) height" } ?? ""
        return "\(ahead), zones seen \(update.zones.zonesSeen) of \(update.zones.zonesTotal)\(weak), \(update.keyframes) photos kept, \(update.droppedBlurry) blurry"
            + (fast ? ", walking too fast" : "")
    }
}

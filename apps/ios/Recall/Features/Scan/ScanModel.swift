import Foundation
import Observation
import RecallCapture
import RecallDomain
import UIKit

/// Drives one capture: starts ARKit, turns updates into speech, haptics and the banner, and finishes the episode.
@MainActor @Observable
final class ScanModel {
    enum Phase: Equatable { case unsupported, running, finishing, done(Scan, CaptureMetrics), failed(String) }

    let room: String
    let scanId = UUID().uuidString.lowercased()
    let capture = CaptureSession()
    private(set) var phase: Phase = .running
    private(set) var update = CaptureUpdate(elapsed: 0, directionsCovered: 0, keyframes: 0, droppedBlurry: 0,
                                            tracking: .notAvailable, lightLux: 0)
    private(set) var cue: String?
    /// The LiDAR points captured so far, painted on the camera.
    let paint = PointPaint()
    /// Camera · LiDAR · Edges.
    var look = CameraLook.camera
    /// The neon zone grid over the camera (on unless switched off).
    var showGrid = true { didSet { paint.showGrid(update.zones, floorY: update.floorY, visible: showGrid) } }
    /// "How to scan well" comes first, every time; Start begins the scan.
    private(set) var showingPlan = true
    var isRescan: Bool { rescan != nil }
    private var heightCoach = HeightCoach()
    /// Stop was pressed before the room map was ready; the next press stops anyway.
    private(set) var confirmingStop = false
    private var lastSpokenDirections = 0
    private var compassOn = false

    private let scans: ScansModel
    private let files: any EpisodeFiles
    private let compass: CoreLocationCompass
    private let speech: any SpeechOutput
    private let haptics: any HapticsOutput

    /// Scanning a room again: the earlier scan and its room map (recognised first, so both share one frame).
    let rescan: (scanId: String, roomMap: Data)?

    init(room: String, rescan: (scanId: String, roomMap: Data)? = nil, scans: ScansModel, files: any EpisodeFiles,
         compass: CoreLocationCompass, speech: any SpeechOutput, haptics: any HapticsOutput) {
        self.room = room; self.rescan = rescan; self.scans = scans; self.files = files; self.compass = compass; self.speech = speech
        self.haptics = haptics
        if !CaptureSession.isSupported { phase = .unsupported }
    }

    /// The plan was read: start scanning.
    func begin() {
        showingPlan = false
        start()
    }

    /// Every step's what, why and done-when, read aloud (the plan's "Read the steps aloud").
    func readPlan() {
        let steps = ScanGuide.Step.allCases.filter { $0 != .recognise || isRescan }
        speech.say(steps.map { "\($0.title). \($0.instruction) \($0.why) \($0.doneWhen) Phone at \($0.heightLabel)." }
            .joined(separator: " "), interrupt: true)
    }

    func start() {
        guard phase == .running else { return }
        do {
            let writer = try EpisodeWriter(scanId: scanId, directory: files.directory(scan: scanId))
            capture.onUpdate = { [weak self] u in Task { @MainActor in self?.apply(u) } }
            compass.start()
            compassOn = true
            capture.start(writer: writer, heading: compass.sampler, rescan: rescan)
            UIApplication.shared.isIdleTimerDisabled = true
            speech.say(rescan == nil ? "Scanning \(room). I'll tell you each step." : "Scanning \(room) again.",
                       interrupt: false)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func apply(_ u: CaptureUpdate) {
        let stepChanged = u.step != update.step
        update = u
        paint.add(u.newPoints)
        paint.showGrid(u.zones, floorY: u.floorY, visible: showGrid)
        // a problem first (it is about right now), then the next step
        switch u.signal {
        case .cue(_, let text):
            cue = text
            speech.say(text, interrupt: true)
            haptics.warning()
        case .clear:
            cue = nil
        case nil:
            break
        }
        if let line = u.guideLine {
            speech.say(line, interrupt: u.signal == nil)
            if stepChanged || u.mapReady { haptics.success() }
        }
        // too low or too high for this step, for a while: one gentle reminder (no other line is being said)
        if u.guideLine == nil, u.signal == nil,
           let line = heightCoach.update(t: u.elapsed, height: u.phoneHeight, step: u.step) {
            speech.say(line, interrupt: false)
        }
        // while turning round, a progress line every 3 new directions
        if u.step == .turnAround, u.directionsCovered >= lastSpokenDirections + 3 {
            lastSpokenDirections = u.directionsCovered
            speech.say("\(u.directionsCovered) of 12 directions.", interrupt: false)
        }
    }

    var spokenProgress: String {
        let s = Int(update.elapsed)
        return "\(s / 60) minutes \(s % 60) seconds. Step: \(update.step.title). \(update.directionsCovered) of 12 directions, "
            + "walls on \(update.wallsCovered) of 12 sides. \(update.mapStatus.spoken). \(update.keyframes) frames."
    }

    func repeatProgress() { speech.say(spokenProgress, interrupt: true) }

    func stop() async {
        guard phase == .running else { return }
        // the room map is what finds you again later: ask once before stopping without it
        if !update.mapReady, update.mapStatus != .mapped, !confirmingStop {
            confirmingStop = true
            speech.say("The room map isn't ready yet, so finding things later may not work. Keep moving slowly, "
                       + "or double tap Stop again to stop anyway.", interrupt: true)
            haptics.warning()
            return
        }
        phase = .finishing
        UIApplication.shared.isIdleTimerDisabled = false
        stopCompass()
        speech.say("Saving the scan.", interrupt: true)
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        do {
            let manifest = try await capture.finish(device: Self.hardwareModel, appVersion: version)
            let m = manifest.captureMetrics
            let scan = Scan(id: scanId, room: room, createdAt: manifest.createdAt, grade: m.grade,
                            directions: m.directionsCovered, frames: manifest.frameCount, alignedTo: manifest.alignedTo)
            scans.add(scan)
            phase = .done(scan, m)
            let grade = m.grade == .good ? "good" : m.grade == .usable ? "usable" : "a redo"
            let tip = ScanTips.make(m).first.map { " Next time: \($0)" } ?? ""
            speech.say("Scan saved. Quality: \(grade). \(ScanGrade.reason(for: m))\(tip)", interrupt: true)
        } catch {
            files.delete(scan: scanId)
            phase = .failed(error.localizedDescription)
            speech.say(error.localizedDescription, interrupt: false)
        }
    }

    func cancel() {
        capture.cancel()
        stopCompass()
        UIApplication.shared.isIdleTimerDisabled = false
        files.delete(scan: scanId)
    }

    private func stopCompass() {
        if compassOn { compass.stop() }
        compassOn = false
    }

    /// e.g. "iPhone17,1"
    static var hardwareModel: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }
}

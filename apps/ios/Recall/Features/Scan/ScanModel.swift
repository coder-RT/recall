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
                                            tracking: .notAvailable, coach: nil, lightLux: 0)
    private(set) var cue: String?
    private var lastSpokenDirections = 0
    private var lastLightWarning: Double = -60

    private let scans: ScansModel
    private let files: any EpisodeFiles
    private let speech: any SpeechOutput
    private let haptics: any HapticsOutput

    init(room: String, scans: ScansModel, files: any EpisodeFiles, speech: any SpeechOutput, haptics: any HapticsOutput) {
        self.room = room; self.scans = scans; self.files = files; self.speech = speech; self.haptics = haptics
        if !CaptureSession.isSupported { phase = .unsupported }
    }

    func start() {
        guard phase == .running else { return }
        do {
            let writer = try EpisodeWriter(scanId: scanId, directory: files.directory(scan: scanId))
            capture.onUpdate = { [weak self] u in Task { @MainActor in self?.apply(u) } }
            capture.start(writer: writer)
            UIApplication.shared.isIdleTimerDisabled = true
            speech.say("Scanning \(room). Walk slowly around the room and turn the phone to every side. Double tap Stop when you're done.",
                       interrupt: false)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func apply(_ u: CaptureUpdate) {
        update = u
        switch u.coach {
        case .slowDown(let cause):
            let text = SpeedCoach.say(cause)
            cue = text
            speech.say(text, interrupt: true)
            haptics.warning()
        case .clear:
            cue = nil
        case nil:
            break
        }
        // a gentle progress line every 3 new directions
        if u.directionsCovered >= lastSpokenDirections + 3 {
            lastSpokenDirections = u.directionsCovered
            speech.say("\(u.directionsCovered) of 12 directions.", interrupt: false)
        }
        if u.lightLux > 0, u.lightLux < 150, u.elapsed - lastLightWarning > 20 {
            lastLightWarning = u.elapsed
            speech.say("It's dark. Turn on a light.", interrupt: false)
        }
    }

    var spokenProgress: String {
        let s = Int(update.elapsed)
        return "\(s / 60) minutes \(s % 60) seconds. \(update.directionsCovered) of 12 directions. \(update.keyframes) frames."
    }

    func repeatProgress() { speech.say(spokenProgress, interrupt: true) }

    func stop() async {
        guard phase == .running else { return }
        phase = .finishing
        UIApplication.shared.isIdleTimerDisabled = false
        speech.say("Saving the scan.", interrupt: true)
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        do {
            let manifest = try await capture.finish(device: Self.hardwareModel, appVersion: version)
            let m = manifest.captureMetrics
            let scan = Scan(id: scanId, room: room, createdAt: manifest.createdAt, grade: m.grade,
                            directions: m.directionsCovered, frames: manifest.frameCount)
            scans.add(scan)
            phase = .done(scan, m)
            let grade = m.grade == .good ? "good" : m.grade == .usable ? "usable" : "a redo"
            speech.say("Scan saved. Quality: \(grade). \(ScanGrade.reason(for: m))", interrupt: true)
        } catch {
            files.delete(scan: scanId)
            phase = .failed(error.localizedDescription)
            speech.say(error.localizedDescription, interrupt: false)
        }
    }

    func cancel() {
        capture.cancel()
        UIApplication.shared.isIdleTimerDisabled = false
        files.delete(scan: scanId)
    }

    /// e.g. "iPhone17,1"
    static var hardwareModel: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }
}

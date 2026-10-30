import Foundation
import Observation
import RecallCapture
import RecallDomain
import RecallVoice
import UIKit

/// Drives one capture: starts ARKit, turns updates into speech, haptics and the banner, and finishes the episode.
@MainActor @Observable
final class ScanModel {
    enum Phase: Equatable { case unsupported, running, finishing, done(ScanRecord), failed(String) }

    let room: String
    let scanId = UUID().uuidString.lowercased()
    let capture = CaptureSession()
    var phase: Phase = .running
    var update = CaptureUpdate(elapsed: 0, directionsCovered: 0, keyframes: 0, droppedBlurry: 0, tracking: .notAvailable,
                               coach: nil, lightLux: 0)
    var cue: String?
    private var lastSpokenDirections = 0
    private var lastLightWarning: Double = -60

    init(room: String) {
        self.room = room
        if !CaptureSession.isSupported { phase = .unsupported }
    }

    func start(model: AppModel) {
        guard phase == .running else { return }
        do {
            let writer = try EpisodeWriter(scanId: scanId, directory: model.episodeDir(scanId))
            capture.onUpdate = { [weak self] u in Task { @MainActor in self?.apply(u, model.announcer) } }
            capture.start(writer: writer)
            UIApplication.shared.isIdleTimerDisabled = true
            model.announcer.say("Scanning \(room). Walk slowly around the room and turn the phone to every side. Double tap Stop when you're done.")
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func apply(_ u: CaptureUpdate, _ announcer: Announcer) {
        update = u
        switch u.coach {
        case .slowDown(let cause):
            let text = SpeedCoach.say(cause)
            cue = text
            announcer.say(text, interrupt: true)
            Haptics.warning()
        case .clear:
            cue = nil
        case nil:
            break
        }
        // a gentle progress line every 3 new directions
        if u.directionsCovered >= lastSpokenDirections + 3 {
            lastSpokenDirections = u.directionsCovered
            announcer.say("\(u.directionsCovered) of 12 directions.")
        }
        if u.lightLux > 0, u.lightLux < 150, u.elapsed - lastLightWarning > 20 {
            lastLightWarning = u.elapsed
            announcer.say("It's dark. Turn on a light.")
        }
    }

    var spokenProgress: String {
        let s = Int(update.elapsed)
        return "\(s / 60) minutes \(s % 60) seconds. \(update.directionsCovered) of 12 directions. \(update.keyframes) frames."
    }

    func stop(model: AppModel) async {
        guard phase == .running else { return }
        phase = .finishing
        UIApplication.shared.isIdleTimerDisabled = false
        model.announcer.say("Saving the scan.", interrupt: true)
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        do {
            let manifest = try await capture.finish(device: Self.hardwareModel, appVersion: version)
            let m = manifest.captureMetrics
            let record = ScanRecord(id: scanId, room: room, createdAt: manifest.createdAt, grade: m.grade,
                                    directions: m.directionsCovered, frames: manifest.frameCount)
            model.add(record)
            phase = .done(record)
        } catch {
            try? FileManager.default.removeItem(at: model.episodeDir(scanId))
            phase = .failed(error.localizedDescription)
            model.announcer.say(error.localizedDescription)
        }
    }

    func cancel(model: AppModel) {
        capture.cancel()
        UIApplication.shared.isIdleTimerDisabled = false
        try? FileManager.default.removeItem(at: model.episodeDir(scanId))
    }

    /// e.g. "iPhone17,1"
    static var hardwareModel: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }
}

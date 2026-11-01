import AVFoundation
import CoreLocation
import CoreMotion
import Foundation
import RecallDomain
import WatchConnectivity
import WatchKit

/// Taps on the wrist, one meaning each: turn left, turn right, facing the right way, a metre walked, arrived, stop.
@MainActor
enum WristTaps {
    static func turn(_ side: CompassWalk.Side) {
        WKInterfaceDevice.current().play(side == .left ? .navigationLeftTurn : .navigationRightTurn)
    }
    static func facing() { WKInterfaceDevice.current().play(.directionUp) }
    static func metre() { WKInterfaceDevice.current().play(.click) }
    static func nextLeg() { WKInterfaceDevice.current().play(.navigationGenericManeuver) }
    static func arrived() { WKInterfaceDevice.current().play(.success) }
    static func stop() { WKInterfaceDevice.current().play(.retry) }
    static func start() { WKInterfaceDevice.current().play(.start) }
}

/// Speech out through the Watch's speaker: an OS voice (AVSpeechSynthesizer), not a model.
@MainActor
final class WatchVoice: NSObject, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()
    private var finished: (() -> Void)?

    override init() {
        super.init()
        synth.delegate = self
    }

    func say(_ text: String, then: (() -> Void)? = nil) {
        synth.stopSpeaking(at: .immediate)
        finished = then
        let u = AVSpeechUtterance(string: text)
        u.rate = AVSpeechUtteranceDefaultSpeechRate
        synth.speak(u)
    }

    func stop() {
        finished = nil
        synth.stopSpeaking(at: .immediate)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            let next = finished
            finished = nil
            next?()
        }
    }
}

/// Records one question as 16 kHz mono WAV (what Muse Voice Transcribe takes), stopping after a second of quiet once
/// the person has spoken, or after `maxSeconds`.
@MainActor
final class WatchRecorder {
    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var heard = false
    private var quietSince: Date?
    private var done: ((URL?) -> Void)?
    private let url = FileManager.default.temporaryDirectory.appending(path: "question.wav")

    var isRecording: Bool { recorder?.isRecording == true }

    func start(maxSeconds: Double = 6, done: @escaping (URL?) -> Void) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default)
        try? session.setActive(true)
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000,
                                       AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
                                       AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
        guard let r = try? AVAudioRecorder(url: url, settings: settings) else { return done(nil) }
        r.isMeteringEnabled = true
        guard r.record(forDuration: maxSeconds) else { return done(nil) }
        recorder = r
        heard = false
        quietSince = nil
        self.done = done
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard let r = recorder else { return }
        guard r.isRecording else { return finish() }  // reached maxSeconds
        r.updateMeters()
        let level = r.averagePower(forChannel: 0)
        if level > -35 { heard = true; quietSince = nil } else if heard, level < -45 {
            quietSince = quietSince ?? .now
            if Date.now.timeIntervalSince(quietSince!) > 1.0 { finish() }
        }
    }

    private func finish() {
        timer?.invalidate()
        timer = nil
        recorder?.stop()
        recorder = nil
        let done = self.done
        self.done = nil
        done?(heard ? url : nil)
    }

    func cancel() {
        done = nil
        timer?.invalidate()
        timer = nil
        recorder?.stop()
        recorder = nil
    }
}

/// The compass (magnetic heading: the routes' bearings are magnetic) and the pedometer's metres since the walk began.
@MainActor
final class WalkSensors: NSObject, CLLocationManagerDelegate {
    private let location = CLLocationManager()
    private let pedometer = CMPedometer()
    private(set) var heading: Double?
    private(set) var metres: Double = 0
    var changed: () -> Void = {}

    var compassAvailable: Bool { CLLocationManager.headingAvailable() }

    func start() {
        metres = 0
        location.delegate = self
        location.headingFilter = 2
        location.requestWhenInUseAuthorization()
        location.startUpdatingHeading()
        if CMPedometer.isDistanceAvailable() || CMPedometer.isStepCountingAvailable() {
            pedometer.startUpdates(from: .now) { [weak self] data, _ in
                guard let data else { return }
                // distance when the pedometer has it, else steps at an average stride
                let m = data.distance?.doubleValue ?? data.numberOfSteps.doubleValue * 0.7
                Task { @MainActor in
                    self?.metres = m
                    self?.changed()
                }
            }
        }
    }

    func stop() {
        location.stopUpdatingHeading()
        pedometer.stopUpdates()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }  // negative: not calibrated yet
        let h = newHeading.magneticHeading
        Task { @MainActor in
            self.heading = h
            self.changed()
        }
    }
}

/// The iPhone, over WatchConnectivity: requests go out, replies come back (a spoken question goes as a file, and its
/// answer arrives later as a message with the same id).
final class PhoneLink: NSObject, WCSessionDelegate, @unchecked Sendable {
    typealias Reply = @MainActor (WatchReply) -> Void
    private let waiting = PendingReplies<Reply>()

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    @MainActor
    func send(_ request: WatchRequest, reply: @escaping @MainActor (WatchReply) -> Void) {
        guard WCSession.default.activationState == .activated,
              let data = try? JSONEncoder().encode(request) else {
            return reply(WatchReply(say: "I can't reach your iPhone. Keep it nearby, with Recall installed."))
        }
        let id = wait(for: reply)
        WCSession.default.sendMessage(["request": data], replyHandler: { [self] message in
            let r = (message["reply"] as? Data).flatMap { try? JSONDecoder().decode(WatchReply.self, from: $0) }
            answer(id, r ?? WatchReply(say: "The iPhone's answer was unreadable."))
        }, errorHandler: { [self] _ in
            answer(id, WatchReply(say: "I can't reach your iPhone. Keep it nearby, with Recall open once."))
        })
    }

    @MainActor
    func ask(audio: URL, reply: @escaping @MainActor (WatchReply) -> Void) {
        guard WCSession.default.activationState == .activated else {
            return reply(WatchReply(say: "I can't reach your iPhone. Keep it nearby, with Recall installed."))
        }
        let id = wait(for: reply)
        WCSession.default.transferFile(audio, metadata: ["id": id])
    }

    /// Registers `reply` under a new id and answers it with `phoneDidNotAnswer` if the iPhone stays silent, so the
    /// Watch never stays on "thinking".
    @MainActor
    private func wait(for reply: @escaping @MainActor (WatchReply) -> Void) -> String {
        let id = UUID().uuidString
        waiting.put(id, reply)
        Task { [self] in
            try? await Task.sleep(for: PendingReplies<Reply>.timeout)
            answer(id, .phoneDidNotAnswer)
        }
        return id
    }

    /// Answers `id` once; a reply after the timeout (or a timeout after the reply) finds nothing and is dropped.
    private func answer(_ id: String, _ reply: WatchReply) {
        guard let handler = waiting.take(id) else { return }
        Task { @MainActor in handler(reply) }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let id = message["id"] as? String, let data = message["reply"] as? Data,
              let reply = try? JSONDecoder().decode(WatchReply.self, from: data) else { return }
        answer(id, reply)
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
}

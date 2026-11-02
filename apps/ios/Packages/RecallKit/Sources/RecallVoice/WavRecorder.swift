import AVFoundation
import RecallDomain

/// Records a spoken question as mono 16-bit PCM WAV at 16 kHz, the format Muse Voice Transcribe takes on the Mac.
/// Speech to text is never done on the phone (no Apple speech recognition; CLAUDE.md rule 8).
@MainActor
public final class WavRecorder: NSObject, VoiceInput {
    private var recorder: AVAudioRecorder?
    private var finished: (@MainActor (Data?) -> Void)?
    private let file = URL.temporaryDirectory.appending(path: "question.wav")

    public override init() { super.init() }

    public var isRecording: Bool { recorder?.isRecording == true }

    public func start(maxSeconds: Double, finished: @escaping @MainActor (Data?) -> Void) async -> Bool {
        guard await AVAudioApplication.requestRecordPermission() else { return false }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .duckOthers])
        try? session.setActive(true)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
        ]
        guard let r = try? AVAudioRecorder(url: file, settings: settings) else { return false }
        r.delegate = self
        recorder = r
        self.finished = finished
        return r.record(forDuration: maxSeconds)
    }

    /// Stops early; the delegate then hands over the recording (the same path as running out of time).
    public func stop() { recorder?.stop() }

    private func done(_ ok: Bool) {
        recorder = nil
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        let handler = finished
        finished = nil
        let audio = ok ? try? Data(contentsOf: file) : nil
        try? FileManager.default.removeItem(at: file)  // the question is in memory now; no copy is left on the phone
        handler?(audio)
    }
}

extension WavRecorder: AVAudioRecorderDelegate {
    // ends both ways: stop() and the time limit
    public nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in self.done(flag) }
    }
}

import AVFoundation

/// Records a spoken question as mono 16-bit PCM WAV at 16 kHz, the format Muse Voice Transcribe takes on the Mac.
/// Speech to text is never done on the phone (no Apple speech recognition; CLAUDE.md rule 8).
@MainActor
final class VoiceRecorder {
    private var recorder: AVAudioRecorder?
    private let file = URL.temporaryDirectory.appending(path: "question.wav")

    var isRecording: Bool { recorder?.isRecording == true }

    /// Starts recording; false when the microphone isn't allowed.
    func start() async -> Bool {
        guard await AVAudioApplication.requestRecordPermission() else { return false }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .duckOthers])
        try? session.setActive(true)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
        ]
        recorder = try? AVAudioRecorder(url: file, settings: settings)
        return recorder?.record(forDuration: 15) == true  // a question is short; stop on its own after 15 s
    }

    /// Stops and returns the WAV; speech output goes back to the spoken-audio setup the Announcer uses.
    func stop() -> Data? {
        recorder?.stop()
        recorder = nil
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        return try? Data(contentsOf: file)
    }
}

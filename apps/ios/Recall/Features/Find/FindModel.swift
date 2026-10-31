import Foundation
import Observation
import RecallApplication
import RecallDomain

/// Find: a question typed or spoken, the Guide's answer, and the thing it is about.
@MainActor @Observable
final class FindModel {
    enum State: Equatable {
        case idle, listening, transcribing, thinking
        case answered(AskWhereIs.Result)
        case failed(String)
    }

    var question = ""
    private(set) var state = State.idle

    private let ask: AskWhereIs
    private let transcriber: any Transcriber
    private let voice: any VoiceInput
    private let things: ThingsModel
    private let settings: SettingsModel
    private let speech: any SpeechOutput
    private let haptics: any HapticsOutput
    /// Starts recognising the room while the answer is read out, so "Take me there" begins at once.
    private let prepareGuide: @MainActor () -> Void

    init(ask: AskWhereIs, transcriber: any Transcriber, voice: any VoiceInput, things: ThingsModel, settings: SettingsModel,
         speech: any SpeechOutput, haptics: any HapticsOutput, prepareGuide: @escaping @MainActor () -> Void = {}) {
        self.ask = ask; self.transcriber = transcriber; self.voice = voice; self.things = things
        self.settings = settings; self.speech = speech; self.haptics = haptics; self.prepareGuide = prepareGuide
    }

    var busy: Bool { state == .thinking || state == .transcribing }

    /// Tap to talk, tap to stop; the recording also ends by itself after 15 s (then the question is asked as well).
    func toggleListening() async {
        if voice.isRecording {
            voice.stop()
            return
        }
        haptics.tap()
        let started = await voice.start(maxSeconds: 15) { [weak self] wav in
            Task { await self?.heard(wav) }
        }
        state = started ? .listening : .failed(UserMessage.explain(RecallError.noMicrophone))
    }

    private func heard(_ wav: Data?) async {
        guard let wav, !wav.isEmpty else {
            state = .idle
            return
        }
        state = .transcribing
        do {
            question = try await transcriber.transcribe(wav: wav)
            await submit()
        } catch {
            state = .failed(UserMessage.explain(error))
        }
    }

    func submit() async {
        state = .thinking
        do {
            // say something at once (system voice); the answer interrupts it when it arrives
            speech.say(Acknowledgement.line(for: question, known: things.things), interrupt: true)
            if !things.loaded { await things.refresh() }
            let result = try await ask(question, home: settings.connection.homeId, known: things.things)
            state = .answered(result)
            if result.thing != nil { prepareGuide() }
            speech.say(result.answer.text + (result.thing == nil ? "" : " Tap Take me there for directions."), interrupt: true)
        } catch {
            state = .failed(UserMessage.explain(error))
            speech.say(UserMessage.explain(error), interrupt: true)
        }
    }
}

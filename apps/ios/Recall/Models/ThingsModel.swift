import Foundation
import Observation
import RecallApplication
import RecallDomain

/// One list of remembered things for Find and Found, so a correction in one shows in the other at once.
@MainActor @Observable
final class ThingsModel {
    private(set) var things: [Thing] = []
    private(set) var error: String?
    private(set) var loading = false
    private(set) var loaded = false

    private let load: LoadThings
    private let correct: CorrectThing
    private let forget: ForgetThing
    private let settings: SettingsModel
    private let speech: any SpeechOutput

    init(load: LoadThings, correct: CorrectThing, forget: ForgetThing, settings: SettingsModel, speech: any SpeechOutput) {
        self.load = load; self.correct = correct; self.forget = forget; self.settings = settings; self.speech = speech
    }

    var unsureCount: Int { things.filter(\.needsReview).count }

    func refresh() async {
        loading = true
        defer { loading = false; loaded = true }
        do {
            things = try await load(home: settings.connection.homeId)
            error = nil
        } catch {
            self.error = UserMessage.explain(error)
        }
    }

    /// Saves and confirms; throws the reason (shown in the edit sheet) when the Mac refuses.
    func save(_ thing: Thing, _ correction: Correction) async throws {
        do {
            try await correct(thing, home: settings.connection.homeId, correction)
        } catch {
            throw RecallError.server(UserMessage.explain(error))
        }
        speech.say("Saved.", interrupt: false)
        await refresh()
    }

    func remove(_ thing: Thing) async throws {
        do {
            try await forget(thing, home: settings.connection.homeId)
        } catch {
            throw RecallError.server(UserMessage.explain(error))
        }
        speech.say("Forgotten.", interrupt: false)
        await refresh()
    }
}

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
    private let loads = SingleFlight<[Thing]>()
    private var fixed = false

    init(load: LoadThings, correct: CorrectThing, forget: ForgetThing, settings: SettingsModel, speech: any SpeechOutput) {
        self.load = load; self.correct = correct; self.forget = forget; self.settings = settings; self.speech = speech
    }

    /// UI tests only (launch argument `-UITestSampleThings`): a fixed list, never fetched. Real users never see it.
    func useForUITests(_ sample: [Thing]) {
        things = sample.sorted(by: Thing.listOrder); loaded = true; fixed = true
    }

    var unsureCount: Int { things.filter(\.needsReview).count }

    /// Find and Found both ask on appearing; they share one request, and leaving a screen doesn't cancel it.
    func refresh() async {
        guard !fixed else { return }
        loading = true
        defer { loading = false }
        do {
            let (load, home) = (load, settings.connection.homeId)
            things = try await loads.run { try await load(home: home) }
            error = nil
            loaded = true
        } catch let e where UserMessage.isCancellation(e) {
            // the screen went away mid-request: keep what is shown, and try again next time
        } catch {
            self.error = UserMessage.explain(error)
            loaded = true
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

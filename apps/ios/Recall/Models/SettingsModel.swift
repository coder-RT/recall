import Foundation
import Observation
import RecallApplication
import RecallDomain

/// The connection settings being edited, kept saved and handed to the live server on every change.
@MainActor @Observable
final class SettingsModel {
    var connection: Connection {
        didSet {
            store.save(connection)
            server.use(connection)
        }
    }

    private let store: any ConnectionStore
    private let server: LiveServer
    private let pair: PairDevice
    private let test: TestConnection
    private let speech: any SpeechOutput

    init(store: any ConnectionStore, server: LiveServer, pair: PairDevice, test: TestConnection, speech: any SpeechOutput) {
        self.store = store; self.server = server; self.pair = pair; self.test = test; self.speech = speech
        connection = store.load()
        server.use(connection)
    }

    var issue: SetupIssue? { connection.issue }

    /// recall://pair?… from the Mac's QR code.
    func pair(with link: URL) {
        do {
            guard let paired = try pair(link) else { return }
            connection = paired
            speech.say(paired.issue?.message ?? "Paired with the Mac. Open Settings and test the connection.", interrupt: false)
        } catch {
            speech.say(UserMessage.explain(error), interrupt: false)
        }
    }

    /// The result stays on screen (to read or copy); only success is spoken.
    func testConnection() async -> (message: String, ok: Bool) {
        if let issue { return (issue.message, false) }
        do {
            let message = try await test()
            speech.say("Connected.", interrupt: false)
            return (message, true)
        } catch {
            return (UserMessage.explain(error), false)
        }
    }

    func say(_ text: String) { speech.say(text, interrupt: false) }
}

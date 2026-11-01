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

    /// A pairing link waiting for the person to confirm it (shown as an alert).
    var pendingPairing: PairingLink?

    /// recall://pair?… from the Mac's QR code. Nothing changes until the person confirms: any app or page can open
    /// such a link, and a silent one would hand the device key to someone else's server.
    func pair(with link: URL) {
        do {
            guard let pairing = try pair.read(link) else { return }
            pendingPairing = pairing
            speech.say(pairing.summary, interrupt: false)
        } catch {
            speech.say(UserMessage.explain(error), interrupt: false)
        }
    }

    func confirmPairing() {
        guard let pairing = pendingPairing else { return }
        pendingPairing = nil
        connection = pair.apply(pairing)
        speech.say(connection.issue?.message ?? "Paired with the Mac. Open Settings and test the connection.", interrupt: false)
    }

    func cancelPairing() {
        guard pendingPairing != nil else { return }
        pendingPairing = nil
        speech.say("Not paired. Your Mac's address and key are unchanged.", interrupt: false)
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

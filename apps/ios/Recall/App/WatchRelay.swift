import Foundation
import RecallApplication
import RecallDomain
import WatchConnectivity

/// The Watch's way to the Mac: requests arrive over WatchConnectivity (a spoken question as a file, everything else as
/// a message), AnswerWatch answers them with the phone's own connection, and the reply goes back to the Watch. The
/// phone app wakes in the background for this, so the phone can stay in a pocket.
final class WatchRelay: NSObject, WCSessionDelegate, @unchecked Sendable {
    private let answer: AnswerWatch
    private let home: @Sendable () async -> String

    init(answer: AnswerWatch, home: @escaping @Sendable () async -> String) {
        self.answer = answer; self.home = home
    }

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // a request with a reply handler: the things for the dial, or a route to a picked thing
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        let reply = Reply(replyHandler)
        guard let data = message["request"] as? Data, let request = try? JSONDecoder().decode(WatchRequest.self, from: data) else {
            return reply(WatchReply(say: "The phone didn't understand the Watch. Update both apps."))
        }
        Task { reply(await answer(request, home: await home())) }
    }

    // a spoken question: the recording arrives as a file; the answer goes back as a message carrying the same id
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let id = file.metadata?["id"] as? String ?? ""
        // a question is a few seconds of 16 kHz audio; anything far bigger isn't one, and isn't read into memory
        let size = (try? file.fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let audio = size <= WatchReply.maxAudioBytes ? try? Data(contentsOf: file.fileURL) : nil
        Task {
            let reply = await answer(.ask(audioFile: id), home: await home(), audio: audio)
            guard let data = try? JSONEncoder().encode(reply) else { return }
            WCSession.default.sendMessage(["reply": data, "id": id], replyHandler: nil)
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }  // a new Watch was paired
}

/// WatchConnectivity's reply handler, carried into the task that answers (it is called once, from any thread).
private struct Reply: @unchecked Sendable {
    let send: ([String: Any]) -> Void
    init(_ send: @escaping ([String: Any]) -> Void) { self.send = send }
    func callAsFunction(_ reply: WatchReply) {
        send(["reply": (try? JSONEncoder().encode(reply)) ?? Data()])
    }
}

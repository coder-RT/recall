import Foundation
import RecallDomain

/// Understands a spoken reply after a find: the Meta model on the Mac first, the phone's own word rules if it can't be
/// reached, can't tell or takes too long, so "go back, or done?" works with the Mac asleep and nobody is left waiting.
public struct ReadFoundReply: Sendable {
    private let reader: (any ReplyReading)?
    private let patience: Double

    public init(reader: (any ReplyReading)?, patience: Double = 6) {
        self.reader = reader
        self.patience = patience
    }

    public func callAsFunction(_ said: String, about thing: String) async -> FoundReply {
        guard let reader else { return FoundReply.read(said) }
        let understood = await withTaskGroup(of: FoundReply?.self) { group in
            group.addTask { try? await reader.read(reply: said, about: thing) }
            group.addTask { [patience] in
                try? await Task.sleep(for: .seconds(patience))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        return understood ?? FoundReply.read(said)
    }
}

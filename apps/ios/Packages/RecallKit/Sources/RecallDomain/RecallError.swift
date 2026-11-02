import Foundation

/// Errors the app explains to the user. Adapters throw these (or system errors), and `UserMessage` turns any of
/// them into one plain sentence that stays on screen to read or copy.
public enum RecallError: Error, Equatable, Sendable {
    case setup(SetupIssue)
    case server(String)
    case status(Int)
    case incompletePairing
    case incompleteScan
    case noMicrophone
}

extension RecallError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .setup(let issue): issue.message
        case .server(let s): s
        case .status(401): "The device key is wrong. Check it in Settings."
        case .status(413): "That was too large for the Mac to accept."
        case .status(429): "The Mac is getting a lot of requests. Wait a moment and try again."
        case .status(404): "The Mac doesn't know that yet."
        case .status(503): "The Mac is missing a setting. Check RECALL_DEVICE_KEY in its .env."
        case .status(let c): "The Mac answered with an error (\(c))."
        case .incompletePairing: "That pairing code is incomplete. Run make pair on the Mac again."
        case .incompleteScan: "This scan's files are incomplete. Scan the room again."
        case .noMicrophone: "Recall can't use the microphone. Allow it in Settings, Privacy, Microphone, or type the question."
        }
    }
}

public enum UserMessage {
    /// A request that was cancelled, not one that failed (iOS says "cancelled (Error -999)"): never shown.
    public static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    /// A plain sentence for any error: Recall's own, or the network failures, with what to check.
    /// `unwrap` lets an adapter open its own wrapper errors first (the generated client wraps the network error).
    public static func explain(_ error: Error, unwrap: (Error) -> Error = { $0 }) -> String {
        let inner = unwrap(error)
        if let e = inner as? RecallError { return e.localizedDescription }
        guard let url = inner as? URLError else { return inner.localizedDescription }
        switch url.code {
        case .notConnectedToInternet:
            return "The iPhone isn't allowed on the local network, or isn't on Wi-Fi. Turn on Settings, Privacy & Security, "
                + "Local Network, Recall, and check the iPhone is on the same network as the Mac. (Error -1009)"
        case .cannotConnectToHost:
            return "The Mac refused the connection. Check the Recall API is running. (Error -1004)"
        case .timedOut:
            return "The Mac didn't answer. Check the address and the network. (Error -1001)"
        case .cannotFindHost, .dnsLookupFailed:
            return "The address can't be found. Check the Mac address in Settings, and that Tailscale is on if you use it. "
                + "(Error \(url.code.rawValue))"
        case .appTransportSecurityRequiresSecureConnection:
            return "iOS blocked plain http to this address. Use the Mac's local IP address or an https tunnel. (Error -1022)"
        default:
            return "\(url.localizedDescription) (Error \(url.code.rawValue))"
        }
    }
}

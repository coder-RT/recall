import Foundation

/// How the phone reaches its Mac: the address as typed, the shared device key (pairing, not a login) and the home.
/// Value object: it cleans what was typed or pasted and says, in words, what's still missing.
public struct Connection: Sendable, Equatable {
    public var address: String
    public var key: String
    public var home: String

    public init(address: String, key: String, home: String) {
        self.address = address; self.key = key; self.home = home
    }

    /// The address as a URL, tolerant of spaces, newlines and a missing "http://".
    public var url: URL? {
        let text = address.filter { !$0.isNewline }.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        let full = text.contains("://") ? text : "http://\(text)"
        guard let url = URL(string: full), url.scheme?.hasPrefix("http") == true, url.host != nil else { return nil }
        return url
    }

    /// The key without the spaces or newline a paste brings along.
    public var cleanKey: String { key.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// "32 characters, ending in 6 G S O." — to compare with the Mac's without showing the key.
    public var keySummary: String {
        let k = cleanKey
        guard !k.isEmpty else { return "No key yet." }
        return "\(k.count) characters, ending in \(k.suffix(4).map(String.init).joined(separator: " "))."
    }

    public var homeId: String {
        let h = home.trimmingCharacters(in: .whitespacesAndNewlines)
        return h.isEmpty ? "flat" : h
    }

    /// What is missing before the phone can talk to the Mac, or nil.
    public var issue: SetupIssue? {
        switch (url, cleanKey.isEmpty) {
        case (nil, true): .nothingSet
        case (nil, false): .badAddress
        case (_, true): .noKey
        default: nil
        }
    }
}

public enum SetupIssue: Sendable, Equatable {
    case nothingSet, badAddress, noKey

    public var message: String {
        switch self {
        case .nothingSet: "Add your Mac's address and device key in Settings."
        case .badAddress: "The Mac address in Settings isn't valid. It looks like 192.168.0.25:8000."
        case .noKey: "Add the device key in Settings."
        }
    }
}

/// The Mac's pairing link (make pair shows it as a QR code): recall://pair?url=…&key=…&home=…
public struct PairingLink: Sendable, Equatable {
    public let address: String
    public let key: String
    public let home: String?

    /// Nil when the link isn't a pairing link; throws when it is one but is missing the address or key.
    public init?(_ link: URL) throws {
        guard link.scheme == "recall", link.host == "pair" else { return nil }
        let items = URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let value = { (name: String) in
            items.first { $0.name == name }?.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        guard !value("url").isEmpty, !value("key").isEmpty else { throw RecallError.incompletePairing }
        address = value("url")
        key = value("key")
        home = value("home").isEmpty ? nil : value("home")
    }
}

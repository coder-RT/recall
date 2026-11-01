import Foundation
import RecallDomain

/// Applies the Mac's pairing link (recall://pair?url=…&key=…&home=…) to the connection settings.
public struct PairDevice: Sendable {
    private let store: any ConnectionStore
    public init(store: any ConnectionStore) { self.store = store }

    /// The new connection, nil when the link isn't a pairing link; throws when it's an incomplete one.
    public func callAsFunction(_ link: URL) throws -> Connection? {
        guard let pairing = try read(link) else { return nil }
        return apply(pairing)
    }

    /// The link's pairing, not yet applied: any app or web page can open a recall:// link, so the person confirms
    /// which Mac first (the old address and key stay until they do).
    public func read(_ link: URL) throws -> PairingLink? { try PairingLink(link) }

    /// Uses the pairing the person confirmed.
    @discardableResult
    public func apply(_ pairing: PairingLink) -> Connection {
        var c = store.load()
        c.address = pairing.address
        c.key = pairing.key
        if let home = pairing.home { c.home = home }
        store.save(c)
        return c
    }
}

/// Settings → Test connection: the Mac answers and accepts the key.
public struct TestConnection: Sendable {
    private let check: any ConnectionCheck
    public init(check: any ConnectionCheck) { self.check = check }

    public func callAsFunction() async throws -> String {
        "Connected. The Mac's Guide runs on \(try await check.check())."
    }
}

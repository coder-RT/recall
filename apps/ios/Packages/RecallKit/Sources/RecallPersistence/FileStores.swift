import Foundation
import RecallDomain

/// The scan list as scans.json in Application Support (the shape older builds wrote, so nothing is lost).
public struct FileScanLibrary: ScanLibrary {
    let file: URL

    public init(file: URL = URL.applicationSupportDirectory.appending(path: "scans.json")) { self.file = file }

    public func load() -> [Scan] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        return (try? Self.decoder.decode([Scan].self, from: data)) ?? []
    }

    public func save(_ scans: [Scan]) {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Self.encoder.encode(scans).write(to: file, options: .atomic)
    }

    static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()
    static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }()
}

/// Episode folders: Application Support/Episodes/scan-<id>/ (manifest.json, worldmap.arworldmap, frames…).
public struct FileEpisodeFiles: EpisodeFiles {
    let root: URL

    public init(root: URL = URL.applicationSupportDirectory.appending(path: "Episodes")) { self.root = root }

    public func directory(scan: String) -> URL {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appending(path: "scan-\(scan)")
    }

    public func manifest(scan: String) -> Manifest? {
        guard let data = try? Data(contentsOf: directory(scan: scan).appending(path: "manifest.json")) else { return nil }
        return try? FileScanLibrary.decoder.decode(Manifest.self, from: data)
    }

    public func roomMap(scan: String) -> Data? {
        try? Data(contentsOf: directory(scan: scan).appending(path: "worldmap.arworldmap"))
    }

    /// The folder, its zip and the upload's part files.
    public func delete(scan: String) {
        let dir = directory(scan: scan)
        for url in [dir, dir.appendingPathExtension("zip"), URL(fileURLWithPath: dir.path + ".parts")] {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

/// The address and home in UserDefaults; the device key in the Keychain.
public struct DefaultsConnectionStore: ConnectionStore {
    nonisolated(unsafe) let defaults: UserDefaults  // UserDefaults is thread-safe
    let keychain: any SecretStore

    public init(defaults: UserDefaults = .standard, keychain: any SecretStore = Keychain()) {
        self.defaults = defaults; self.keychain = keychain
    }

    public func load() -> Connection {
        Connection(address: defaults.string(forKey: "serverURL") ?? "", key: keychain.read("deviceKey") ?? "",
                   home: defaults.string(forKey: "homeId") ?? "flat")
    }

    public func save(_ c: Connection) {
        defaults.set(c.address, forKey: "serverURL")
        defaults.set(c.home, forKey: "homeId")
        keychain.write(c.key, account: "deviceKey")
    }
}

/// Where secrets live (the Keychain on the phone; a dictionary in tests).
public protocol SecretStore: Sendable {
    func read(_ account: String) -> String?
    func write(_ value: String, account: String)
}

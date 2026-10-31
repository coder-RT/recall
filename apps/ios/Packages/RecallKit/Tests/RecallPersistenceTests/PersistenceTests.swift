import Foundation
import RecallDomain
import Testing
@testable import RecallPersistence

private func tempDir() -> URL {
    let dir = FileManager.default.temporaryDirectory.appending(path: "recall-tests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private final class MemorySecrets: SecretStore, @unchecked Sendable {
    var values: [String: String] = [:]
    func read(_ account: String) -> String? { values[account] }
    func write(_ value: String, account: String) { values[account] = value }
}

@Test func scanLibraryRoundTrip() {
    let library = FileScanLibrary(file: tempDir().appending(path: "scans.json"))
    #expect(library.load().isEmpty)
    var scan = Scan(id: "a", room: "Kitchen", createdAt: Date(timeIntervalSince1970: 1_800_000_000), grade: .good,
                    directions: 9, frames: 40)
    scan.apply(.processing)
    library.save([scan])
    #expect(library.load() == [scan])
}

@Test func episodeFilesFindManifestAndMapAndDeleteEverything() throws {
    let files = FileEpisodeFiles(root: tempDir())
    let dir = files.directory(scan: "x")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try Data("map".utf8).write(to: dir.appending(path: "worldmap.arworldmap"))
    try Data("zip".utf8).write(to: dir.appendingPathExtension("zip"))
    #expect(files.roomMap(scan: "x") == Data("map".utf8))
    #expect(files.manifest(scan: "x") == nil)  // no manifest yet
    files.delete(scan: "x")
    #expect(!FileManager.default.fileExists(atPath: dir.path))
    #expect(!FileManager.default.fileExists(atPath: dir.appendingPathExtension("zip").path))
}

@Test func connectionKeepsTheKeyOutOfUserDefaults() throws {
    let defaults = try #require(UserDefaults(suiteName: "recall-tests-\(UUID().uuidString)"))
    let secrets = MemorySecrets()
    let store = DefaultsConnectionStore(defaults: defaults, keychain: secrets)
    store.save(Connection(address: "mac:8000", key: "secret", home: "loft"))
    #expect(store.load() == Connection(address: "mac:8000", key: "secret", home: "loft"))
    #expect(secrets.values["deviceKey"] == "secret")
    #expect(defaults.dictionaryRepresentation().values.contains { ($0 as? String) == "secret" } == false)
}

import Foundation
import Observation
import RecallDomain
import RecallNetworking
import RecallUpload
import RecallVoice

/// A scan the phone has recorded, and where its upload stands.
struct ScanRecord: Codable, Identifiable, Equatable {
    let id: String
    var room: String
    var createdAt: Date
    var grade: ScanGrade
    var directions: Int
    var frames: Int
    var uploadPhase: String?
    var uploadDetail: String?
    var uploadFraction: Double?
}

/// App state: settings, the local scan library, uploads. Feature screens talk to it; it talks to RecallKit's ports.
@MainActor @Observable
final class AppModel {
    static let sharedUploader = Uploader()

    var scans: [ScanRecord] = []
    var serverURL: String { didSet { UserDefaults.standard.set(serverURL, forKey: "serverURL") } }
    var homeId: String { didSet { UserDefaults.standard.set(homeId, forKey: "homeId") } }
    var deviceKey: String { didSet { Keychain.write(deviceKey, account: "deviceKey") } }

    let announcer = Announcer()
    let uploader = AppModel.sharedUploader

    init() {
        serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? ""
        homeId = UserDefaults.standard.string(forKey: "homeId") ?? "flat"
        deviceKey = Keychain.read("deviceKey") ?? ""
        scans = (try? JSONDecoder.iso.decode([ScanRecord].self, from: Data(contentsOf: Self.libraryFile))) ?? []
    }

    var isConfigured: Bool { api != nil }

    var api: RecallAPI? {
        guard let url = URL(string: serverURL.trimmingCharacters(in: .whitespaces)), url.scheme?.hasPrefix("http") == true,
              !deviceKey.isEmpty else { return nil }
        return RecallAPI(baseURL: url, deviceKey: deviceKey)
    }

    static var episodesDir: URL {
        let dir = URL.applicationSupportDirectory.appending(path: "Episodes")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var libraryFile: URL { URL.applicationSupportDirectory.appending(path: "scans.json") }

    func episodeDir(_ id: String) -> URL { Self.episodesDir.appending(path: "scan-\(id)") }

    func start() async {
        await uploader.observe { [weak self] id, progress in
            Task { @MainActor in self?.apply(id, progress) }
        }
    }

    func add(_ record: ScanRecord) {
        scans.insert(record, at: 0)
        save()
    }

    func upload(_ record: ScanRecord) {
        guard let api else {
            announcer.say("Set the Mac's address and device key in Settings first.")
            return
        }
        let dir = episodeDir(record.id)
        guard let data = try? Data(contentsOf: dir.appending(path: "manifest.json")),
              let manifest = try? JSONDecoder.iso.decode(Manifest.self, from: data) else {
            announcer.say("This scan's files are incomplete. Scan the room again.")
            return
        }
        announcer.say("Uploading \(record.room).")
        let home = homeId
        Task { await uploader.upload(scanId: record.id, homeId: home, room: record.room, episode: dir, manifest: manifest, api: api) }
    }

    /// The zip for AirDrop or Files, built on demand (call off the main thread).
    nonisolated static func archive(_ episode: URL) -> URL? {
        guard FileManager.default.fileExists(atPath: episode.appending(path: "manifest.json").path) else { return nil }
        return try? EpisodeArchive.make(episode: episode).zip
    }

    func delete(_ record: ScanRecord) {
        let dir = episodeDir(record.id)
        for url in [dir, dir.appendingPathExtension("zip"), URL(fileURLWithPath: dir.path + ".parts")] {
            try? FileManager.default.removeItem(at: url)
        }
        scans.removeAll { $0.id == record.id }
        save()
    }

    private func apply(_ id: String, _ p: UploadProgress) {
        guard let i = scans.firstIndex(where: { $0.id == id }) else { return }
        let before = scans[i].uploadPhase
        scans[i].uploadPhase = p.phase.rawValue
        scans[i].uploadDetail = p.detail
        scans[i].uploadFraction = p.fraction
        save()
        guard before != p.phase.rawValue else { return }
        switch p.phase {
        case .processing: announcer.say("\(scans[i].room) is uploaded. The Mac is processing it.")
        case .failed: announcer.say("Upload failed. \(p.detail ?? "")")
        default: break
        }
    }

    private func save() {
        try? JSONEncoder.iso.encode(scans).write(to: Self.libraryFile, options: .atomic)
    }
}

extension JSONDecoder {
    static var iso: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
}

extension JSONEncoder {
    static var iso: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }
}

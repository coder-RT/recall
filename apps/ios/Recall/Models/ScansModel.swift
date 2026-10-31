import Foundation
import Observation
import RecallApplication
import RecallDomain

/// The scans this phone made: their files, their uploads and the Mac's processing, spoken as they change.
@MainActor @Observable
final class ScansModel {
    private(set) var scans: [Scan]

    private let library: any ScanLibrary
    private let files: any EpisodeFiles
    private let archiver: any EpisodeArchiving
    private let uploads: any ScanUploading
    private let upload: UploadScan
    private let track: TrackProcessing
    private let settings: SettingsModel
    private let things: ThingsModel
    private let speech: any SpeechOutput
    private let clock: any Clock

    init(library: any ScanLibrary, files: any EpisodeFiles, archiver: any EpisodeArchiving, uploads: any ScanUploading,
         upload: UploadScan, track: TrackProcessing, settings: SettingsModel, things: ThingsModel,
         speech: any SpeechOutput, clock: any Clock) {
        self.library = library; self.files = files; self.archiver = archiver; self.uploads = uploads; self.upload = upload
        self.track = track; self.settings = settings; self.things = things; self.speech = speech; self.clock = clock
        scans = library.load()
    }

    /// Listens to uploads and asks the Mac about processing scans every 10 s, for the app's life.
    func start() async {
        await uploads.observe { [weak self] id, state in Task { @MainActor in self?.apply(id, state) } }
        while !Task.isCancelled {
            let changes = await track(scans, home: settings.connection.homeId)
            for (id, state) in changes { apply(id, state, announce: false) }
            if changes.values.contains(.processed) { await things.refresh() }
            try? await clock.sleep(seconds: 10)
        }
    }

    func add(_ scan: Scan) {
        scans.insert(scan, at: 0)
        library.save(scans)
    }

    /// Starts the upload; the reason it can't start is spoken and returned (shown on screen).
    @discardableResult
    func upload(_ scan: Scan) -> String? {
        do {
            try upload(scan, connection: settings.connection)
            return nil
        } catch {
            let message = UserMessage.explain(error)
            speech.say(message, interrupt: false)
            return message
        }
    }

    func delete(_ scan: Scan) {
        files.delete(scan: scan.id)
        scans.removeAll { $0.id == scan.id }
        library.save(scans)
    }

    /// The zip for AirDrop or Files, built off the main thread.
    func archive(_ scan: Scan) async -> URL? {
        let (dir, archiver) = (files.directory(scan: scan.id), archiver)
        return await Task.detached { archiver.archive(episode: dir) }.value
    }

    /// The saved room map to relocalise in: the home's first processed scan made on this phone (routes are planned
    /// in that scan's world).
    func roomMap() -> Data? {
        scans.filter(\.isProcessed).sorted { $0.createdAt < $1.createdAt }.lazy.compactMap { self.files.roomMap(scan: $0.id) }.first
    }

    private func apply(_ id: String, _ state: UploadState, announce: Bool = true) {
        guard let i = scans.firstIndex(where: { $0.id == id }) else { return }
        let changed = scans[i].apply(state)
        library.save(scans)
        guard announce, changed else { return }
        switch state {
        case .processing: speech.say("\(scans[i].room) is uploaded. The Mac is processing it.", interrupt: false)
        case .failed: speech.say("Upload failed. The reason is on the scan.", interrupt: false)
        default: break
        }
    }
}

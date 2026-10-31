import Foundation
import RecallApplication
import RecallCapture
import RecallDomain
import RecallNetworking
import RecallPersistence
import RecallUpload
import RecallVoice

/// Composition root: the only place adapters are built and handed to use cases and models (the same idea as the
/// API's infra/container.py). Everything else depends on ports.
@MainActor
final class AppContainer {
    /// One background upload session for the app's life; the app delegate hands it relaunch events.
    static let uploader = Uploader()

    let speech = Announcer()
    let haptics = Haptics()
    let compass = CoreLocationCompass()
    /// One ARKit locator for every guide: prepared when Find answers, so the room is often recognised before
    /// "Take me there" is tapped, and paused (not reset) between guides.
    let locator = ARLocator()
    private var guiding = false
    private var idle: Task<Void, Never>?
    let clock: any Clock = SystemClock()
    let server = LiveServer()
    let files: any EpisodeFiles = FileEpisodeFiles()
    let router = Router()

    let settings: SettingsModel
    let things: ThingsModel
    let scans: ScansModel

    init() {
        let store = DefaultsConnectionStore()
        settings = SettingsModel(store: store, server: server, pair: PairDevice(store: store),
                                 test: TestConnection(check: server), speech: speech)
        things = ThingsModel(load: LoadThings(memory: server), correct: CorrectThing(memory: server),
                             forget: ForgetThing(memory: server), settings: settings, speech: speech)
        scans = ScansModel(library: FileScanLibrary(), files: files, archiver: ZipArchiver(), uploads: Self.uploader,
                           upload: UploadScan(files: files, uploads: Self.uploader, server: server, speech: speech),
                           track: TrackProcessing(processing: server, memory: server, speech: speech),
                           settings: settings, things: things, speech: speech, clock: clock)
        if UITestSamples.enabled {
            things.useForUITests(UITestSamples.things)
            scans.useForUITests(UITestSamples.scans)
        }
    }

    func findModel() -> FindModel {
        FindModel(ask: AskWhereIs(guide: server), transcriber: server, voice: WavRecorder(), things: things,
                  settings: settings, speech: speech, haptics: haptics,
                  prepareGuide: { [weak self] in self?.prepareGuide() })
    }

    /// Starts recognising the saved room in the background; paused again if no guide starts within a minute.
    func prepareGuide() {
        guard ARLocator.isSupported, !guiding, let map = scans.roomMap() else { return }
        locator.prepare(roomMap: map)
        idle?.cancel()
        idle = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard let self, !Task.isCancelled, !self.guiding else { return }
            self.locator.stop()
        }
    }

    func guideModel(for thing: Thing) -> GuideModel {
        idle?.cancel()
        guiding = true
        let use = GuideToThing(home: settings.connection.homeId, thing: thing, roomMap: scans.roomMap(), locator: locator,
                               guide: server, speech: speech, haptics: haptics, clock: clock, compass: compass)
        return GuideModel(guide: use, session: locator.session, scene: locator.scene, supported: ARLocator.isSupported,
                          ended: { [weak self] in self?.guiding = false })
    }

    /// `again`: a processed scan of this room to scan again in the same frame (its room map is recognised first).
    func scanModel(room: String, again: Scan? = nil) -> ScanModel {
        idle?.cancel()
        locator.stop()  // one ARKit session at a time: the scan needs the camera
        let rescan = again.flatMap { s in scans.roomMap(scan: s).map { (scanId: s.id, roomMap: $0) } }
        return ScanModel(room: room, rescan: rescan, scans: scans, files: files, compass: compass, speech: speech,
                         haptics: haptics)
    }
}

/// The real clock.
struct SystemClock: Clock {
    func now() -> Date { Date() }
    func sleep(seconds: Double) async throws { try await Task.sleep(for: .seconds(seconds)) }
}

/// The Mac, as every Mac-facing port, reached with the current connection settings. Changing Settings swaps the
/// client underneath; a call made before setup throws the setup issue, in words.
final class LiveServer: HomeMemory, GuideService, Transcriber, ScanProcessing, ConnectionCheck, ScanServer, @unchecked Sendable {
    private let lock = NSLock()
    private var api: RecallAPI?
    private var issue: SetupIssue = .nothingSet

    func use(_ connection: Connection) {
        lock.withLock {
            if let url = connection.url, connection.issue == nil {
                api = RecallAPI(baseURL: url, deviceKey: connection.cleanKey)
            } else {
                api = nil
                issue = connection.issue ?? .nothingSet
            }
        }
    }

    private func current() throws -> RecallAPI {
        try lock.withLock {
            guard let api else { throw RecallError.setup(issue) }
            return api
        }
    }

    func things(home: String) async throws -> [Thing] { try await current().things(home: home) }
    func correct(home: String, thing: String, _ c: Correction) async throws { try await current().correct(home: home, thing: thing, c) }
    func forget(home: String, thing: String) async throws { try await current().forget(home: home, thing: thing) }
    func ask(home: String, question: String) async throws -> Answer { try await current().ask(home: home, question: question) }
    func route(home: String, to thing: String, from pose: Pose, tracking: TrackingState) async throws -> Route {
        try await current().route(home: home, to: thing, from: pose, tracking: tracking)
    }
    func transcribe(wav: Data) async throws -> String { try await current().transcribe(wav: wav) }
    func status(scan: String) async throws -> ScanReport { try await current().status(scan: scan) }
    func check() async throws -> String { try await current().check() }
    func createScan(scan: String, home: String, room: String, size: Int, sha256: String, partSize: Int) async throws -> UploadPlan {
        try await current().createScan(scan: scan, home: home, room: room, size: size, sha256: sha256, partSize: partSize)
    }
    // only called mid-upload, after createScan succeeded with the same client
    func partRequest(path: String, sha256: String) -> URLRequest {
        (try? current())?.partRequest(path: path, sha256: sha256) ?? URLRequest(url: URL(string: "about:blank")!)
    }
    func putManifest(scan: String, manifest: Manifest) async throws { try await current().putManifest(scan: scan, manifest: manifest) }
    func complete(scan: String) async throws -> (ScanStatus, detail: String?) { try await current().complete(scan: scan) }
}

/// The app's tabs and the walk in progress (shown over every tab).
enum AppTab: Hashable { case devices, find, scans, found, settings }

@MainActor @Observable
final class Router {
    var tab = AppTab.find
    var guiding: Thing?
}

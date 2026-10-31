import Foundation
import RecallDomain

// Fakes for every port: scripted answers in, recorded calls out. No network, ARKit, files or audio.

public extension Thing {
    static func sample(_ id: String = "obj_1", label: String = "keys", color: String? = "red", needsReview: Bool = false,
                       landmark: String? = "desk", room: String? = "Living room", heightBand: String = "waist",
                       name: String? = nil) -> Thing {
        Thing(id: id, label: label, name: name, color: color, heightM: 0.75, heightBand: heightBand, landmark: landmark,
              relation: "on", room: room, confidence: needsReview ? 0.6 : 0.9, needsReview: needsReview,
              seenAt: Date(timeIntervalSince1970: 1_800_000_000))
    }
}

public final class FakeHomeMemory: HomeMemory, @unchecked Sendable {
    public var things: [Thing]
    public var error: Error?
    public private(set) var corrections: [(String, Correction)] = []
    public private(set) var forgotten: [String] = []

    public init(things: [Thing] = [], error: Error? = nil) { self.things = things; self.error = error }

    public func things(home: String) async throws -> [Thing] {
        if let error { throw error }
        return things
    }
    public func correct(home: String, thing: String, _ correction: Correction) async throws {
        if let error { throw error }
        corrections.append((thing, correction))
    }
    public func forget(home: String, thing: String) async throws {
        if let error { throw error }
        forgotten.append(thing)
        things.removeAll { $0.id == thing }
    }
}

public final class FakeGuide: GuideService, @unchecked Sendable {
    public var answer: Answer
    /// Routes handed out in order; the last one repeats.
    public var routes: [Route]
    public var error: Error?
    public private(set) var routeRequests: [(pose: Pose, tracking: TrackingState)] = []

    public init(answer: Answer = Answer(text: "On the desk.", thingId: "obj_1", grounded: true), routes: [Route] = [],
                error: Error? = nil) {
        self.answer = answer; self.routes = routes; self.error = error
    }

    public func ask(home: String, question: String) async throws -> Answer {
        if let error { throw error }
        return answer
    }
    public func route(home: String, to thing: String, from pose: Pose, tracking: TrackingState) async throws -> Route {
        if let error { throw error }
        routeRequests.append((pose, tracking))
        return routes.count > 1 ? routes.removeFirst() : routes[0]
    }
    /// The arrival check's answer (nil: the Mac can't check, the call throws).
    public var check: ArrivalCheck? = ArrivalCheck(outcome: .confirmed, say: "Found it. Your keys are at 12 o'clock, 40 centimetres away.")
    public private(set) var verified: [ArrivalFrame] = []
    public func verify(session: String, frame: ArrivalFrame) async throws -> ArrivalCheck {
        verified.append(frame)
        guard let check else { throw RecallError.status(501) }
        return check
    }
}

public final class FakeProcessing: ScanProcessing, @unchecked Sendable {
    public var reports: [String: ScanReport]
    public init(_ statuses: [String: (ScanStatus, String?)] = [:]) {
        reports = statuses.mapValues { ScanReport($0.0, detail: $0.1) }
    }
    public init(reports: [String: ScanReport]) { self.reports = reports }
    public func status(scan: String) async throws -> ScanReport {
        guard let r = reports[scan] else { throw RecallError.status(404) }
        return r
    }
}

public struct FakeConnectionCheck: ConnectionCheck {
    public let result: Result<String, RecallError>
    public init(_ result: Result<String, RecallError>) { self.result = result }
    public func check() async throws -> String { try result.get() }
}

public final class FakeConnectionStore: ConnectionStore, @unchecked Sendable {
    public var connection: Connection
    public init(_ connection: Connection = Connection(address: "", key: "", home: "flat")) { self.connection = connection }
    public func load() -> Connection { connection }
    public func save(_ connection: Connection) { self.connection = connection }
}

/// Time that only moves when the code under test sleeps: loops run instantly and deterministically.
public final class FakeClock: Clock, @unchecked Sendable {
    public private(set) var current = Date(timeIntervalSince1970: 1_800_000_000)
    public var onSleep: (() -> Void)?
    public init() {}
    public func now() -> Date { current }
    public func sleep(seconds: Double) async throws {
        current = current.addingTimeInterval(seconds)
        onSleep?()
        await Task.yield()
    }
}

@MainActor public final class FakeSpeech: SpeechOutput {
    public private(set) var lines: [String] = []
    public init() {}
    public func say(_ text: String, interrupt: Bool) { lines.append(text) }
    public func stop() {}
}

@MainActor public final class FakeHaptics: HapticsOutput {
    public private(set) var events: [String] = []
    public init() {}
    public func tap() { events.append("tap") }
    public func success() { events.append("success") }
    public func warning() { events.append("warning") }
}

/// Plays back a scripted walk: each `reading()` returns the next pose (the last one repeats).
@MainActor public final class FakeLocator: Locator {
    public var mapReadable: Bool
    public var readings: [(pose: Pose, tracking: TrackingState)]
    public private(set) var startedWithMap: Bool?
    public private(set) var stopped = false
    public private(set) var marks: [SIMD3<Double>?] = []

    public init(mapReadable: Bool = true, readings: [(Pose, TrackingState)]) {
        self.mapReadable = mapReadable
        self.readings = readings.map { (pose: $0.0, tracking: $0.1) }
    }

    public func start(roomMap: Data?) -> Bool {
        startedWithMap = roomMap != nil
        return roomMap == nil || mapReadable
    }
    public func stop() { stopped = true }
    public private(set) var paths: [[SIMD2<Double>]] = []
    public func mark(_ target: SIMD3<Double>?) { marks.append(target) }
    public func showPath(_ path: [SIMD2<Double>], floorY: Double?) { paths.append(path) }
    /// The frame the arrival check gets (nil: the camera has none).
    public var frame: ArrivalFrame? = ArrivalFrame.sample
    public func arrivalFrame() -> ArrivalFrame? { frame }
    public func reading() -> (pose: Pose, tracking: TrackingState)? {
        guard !readings.isEmpty else { return nil }
        return readings.count > 1 ? readings.removeFirst() : readings[0]
    }
}

public extension Pose {
    /// A pose at (x, z) on the floor, facing `yawDegrees` (0 looks along −z, 90 along +x).
    static func at(x: Double, z: Double, yawDegrees: Double = 0) -> Pose {
        let a = yawDegrees * .pi / 180
        // camera −Z (forward) = (sin a, 0, −cos a) → column 2 = (−sin a, 0, cos a)
        return Pose(columnMajor: [cos(a), 0, sin(a), 0, 0, 1, 0, 0, -sin(a), 0, cos(a), 0, x, 1.4, z, 1])
    }
}

@MainActor public final class FakeVoice: VoiceInput {
    public var allowed = true
    public var recording = Data("RIFF".utf8)
    public private(set) var isRecording = false
    private var finished: (@MainActor (Data?) -> Void)?
    public init() {}
    public func start(maxSeconds: Double, finished: @escaping @MainActor (Data?) -> Void) async -> Bool {
        guard allowed else { return false }
        isRecording = true
        self.finished = finished
        return true
    }
    public func stop() { end() }
    /// What the real recorder does when time runs out.
    public func timeOut() { end() }
    private func end() {
        guard isRecording else { return }
        isRecording = false
        finished?(recording)
        finished = nil
    }
}

public final class FakeEpisodeFiles: EpisodeFiles, @unchecked Sendable {
    public var manifests: [String: Manifest] = [:]
    public var maps: [String: Data] = [:]
    public private(set) var deleted: [String] = []
    public init() {}
    public func directory(scan: String) -> URL { URL(fileURLWithPath: "/tmp/scan-\(scan)") }
    public func manifest(scan: String) -> Manifest? { manifests[scan] }
    public func roomMap(scan: String) -> Data? { maps[scan] }
    public func delete(scan: String) { deleted.append(scan) }
}

public actor FakeUploads: ScanUploading {
    public private(set) var started: [String] = []
    public init() {}
    public func observe(_ listener: @escaping @Sendable (String, UploadState) -> Void) {}
    public func upload(scan: String, home: String, room: String, episode: URL, manifest: Manifest, server: any ScanServer) {
        started.append(scan)
    }
}

/// A server that only records that it was handed over (uploads are faked above).
public struct FakeScanServer: ScanServer {
    public init() {}
    public func createScan(scan: String, home: String, room: String, size: Int, sha256: String, partSize: Int) async throws -> UploadPlan {
        UploadPlan(parts: [])
    }
    public func partRequest(path: String, sha256: String) -> URLRequest { URLRequest(url: URL(string: "http://mac/\(path)")!) }
    public func putManifest(scan: String, manifest: Manifest) async throws {}
    public func complete(scan: String) async throws -> (ScanStatus, detail: String?) { (.processing, nil) }
}

public extension Manifest {
    static func sample(scan: String) -> Manifest {
        Manifest(scanId: scan, device: "iPhone17,1", appVersion: "1", createdAt: Date(timeIntervalSince1970: 1_800_000_000),
                 durationS: 30, frameCount: 40, image: .init(width: 1024, height: 768),
                 depth: .init(width: 256, height: 192), intrinsics: .init(fx: 1, fy: 1, cx: 0, cy: 0), worldMap: nil,
                 files: [], captureMetrics: CaptureMetrics(directionsCovered: 10, keyframesKept: 40, keyframesDroppedBlurry: 1,
                                                           trackingNormalRatio: 0.95, meanSpeedMps: 0.4, peakSpeedMps: 0.8,
                                                           slowDownCues: 0, areaWalkedM2: 6, meanLightLux: 300))
    }
}

/// A compass that reads whatever the test sets.
@MainActor public final class FakeCompass: CompassSensor {
    public var reading: HeadingReading?
    public private(set) var running = false
    public init(_ reading: HeadingReading? = nil) { self.reading = reading }
    public func start() { running = true }
    public func stop() { running = false }
}

public extension ArrivalFrame {
    static let sample = ArrivalFrame(jpeg: Data("jpeg".utf8), depthMM: Data(count: 8), depthSize: (2, 2),
                                     imageSize: (640, 480), intrinsics: (500, 500, 320, 240),
                                     pose: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1])
}

/// Robot Access kept in memory; the map package is built from a small made-up map.
public final class FakeRobotSharing: RobotSharing, @unchecked Sendable {
    public var on = false
    public var error: Error?
    public init() {}
    public func robotAccess() async throws -> RobotAccessStatus {
        if let error { throw error }
        return status
    }
    public func setRobotAccess(_ on: Bool) async throws -> RobotAccessStatus {
        if let error { throw error }
        self.on = on
        return status
    }
    public var entries: [AuditEntry] = []
    public func activity(limit: Int) async throws -> [AuditEntry] { Array(entries.prefix(limit)) }
    public func robotMap(home: String) async throws -> RobotMapPackage {
        if let error { throw error }
        let map = RobotMap(width: 4, height: 3, resolution: 0.1, origin: (0, 0), shades: [254, 254, 0, 128, 254, 254, 0, 128, 254, 254, 254, 128])
        return RobotMapPackage(room: "Living room", map: map, things: [.init(label: "keys", color: "beige", x: 0.15, y: 0.05)],
                               files: ["map.pgm": Data("P5".utf8), "map.yaml": Data(), "objects.json": Data("{}".utf8), "room.json": Data()])
    }
    var status: RobotAccessStatus {
        RobotAccessStatus(on: on, a2aURL: "http://mac.local:8000/a2a/home-memory",
                          agentCardURL: "http://mac.local:8000/a2a/home-memory/.well-known/agent-card.json",
                          exportURL: "http://mac.local:8000/homes/flat/robot-export")
    }
}

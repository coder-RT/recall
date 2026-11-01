import Foundation

// Ports: what the app needs from the outside world, one small protocol per job (adapters implement them in
// RecallNetworking, RecallUpload, RecallCapture, RecallVoice and RecallPersistence; RecallTestSupport fakes them).

// MARK: The Mac

/// What the Mac remembers about a home.
public protocol HomeMemory: Sendable {
    func things(home: String) async throws -> [Thing]
    func correct(home: String, thing: String, _ correction: Correction) async throws
    func forget(home: String, thing: String) async throws
}

/// Each room's map, with the things in it, for the owner's own screens (not recorded as a robot export).
/// Everything found in a room, placed in that room's saved AR map (labels over the camera).
public protocol ArLabelsSource: Sendable {
    func arLabels(home: String, room: String) async throws -> ArLabels
}

/// Directions by compass for the Watch, from where the room's scan began (the Mac plans them).
public protocol CompassRoutes: Sendable {
    func compassRoute(home: String, thing: String) async throws -> CompassRoute
}

/// The owner's trust level, kept on the Mac.
public protocol TrustSettings: Sendable {
    func trustLevel() async throws -> TrustLevel
    func setTrustLevel(_ level: TrustLevel) async throws -> TrustLevel
}

/// One room's package for a robot, made by the Mac: a .zip of the files a robot loads (Nav2 map, things, room
/// outline, 3D points, README). `room` nil is the newest scan's room.
public protocol RobotPackages: Sendable {
    func robotPackage(home: String, room: String?) async throws -> Data
}

public protocol RoomMaps: Sendable {
    func roomMap(home: String, room: String) async throws -> RobotMapPackage
}

/// The Guide agent and the route planner.
public protocol GuideService: Sendable {
    /// `about`: the thing the last answer was about, so "why do you think so?" knows what "so" is.
    func ask(home: String, question: String, about: String?) async throws -> Answer
    func route(home: String, to thing: String, from pose: Pose, tracking: TrackingState) async throws -> Route
    /// The arrival check: is the thing really there? (SAM 3.1 + depth + geometry on the Mac)
    func verify(session: String, frame: ArrivalFrame) async throws -> ArrivalCheck
}

/// Speech to text on the Mac (Muse Voice Transcribe), from mono 16-bit WAV at 16 kHz.
public protocol Transcriber: Sendable {
    func transcribe(wav: Data) async throws -> String
}

/// The Mac's processing status of an uploaded scan.
public protocol ScanProcessing: Sendable {
    func status(scan: String) async throws -> ScanReport
    /// Erases the scan from the Mac: its photos and files, and what memory learnt only from it.
    func erase(scan: String) async throws
}

/// Why an answer said what it said: the sightings behind it, and the camera's view of each.
public protocol EvidenceSource: Sendable {
    func evidence(answer: String) async throws -> Evidence
    func crop(path: String) async throws -> Data
}

/// What the Mac keeps and sends where, under its current settings.
public protocol PrivacySource: Sendable {
    func privacy() async throws -> PrivacyStatus
}

/// That the Mac answers and accepts the key; returns the model the Guide runs on.
public protocol ConnectionCheck: Sendable {
    func check() async throws -> String
}

/// The upload steps the Mac offers (POST /scans, the parts, the manifest, complete).
public protocol ScanServer: Sendable {
    func createScan(scan: String, home: String, room: String, size: Int, sha256: String, partSize: Int) async throws -> UploadPlan
    func partRequest(path: String, sha256: String) -> URLRequest
    func putManifest(scan: String, manifest: Manifest) async throws
    func complete(scan: String) async throws -> (ScanStatus, detail: String?)
}

/// The server's plan for a resumable upload: which parts it already has.
public struct UploadPlan: Sendable {
    public struct Part: Sendable {
        public let number: Int; public let path: String; public let received: Bool
        public init(number: Int, path: String, received: Bool) { self.number = number; self.path = path; self.received = received }
    }
    public let parts: [Part]
    public init(parts: [Part]) { self.parts = parts }
}

// MARK: This phone

/// Sends a scan to the Mac in the background and reports each change of its upload state.
public protocol ScanUploading: Sendable {
    func observe(_ listener: @escaping @Sendable (_ scan: String, UploadState) -> Void) async
    func upload(scan: String, home: String, room: String, episode: URL, manifest: Manifest, server: any ScanServer) async
}

/// The list of scans this phone has made.
public protocol ScanLibrary: Sendable {
    func load() -> [Scan]
    func save(_ scans: [Scan])
}

/// The scans' files on this phone: episode folders, their manifests and the saved room maps.
public protocol EpisodeFiles: Sendable {
    func directory(scan: String) -> URL
    func manifest(scan: String) -> Manifest?
    func roomMap(scan: String) -> Data?
    func delete(scan: String)
}

/// A zip of an episode folder for AirDrop or Files (slow: call off the main thread).
public protocol EpisodeArchiving: Sendable {
    func archive(episode: URL) -> URL?
}

/// Where the connection settings live (the key goes to the Keychain).
public protocol ConnectionStore: Sendable {
    func load() -> Connection
    func save(_ connection: Connection)
}

/// Clock and waiting, so use cases run instantly in tests.
public protocol Clock: Sendable {
    func now() -> Date
    func sleep(seconds: Double) async throws
}

// MARK: Senses and feedback (main thread)

@MainActor public protocol SpeechOutput: AnyObject {
    func say(_ text: String, interrupt: Bool)
    func stop()
}

@MainActor public protocol HapticsOutput: AnyObject {
    func tap()
    func success()
    func warning()
}

/// Records a spoken question. `finished` is called once, with the recording, when the user stops or time runs out.
@MainActor public protocol VoiceInput: AnyObject {
    var isRecording: Bool { get }
    func start(maxSeconds: Double, finished: @escaping @MainActor (Data?) -> Void) async -> Bool
    func stop()
}

/// The phone's place in the room for guidance: relocalises in a saved room map, then reports the camera's pose.
@MainActor public protocol Locator: AnyObject {
    func start(roomMap: Data?) -> Bool  // false when the saved map can't be read
    func stop()
    /// The latest pose and whether tracking is normal (nil before the first frame).
    func reading() -> (pose: Pose, tracking: TrackingState)?
    /// Shows an arrow pointing down at this spot in the camera view (nil removes it).
    func mark(_ target: SIMD3<Double>?)
    /// One camera frame with depth and pose, for the arrival check (nil when the camera has none yet).
    func arrivalFrame() -> ArrivalFrame?
    /// Lays arrows on the floor along the route (ARKit x, z), at the floor's height when known; empty clears them.
    func showPath(_ path: [SIMD2<Double>], floorY: Double?)
}

/// The phone's compass (magnetic north; no location is read).
@MainActor public protocol CompassSensor: AnyObject {
    func start()
    func stop()
    /// The latest reading, nil before the first.
    var reading: HeadingReading? { get }
}

/// Robot Access on the Mac: the owner's switch, and the robot map package for sharing.
public protocol RobotSharing: Sendable {
    func robotAccess() async throws -> RobotAccessStatus
    func setRobotAccess(_ on: Bool) async throws -> RobotAccessStatus
    func robotMap(home: String) async throws -> RobotMapPackage
    /// The newest entries of the Mac's audit log (the owner's key only).
    func activity(limit: Int) async throws -> [AuditEntry]
}

public extension GuideService {
    func ask(home: String, question: String) async throws -> Answer { try await ask(home: home, question: question, about: nil) }
}

import ARKit
import Foundation
import RecallDomain

/// What the Scan screen shows and says, about 10 times a second.
public struct CaptureUpdate: Sendable, Equatable {
    public var elapsed: Double
    public var directionsCovered: Int
    public var keyframes: Int
    public var droppedBlurry: Int
    public var tracking: TrackingState
    public var coach: SpeedCoach.Event?
    public var lightLux: Double

    public init(elapsed: Double, directionsCovered: Int, keyframes: Int, droppedBlurry: Int, tracking: TrackingState,
                coach: SpeedCoach.Event?, lightLux: Double) {
        self.elapsed = elapsed; self.directionsCovered = directionsCovered; self.keyframes = keyframes
        self.droppedBlurry = droppedBlurry; self.tracking = tracking; self.coach = coach; self.lightLux = lightLux
    }
}

/// Plain ARKit world tracking on our own ARSession with LiDAR scene depth. No scene reconstruction and no plane
/// detection or classification (those are Apple models; CLAUDE.md rule 8).
public final class CaptureSession: NSObject, ARSessionDelegate, @unchecked Sendable {
    public let session = ARSession()
    private let queue = DispatchQueue(label: "recall.capture", qos: .userInitiated)

    // capture-queue state
    private var writer: EpisodeWriter?
    private var selector = KeyframeSelector()
    private var coverage = CoverageTracker()
    private var coach = SpeedCoach()
    private var start: TimeInterval?
    private var startedAt = Date()
    private var lastEmit: Double = -1
    private var lastBlurCheck: Double = -1
    private var keptSharpness: [Float] = []
    private var dropped = 0
    private var pendingCoach: SpeedCoach.Event?

    public var onUpdate: (@Sendable (CaptureUpdate) -> Void)?

    public static var isSupported: Bool {
        ARWorldTrackingConfiguration.isSupported && ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
    }

    public func start(writer: EpisodeWriter) {
        queue.sync {
            self.writer = writer
            selector = KeyframeSelector(); coverage = CoverageTracker(); coach = SpeedCoach()
            start = nil; startedAt = Date(); lastEmit = -1; lastBlurCheck = -1; keptSharpness = []; dropped = 0
        }
        let config = ARWorldTrackingConfiguration()
        config.frameSemantics = [.sceneDepth]
        config.planeDetection = []
        config.environmentTexturing = .none
        config.isLightEstimationEnabled = true
        session.delegateQueue = queue
        session.delegate = self
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    /// Stops, saves the world map and writes the manifest last. Throws when too few frames were kept.
    public func finish(device: String, appVersion: String) async throws -> Manifest {
        let mapData = try? await currentWorldMapData()
        session.pause()
        return try queue.sync {
            guard let writer, writer.frameCount > 0 else { throw CaptureError.noFrames }
            let metrics = CaptureMetrics(
                directionsCovered: coverage.directionsCovered, keyframesKept: writer.frameCount,
                keyframesDroppedBlurry: dropped, trackingNormalRatio: coverage.trackingNormalRatio,
                meanSpeedMps: coverage.meanSpeed, peakSpeedMps: coverage.peakSpeed, slowDownCues: coach.cues,
                areaWalkedM2: coverage.areaWalked, meanLightLux: coverage.meanLight)
            let duration = Date().timeIntervalSince(startedAt)
            self.writer = nil
            return try writer.finish(worldMap: mapData, metrics: metrics, duration: duration, device: device,
                                     appVersion: appVersion, createdAt: startedAt)
        }
    }

    public func cancel() {
        session.pause()
        queue.sync { writer = nil }
    }

    /// The ARWorldMap, archived inside ARKit's callback (the map object itself must not cross threads).
    private func currentWorldMapData() async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            session.getCurrentWorldMap { map, error in
                if let map, let data = try? NSKeyedArchiver.archivedData(withRootObject: map, requiringSecureCoding: true) {
                    cont.resume(returning: data)
                } else {
                    cont.resume(throwing: error ?? CaptureError.noWorldMap)
                }
            }
        }
    }

    // MARK: ARSessionDelegate (called on `queue`)

    public func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard let writer else { return }
        let t0 = start ?? frame.timestamp
        start = t0
        let t = frame.timestamp - t0
        let pose = frame.camera.transform
        let (tracking, reason) = Self.tracking(frame.camera.trackingState)
        let lux = frame.lightEstimate.map { Double($0.ambientIntensity) }
        let (speed, turn) = coverage.add(pose: pose, t: t, tracking: tracking, lux: lux)
        if let event = coach.update(t: t, speed: speed, turnRate: turn, reason: reason) { pendingCoach = event }

        if tracking == .normal, t - lastBlurCheck >= selector.minInterval, selector.qualifies(pose, at: t),
           let depth = frame.sceneDepth {
            lastBlurCheck = t
            let sharp = writer.sharpness(frame.capturedImage)
            if isBlurry(sharp) {
                dropped += 1
            } else if writer.write(image: frame.capturedImage, depth: depth.depthMap, confidence: depth.confidenceMap,
                                   pose: pose, t: t, tracking: tracking, reason: reason,
                                   cameraIntrinsics: frame.camera.intrinsics,
                                   cameraSize: CGSize(width: frame.camera.imageResolution.width,
                                                      height: frame.camera.imageResolution.height)) {
                selector.accept(pose, at: t)
                keptSharpness.append(sharp)
                if keptSharpness.count > 30 { keptSharpness.removeFirst() }
            }
        }

        if t - lastEmit >= 0.1 || pendingCoach != nil {
            lastEmit = t
            let update = CaptureUpdate(elapsed: t, directionsCovered: coverage.directionsCovered,
                                       keyframes: writer.frameCount, droppedBlurry: dropped, tracking: tracking,
                                       coach: pendingCoach, lightLux: lux ?? 0)
            pendingCoach = nil
            onUpdate?(update)
        }
    }

    /// Blurry when well below the recent sharp frames (adaptive), or below an absolute floor.
    private func isBlurry(_ s: Float) -> Bool {
        if s < 0.0004 { return true }
        guard keptSharpness.count >= 5 else { return false }
        let median = keptSharpness.sorted()[keptSharpness.count / 2]
        return s < median * 0.35
    }

    static func tracking(_ s: ARCamera.TrackingState) -> (TrackingState, TrackingReason?) {
        switch s {
        case .normal: return (.normal, nil)
        case .notAvailable: return (.notAvailable, nil)
        case .limited(let r):
            switch r {
            case .excessiveMotion: return (.limited, .excessiveMotion)
            case .insufficientFeatures: return (.limited, .insufficientFeatures)
            case .initializing: return (.limited, .initializing)
            case .relocalizing: return (.limited, .relocalizing)
            @unknown default: return (.limited, nil)
            }
        }
    }
}

public enum CaptureError: Error, LocalizedError {
    case noFrames, noWorldMap
    public var errorDescription: String? {
        switch self {
        case .noFrames: return "No sharp frames were captured. Scan again, slowly, with the lights on."
        case .noWorldMap: return "The room map could not be saved."
        }
    }
}

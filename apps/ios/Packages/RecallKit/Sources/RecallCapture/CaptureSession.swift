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
    /// A cue to say (or `.clear` when the problem went away); nil when nothing changed.
    public var signal: ScanSignals.Event?
    public var lightLux: Double
    /// Which of the 12 directions (30° each) have been seen, for the dial.
    public var sectors: Set<Int>
    public var mapStatus: MapStatus
    public var step: ScanGuide.Step
    /// A voice step to say (a new step, or the room map becoming ready); nil when nothing changed.
    public var guideLine: String?
    public var mapReady: Bool
    /// Floor and walls the LiDAR saw, and the walked path, for the mini-map.
    public var surfaces: SurfaceCoverage
    /// Walking speed, m/s (the readout turns amber when it's too fast for sharp photos).
    public var speed: Double = 0
    /// Distance to whatever is straight ahead, metres (nil: nothing in range).
    public var centreDistance: Double?
    /// LiDAR points sampled so far, and the newest ones (ARKit world) to paint on the camera; empty between samples.
    public var pointsCaptured = 0
    public var newPoints: [SIMD3<Float>] = []

    public init(elapsed: Double, directionsCovered: Int, keyframes: Int, droppedBlurry: Int, tracking: TrackingState,
                signal: ScanSignals.Event? = nil, lightLux: Double, sectors: Set<Int> = [],
                mapStatus: MapStatus = .notAvailable, step: ScanGuide.Step = .start, guideLine: String? = nil,
                mapReady: Bool = false, surfaces: SurfaceCoverage = .init()) {
        self.elapsed = elapsed; self.directionsCovered = directionsCovered; self.keyframes = keyframes
        self.droppedBlurry = droppedBlurry; self.tracking = tracking; self.signal = signal; self.lightLux = lightLux
        self.sectors = sectors; self.mapStatus = mapStatus; self.step = step; self.guideLine = guideLine
        self.mapReady = mapReady; self.surfaces = surfaces
    }

    public var wallsCovered: Int { surfaces.wallsCovered }
    public var floorSeenM2: Double { surfaces.floorSeenM2 }
}

/// Plain ARKit world tracking on our own ARSession with LiDAR scene depth. No scene reconstruction and no plane
/// detection or classification (those are Apple models; CLAUDE.md rule 8). Depth is only sampled (a 16 × 12 grid)
/// to measure what the scan saw; the room itself is built on the Mac.
public final class CaptureSession: NSObject, ARSessionDelegate, @unchecked Sendable {
    public let session = ARSession()
    private let queue = DispatchQueue(label: "recall.capture", qos: .userInitiated)

    // capture-queue state
    private var writer: EpisodeWriter?
    private var heading: (@Sendable () -> HeadingReading?)?
    private var selector = KeyframeSelector()
    private var coverage = CoverageTracker()
    private var surfaces = SurfaceCoverage()
    private var signals = ScanSignals()
    private var guide = ScanGuide()
    private var calibration = CompassCalibration()
    private var mapStatus = MapStatus.notAvailable
    private var start: TimeInterval?
    private var startedAt = Date()
    private var lastEmit: Double = -1
    private var lastBlurCheck: Double = -1
    private var lastDepthSample: Double = -1
    private var lastPosition: simd_float3?
    private var centreDepth: Double?
    private var pointsCaptured = 0
    private var freshPoints: [SIMD3<Float>] = []
    private var highConfidence: Double?
    private var keptSharpness: [Float] = []
    private var dropped = 0
    private var pendingSignal: ScanSignals.Event?
    private var pendingLine: String?
    // a rescan: recognise the earlier scan's room before keeping any view, or start fresh after a while
    private var alignTo: String?
    private var recognising = false
    private var recogniseStarted: TimeInterval?
    private var alignedTo: String?
    static let recogniseTimeout: Double = 25

    public var onUpdate: (@Sendable (CaptureUpdate) -> Void)?

    public static var isSupported: Bool {
        ARWorldTrackingConfiguration.isSupported && ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
    }

    /// `heading` reads the compass (any thread); without it the scan has no compass. `rescan`: the earlier scan's id
    /// and room map; the session starts in that map and keeps no view until ARKit has recognised the room, so this
    /// scan's poses share the earlier scan's frame (or, after 25 s without a match, it starts fresh).
    public func start(writer: EpisodeWriter, heading: (@Sendable () -> HeadingReading?)? = nil,
                      rescan: (scanId: String, roomMap: Data)? = nil) {
        let map = rescan.flatMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: $0.roomMap) }
        queue.sync {
            self.writer = writer
            self.heading = heading
            startedAt = Date(); dropped = 0; keptSharpness = []; pointsCaptured = 0; freshPoints = []
            alignTo = map == nil ? nil : rescan?.scanId
            recognising = alignTo != nil
            recogniseStarted = nil; alignedTo = nil
            resetMeasures()
            guide = ScanGuide(recognising: recognising)
            pendingLine = recognising ? ScanGuide.Step.recognise.spoken : ScanGuide.Step.start.spoken
        }
        session.delegateQueue = queue
        session.delegate = self
        session.run(Self.configuration(map), options: [.resetTracking, .removeExistingAnchors])
    }

    private static func configuration(_ map: ARWorldMap?) -> ARWorldTrackingConfiguration {
        let config = ARWorldTrackingConfiguration()
        config.frameSemantics = [.sceneDepth]
        config.planeDetection = []
        config.environmentTexturing = .none
        config.isLightEstimationEnabled = true
        config.initialWorldMap = map
        return config
    }

    /// Everything measured about the walk so far (cleared again when a rescan starts fresh).
    private func resetMeasures() {
        selector = KeyframeSelector(); coverage = CoverageTracker(); surfaces = SurfaceCoverage()
        signals = ScanSignals(); calibration = CompassCalibration(); mapStatus = .notAvailable
        start = nil; lastEmit = -1; lastBlurCheck = -1; lastDepthSample = -1
        lastPosition = nil; centreDepth = nil; highConfidence = nil; pendingSignal = nil
    }

    /// Stops, saves the world map and writes the manifest last. Throws when too few frames were kept.
    public func finish(device: String, appVersion: String) async throws -> Manifest {
        let mapData = try? await currentWorldMapData()
        session.pause()
        return try queue.sync {
            guard let writer, writer.frameCount > 0 else { throw CaptureError.noFrames }
            let compass = calibration.summary
            let metrics = CaptureMetrics(
                directionsCovered: coverage.directionsCovered, keyframesKept: writer.frameCount,
                keyframesDroppedBlurry: dropped, trackingNormalRatio: coverage.trackingNormalRatio,
                meanSpeedMps: coverage.meanSpeed, peakSpeedMps: coverage.peakSpeed, slowDownCues: signals.cues,
                areaWalkedM2: coverage.areaWalked, meanLightLux: coverage.meanLight,
                wallsCovered: surfaces.wallsCovered, floorSeenM2: (surfaces.floorSeenM2 * 100).rounded() / 100,
                mapStatus: mapStatus, loopClosed: guide.loopClosed, compassSpreadDeg: compass?.spreadDeg)
            let duration = Date().timeIntervalSince(startedAt)
            self.writer = nil
            return try writer.finish(worldMap: mapData, metrics: metrics, compass: compass, alignedTo: alignedTo,
                                     duration: duration, device: device, appVersion: appVersion, createdAt: startedAt)
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
        if recognising {
            recognise(frame)
            return
        }
        let t0 = start ?? frame.timestamp
        start = t0
        let t = frame.timestamp - t0
        let pose = frame.camera.transform
        let position = pose.columns.3.xyz
        let pitch = Double(pose.pitchDegrees)
        let (tracking, reason) = Self.tracking(frame.camera.trackingState)
        let lux = frame.lightEstimate.map { Double($0.ambientIntensity) }
        let (speed, turn) = coverage.add(pose: pose, t: t, tracking: tracking, lux: lux)
        mapStatus = Self.mapStatus(frame.worldMappingStatus)
        let jump = lastPosition.map { Double(simd_distance($0, position)) } ?? 0
        lastPosition = position

        let compass = heading?()
        if tracking == .normal, let compass {
            calibration.add(compass, cameraYaw: Double(pose.headingDegrees), pitch: pitch)
        }

        // what the LiDAR sees, twice a second: distance to surfaces, confidence, and floor and wall coverage
        if tracking == .normal, t - lastDepthSample >= 0.5, let depth = frame.sceneDepth {
            lastDepthSample = t
            let s = Self.sample(depth: depth.depthMap, confidence: depth.confidenceMap, intrinsics: frame.camera.intrinsics,
                                imageSize: frame.camera.imageResolution, pose: pose)
            centreDepth = s.centre
            highConfidence = s.high
            surfaces.add(samples: s.points, camera: position)
            pointsCaptured += s.points.count
            freshPoints = s.points
        }

        if tracking == .normal, t - lastBlurCheck >= selector.minInterval, selector.qualifies(pose, at: t),
           let depth = frame.sceneDepth {
            lastBlurCheck = t
            let sharp = writer.sharpness(frame.capturedImage)
            if isBlurry(sharp) {
                dropped += 1
            } else if writer.write(image: frame.capturedImage, depth: depth.depthMap, confidence: depth.confidenceMap,
                                   pose: pose, t: t, tracking: tracking, reason: reason,
                                   heading: compass.map { .init(magneticDeg: $0.magneticDeg, accuracyDeg: $0.accuracyDeg) },
                                   cameraIntrinsics: frame.camera.intrinsics,
                                   cameraSize: CGSize(width: frame.camera.imageResolution.width,
                                                      height: frame.camera.imageResolution.height)) {
                selector.accept(pose, at: t)
                keptSharpness.append(sharp)
                if keptSharpness.count > 30 { keptSharpness.removeFirst() }
            }
        }

        let input = ScanSignals.Input(t: t, speed: speed, turnRate: turn, reason: reason, jump: jump, pitch: pitch,
                                      centreDepth: centreDepth, highConfidence: highConfidence, lux: lux,
                                      sinceKeyframe: selector.since(t), floorSeen: surfaces.floorSeenM2 > 0)
        if let event = signals.update(input) { pendingSignal = event }
        let progress = ScanGuide.Progress(elapsed: t, directions: coverage.directionsCovered,
                                          walls: surfaces.wallsCovered, floorSeenM2: surfaces.floorSeenM2,
                                          areaWalkedM2: coverage.areaWalked, walkedM: surfaces.walkedM,
                                          fromStartM: surfaces.fromStartM, map: mapStatus)
        if let line = guide.update(progress) { pendingLine = line }

        if t - lastEmit >= 0.1 || pendingSignal != nil || pendingLine != nil {
            lastEmit = t
            let update = CaptureUpdate(elapsed: t, directionsCovered: coverage.directionsCovered,
                                       keyframes: writer.frameCount, droppedBlurry: dropped, tracking: tracking,
                                       signal: pendingSignal, lightLux: lux ?? 0, sectors: coverage.sectors,
                                       mapStatus: mapStatus, step: guide.step, guideLine: pendingLine,
                                       mapReady: guide.mapReady, surfaces: surfaces)
            var live = update
            live.speed = speed
            live.centreDistance = centreDepth
            live.pointsCaptured = pointsCaptured
            live.newPoints = freshPoints
            freshPoints = []
            pendingSignal = nil
            pendingLine = nil
            onUpdate?(live)
        }
    }

    /// A rescan's first seconds: wait for ARKit to recognise the earlier scan's room (tracking turns normal in that
    /// map), keeping nothing; then measure from there. No match in time: start over without the map.
    private func recognise(_ frame: ARFrame) {
        let t0 = recogniseStarted ?? frame.timestamp
        recogniseStarted = t0
        let t = frame.timestamp - t0
        let (tracking, _) = Self.tracking(frame.camera.trackingState)
        let recognised = tracking == .normal
        guard recognised || t > Self.recogniseTimeout else {
            if t - lastEmit >= 0.25 || pendingLine != nil {
                lastEmit = t
                onUpdate?(CaptureUpdate(elapsed: t, directionsCovered: 0, keyframes: 0, droppedBlurry: 0, tracking: tracking,
                                        lightLux: 0, step: .recognise, guideLine: pendingLine))
                pendingLine = nil
            }
            return
        }
        recognising = false
        alignedTo = recognised ? alignTo : nil
        resetMeasures()
        lastEmit = -1
        pendingLine = guide.endRecognise(recognised: recognised, at: 0)
        if !recognised {
            session.run(Self.configuration(nil), options: [.resetTracking, .removeExistingAnchors])  // a fresh scan
        }
    }

    /// Blurry when well below the recent sharp frames (adaptive), or below an absolute floor.
    private func isBlurry(_ s: Float) -> Bool {
        if s < 0.0004 { return true }
        guard keptSharpness.count >= 5 else { return false }
        let median = keptSharpness.sorted()[keptSharpness.count / 2]
        return s < median * 0.35
    }

    /// Reads the LiDAR depth on a 16 × 12 grid: world points where confidence is high, the distance straight ahead
    /// (median of the middle samples) and the share of high-confidence samples.
    static func sample(depth: CVPixelBuffer, confidence: CVPixelBuffer?, intrinsics: simd_float3x3, imageSize: CGSize,
                       pose: simd_float4x4) -> (points: [SIMD3<Float>], centre: Double?, high: Double?) {
        CVPixelBufferLockBaseAddress(depth, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depth, .readOnly) }
        if let confidence { CVPixelBufferLockBaseAddress(confidence, .readOnly) }
        defer { if let confidence { CVPixelBufferUnlockBaseAddress(confidence, .readOnly) } }
        guard CVPixelBufferGetPixelFormatType(depth) == kCVPixelFormatType_DepthFloat32,
              let base = CVPixelBufferGetBaseAddress(depth) else { return ([], nil, nil) }
        let w = CVPixelBufferGetWidth(depth), h = CVPixelBufferGetHeight(depth)
        let row = CVPixelBufferGetBytesPerRow(depth)
        let cBase = confidence.flatMap { CVPixelBufferGetBaseAddress($0) }
        let cRow = confidence.map { CVPixelBufferGetBytesPerRow($0) } ?? 0

        // ARKit's intrinsics are for the full camera image; the depth map is smaller
        let s = Float(w) / Float(imageSize.width)
        let fx = intrinsics.columns.0.x * s, fy = intrinsics.columns.1.y * s
        let cx = intrinsics.columns.2.x * s, cy = intrinsics.columns.2.y * s

        var points: [SIMD3<Float>] = []
        var middle: [Float] = []
        var high = 0, total = 0
        for j in 0..<12 {
            for i in 0..<16 {
                let u = Int((Float(i) + 0.5) * Float(w) / 16), v = Int((Float(j) + 0.5) * Float(h) / 12)
                let d = base.load(fromByteOffset: v * row + u * MemoryLayout<Float32>.size, as: Float32.self)
                guard d.isFinite, d > 0.1, d < 6 else { continue }
                total += 1
                if (6...9).contains(i), (4...7).contains(j) { middle.append(d) }
                let c = cBase.map { $0.load(fromByteOffset: v * cRow + u, as: UInt8.self) } ?? 2
                guard c >= 2 else { continue }  // ARConfidenceLevel.high
                high += 1
                // camera space (ARKit: +x right, +y up, looking along −z; image v grows downwards)
                let p = SIMD4((Float(u) - cx) / fx * d, -(Float(v) - cy) / fy * d, -d, 1)
                points.append((pose * p).xyz)
            }
        }
        let centre = middle.isEmpty ? nil : Double(middle.sorted()[middle.count / 2])
        return (points, centre, total == 0 ? nil : Double(high) / Double(total))
    }

    static func mapStatus(_ s: ARFrame.WorldMappingStatus) -> MapStatus {
        switch s {
        case .notAvailable: .notAvailable
        case .limited: .limited
        case .extending: .extending
        case .mapped: .mapped
        @unknown default: .limited
        }
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

import Foundation

/// One line of poses.jsonl (services/api/resources/schemas/PoseRecord.yaml).
public struct PoseRecord: Codable, Sendable, Equatable {
    public var index: Int
    public var t: Double
    /// ARKit camera-to-world, column-major (simd_float4x4 columns one after another).
    public var pose: [Float]
    public var tracking: TrackingState
    public var reason: TrackingReason?

    public init(index: Int, t: Double, pose: [Float], tracking: TrackingState, reason: TrackingReason?) {
        self.index = index; self.t = t; self.pose = pose; self.tracking = tracking; self.reason = reason
    }
}

public enum TrackingState: String, Codable, Sendable { case normal, limited, notAvailable = "not_available" }

public enum TrackingReason: String, Codable, Sendable {
    case excessiveMotion = "excessive_motion"
    case insufficientFeatures = "insufficient_features"
    case initializing, relocalizing
}

/// manifest.json (services/api/resources/schemas/Manifest.yaml). Written on the phone, uploaded last.
public struct Manifest: Codable, Sendable {
    public struct Size: Codable, Sendable {
        public var width: Int; public var height: Int
        public init(width: Int, height: Int) { self.width = width; self.height = height }
    }
    public struct Depth: Codable, Sendable {
        public var width: Int; public var height: Int; public var unit = "mm"; public var encoding = "png16"
        public init(width: Int, height: Int) { self.width = width; self.height = height }
    }
    public struct Intrinsics: Codable, Sendable {
        public var fx, fy, cx, cy: Double
        public init(fx: Double, fy: Double, cx: Double, cy: Double) { self.fx = fx; self.fy = fy; self.cx = cx; self.cy = cy }
    }
    public struct FileEntry: Codable, Sendable, Equatable {
        public var path: String; public var size: Int; public var sha256: String
        public init(path: String, size: Int, sha256: String) { self.path = path; self.size = size; self.sha256 = sha256 }
    }

    public var scanId: String
    public var format = "recall-episode/1"
    public var device: String
    public var appVersion: String
    public var createdAt: Date
    public var durationS: Double
    public var frameCount: Int
    public var image: Size
    public var depth: Depth
    public var intrinsics: Intrinsics
    public var worldMap: String?
    public var files: [FileEntry]
    public var captureMetrics: CaptureMetrics

    enum CodingKeys: String, CodingKey {
        case scanId = "scan_id", format, device, appVersion = "app_version", createdAt = "created_at"
        case durationS = "duration_s", frameCount = "frame_count", image, depth, intrinsics
        case worldMap = "world_map", files, captureMetrics = "capture_metrics"
    }

    public init(scanId: String, device: String, appVersion: String, createdAt: Date, durationS: Double, frameCount: Int,
                image: Size, depth: Depth, intrinsics: Intrinsics, worldMap: String?, files: [FileEntry],
                captureMetrics: CaptureMetrics) {
        self.scanId = scanId; self.device = device; self.appVersion = appVersion; self.createdAt = createdAt
        self.durationS = durationS; self.frameCount = frameCount; self.image = image; self.depth = depth
        self.intrinsics = intrinsics; self.worldMap = worldMap; self.files = files; self.captureMetrics = captureMetrics
    }

    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }
}

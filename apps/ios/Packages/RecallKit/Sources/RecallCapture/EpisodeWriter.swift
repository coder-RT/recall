import CoreVideo
import Foundation
import RecallDomain
import simd

/// Writes one episode folder: frames/, depth/, confidence/, poses.jsonl, worldmap.arworldmap, manifest.json (last).
/// Confined to the capture queue.
public final class EpisodeWriter: @unchecked Sendable {
    public let scanId: String
    public let directory: URL
    private let encoder = FrameEncoder()
    private var files: [Manifest.FileEntry] = []
    private var poses: FileHandle?
    private var posesData = Data()
    private(set) var frameCount = 0
    private(set) var imageSize = CGSize.zero
    private(set) var depthSize = CGSize.zero
    private(set) var intrinsics: Manifest.Intrinsics?

    public init(scanId: String, directory: URL) throws {
        self.scanId = scanId
        self.directory = directory
        for sub in ["frames", "depth", "confidence"] {
            try FileManager.default.createDirectory(at: directory.appending(path: sub), withIntermediateDirectories: true)
        }
    }

    func sharpness(_ image: CVPixelBuffer) -> Float { encoder.sharpness(image) }

    /// Writes the keyframe. Returns false when an image could not be encoded (the frame is then skipped).
    func write(image: CVPixelBuffer, depth: CVPixelBuffer, confidence: CVPixelBuffer?, pose: simd_float4x4, t: Double,
               tracking: TrackingState, reason: TrackingReason?, cameraIntrinsics: simd_float3x3, cameraSize: CGSize) -> Bool {
        let name = String(format: "%06d", frameCount)
        guard let (jpeg, size) = encoder.jpeg(image), let (depthPNG, dsize) = encoder.depthPNG(depth) else { return false }
        save(jpeg, "frames/\(name).jpg")
        save(depthPNG, "depth/\(name).png")
        if let confidence, let c = encoder.confidencePNG(confidence) { save(c, "confidence/\(name).png") }
        if intrinsics == nil {
            // ARKit reports intrinsics for the full camera image; scale them to the saved frame
            let s = Double(size.width / cameraSize.width)
            let k = cameraIntrinsics
            let fx = Double(k.columns.0.x) * s
            let fy = Double(k.columns.1.y) * s
            let cx = Double(k.columns.2.x) * s
            let cy = Double(k.columns.2.y) * s
            intrinsics = Manifest.Intrinsics(fx: fx, fy: fy, cx: cx, cy: cy)
            imageSize = size
            depthSize = dsize
        }
        let record = PoseRecord(index: frameCount, t: t, pose: pose.columnMajor, tracking: tracking, reason: reason)
        if var line = try? JSONEncoder().encode(record) {
            line.append(0x0A)
            posesData.append(line)
        }
        frameCount += 1
        return true
    }

    /// Writes poses.jsonl, the world map and, last, manifest.json. Returns the manifest.
    func finish(worldMap: Data?, metrics: CaptureMetrics, duration: Double, device: String, appVersion: String,
                createdAt: Date) throws -> Manifest {
        save(posesData, "poses.jsonl")
        var mapPath: String?
        if let worldMap { save(worldMap, "worldmap.arworldmap"); mapPath = "worldmap.arworldmap" }
        let manifest = Manifest(
            scanId: scanId, device: device, appVersion: appVersion, createdAt: createdAt, durationS: duration,
            frameCount: frameCount, image: .init(width: Int(imageSize.width), height: Int(imageSize.height)),
            depth: .init(width: Int(depthSize.width), height: Int(depthSize.height)),
            intrinsics: intrinsics ?? .init(fx: 0, fy: 0, cx: 0, cy: 0), worldMap: mapPath, files: files,
            captureMetrics: metrics)
        try Manifest.encoder().encode(manifest).write(to: directory.appending(path: "manifest.json"), options: .atomic)
        return manifest
    }

    private func save(_ data: Data, _ path: String) {
        try? data.write(to: directory.appending(path: path), options: .atomic)
        files.append(.init(path: path, size: data.count, sha256: Hash.sha256(data)))
    }
}

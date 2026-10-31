import ARKit
import CoreVideo
import Foundation
import RecallDomain
import SceneKit
import Testing
@testable import RecallCapture

/// A pixel buffer filled by `value(x, y)`.
private func buffer<T>(_ w: Int, _ h: Int, _ format: OSType, _ value: (Int, Int) -> T) -> CVPixelBuffer {
    var pb: CVPixelBuffer?
    CVPixelBufferCreate(nil, w, h, format, nil, &pb)
    let b = pb!
    CVPixelBufferLockBaseAddress(b, [])
    let base = CVPixelBufferGetBaseAddress(b)!, row = CVPixelBufferGetBytesPerRow(b)
    for y in 0..<h {
        for x in 0..<w { base.advanced(by: y * row + x * MemoryLayout<T>.size).storeBytes(of: value(x, y), as: T.self) }
    }
    CVPixelBufferUnlockBaseAddress(b, [])
    return b
}

private func depth(_ w: Int = 32, _ h: Int = 24, _ v: @escaping (Int, Int) -> Float32) -> CVPixelBuffer {
    buffer(w, h, kCVPixelFormatType_DepthFloat32, v)
}

private func confidence(_ w: Int = 32, _ h: Int = 24, _ v: @escaping (Int, Int) -> UInt8) -> CVPixelBuffer {
    buffer(w, h, kCVPixelFormatType_OneComponent8, v)
}

/// Intrinsics for a 64 × 48 camera image (the depth map is half that): f = 50, centre (32, 24).
private let K = simd_float3x3(SIMD3(50, 0, 0), SIMD3(0, 50, 0), SIMD3(32, 24, 1))
private let imageSize = CGSize(width: 64, height: 48)

@Suite("LiDAR sampling")
struct DepthSamplingTests {
    @Test func backProjectsAGridIntoTheWorld() throws {
        let s = CaptureSession.sample(depth: depth { _, _ in 2 }, confidence: confidence { _, _ in 2 }, intrinsics: K,
                                      imageSize: imageSize, pose: matrix_identity_float4x4)
        #expect(s.points.count == 16 * 12)
        #expect(s.centre == 2)
        #expect(s.high == 1)
        // the first sample: depth pixel (1, 1); scaled intrinsics f = 25, centre (16, 12); ARKit camera looks along −z
        let p = try #require(s.points.first)
        #expect(abs(p.x - (1 - 16) / 25 * 2) < 1e-5)
        #expect(abs(p.y - -(1 - 12) / 25 * 2) < 1e-5)
        #expect(p.z == -2)
        #expect(s.points.allSatisfy { $0.z == -2 })  // a flat wall 2 m ahead
    }

    @Test func thePoseMovesThePointsIntoTheWorld() {
        var pose = matrix_identity_float4x4
        pose.columns.3 = SIMD4(1, 1.4, 0, 1)
        let s = CaptureSession.sample(depth: depth { _, _ in 2 }, confidence: nil, intrinsics: K, imageSize: imageSize,
                                      pose: pose)
        #expect(s.points.allSatisfy { abs($0.z + 2) < 1e-5 })
        let xs = s.points.map(\.x)
        #expect(abs((xs.min()! + xs.max()!) / 2 - 1) < 0.1)  // centred on the camera's x
    }

    @Test func lowConfidenceAndMissingDepthAreLeftOut() {
        // left half low confidence; a band of no depth across the top
        let s = CaptureSession.sample(depth: depth { _, y in y < 6 ? .nan : 3 },
                                      confidence: confidence { x, _ in x < 16 ? 0 : 2 },
                                      intrinsics: K, imageSize: imageSize, pose: matrix_identity_float4x4)
        #expect(s.points.count == 8 * 9)  // right half × rows below the band
        #expect(s.high == 0.5)
        #expect(s.centre == 3)
    }

    @Test func tooCloseOrFarIsIgnoredAndAWrongFormatGivesNothing() {
        let near = CaptureSession.sample(depth: depth { _, _ in 0.05 }, confidence: nil, intrinsics: K,
                                         imageSize: imageSize, pose: matrix_identity_float4x4)
        #expect(near.points.isEmpty && near.centre == nil && near.high == nil)
        let wrong = CaptureSession.sample(depth: confidence { _, _ in 2 }, confidence: nil, intrinsics: K,
                                          imageSize: imageSize, pose: matrix_identity_float4x4)
        #expect(wrong.points.isEmpty)
    }

    @Test func arkitStatesMapToOurs() {
        #expect(CaptureSession.mapStatus(.mapped) == .mapped)
        #expect(CaptureSession.mapStatus(.extending) == .extending)
        #expect(CaptureSession.mapStatus(.limited) == .limited)
        #expect(CaptureSession.mapStatus(.notAvailable) == .notAvailable)
        #expect(CaptureSession.tracking(.normal) == (.normal, nil))
        #expect(CaptureSession.tracking(.limited(.excessiveMotion)) == (.limited, .excessiveMotion))
        #expect(CaptureSession.tracking(.limited(.relocalizing)) == (.limited, .relocalizing))
        #expect(CaptureSession.tracking(.notAvailable) == (.notAvailable, nil))
    }
}

@Suite("Episode writer")
struct EpisodeWriterTests {
    @Test func posesCarryTheCompassAndTheManifestItsNorth() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "recall-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let writer = try EpisodeWriter(scanId: "s1", directory: dir)
        let image = buffer(64, 48, kCVPixelFormatType_32BGRA) { x, _ in UInt32(x * 4) }
        let heading = PoseRecord.Heading(magneticDeg: 42.5, accuracyDeg: 8)
        #expect(writer.write(image: image, depth: depth { _, _ in 1.5 }, confidence: confidence { _, _ in 2 },
                             pose: matrix_identity_float4x4, t: 0.5, tracking: .normal, reason: nil, heading: heading,
                             cameraIntrinsics: K, cameraSize: imageSize))
        #expect(writer.write(image: image, depth: depth { _, _ in 1.5 }, confidence: nil, pose: matrix_identity_float4x4,
                             t: 1.0, tracking: .limited, reason: .excessiveMotion, cameraIntrinsics: K, cameraSize: imageSize))
        let metrics = CaptureMetrics(directionsCovered: 10, keyframesKept: 2, keyframesDroppedBlurry: 0,
                                     trackingNormalRatio: 0.95, meanSpeedMps: 0.3, peakSpeedMps: 0.6, slowDownCues: 0,
                                     areaWalkedM2: 4, meanLightLux: 300, wallsCovered: 10, floorSeenM2: 3.5,
                                     mapStatus: .mapped, loopClosed: true, compassSpreadDeg: 6)
        let compass = Manifest.Compass(northYawDeg: 90, spreadDeg: 6, samples: 40)
        let manifest = try writer.finish(worldMap: nil, metrics: metrics, compass: compass, duration: 60,
                                         device: "iPhone17,1", appVersion: "1", createdAt: Date(timeIntervalSince1970: 0))

        let lines = try String(contentsOf: dir.appending(path: "poses.jsonl"), encoding: .utf8).split(separator: "\n")
        #expect(lines.count == 2)
        let first = try JSONDecoder().decode(PoseRecord.self, from: Data(lines[0].utf8))
        #expect(first.heading == heading)
        #expect(lines[0].contains("\"magnetic_deg\":42.5"))  // snake_case on the wire, as PoseRecord.yaml says
        #expect(try JSONDecoder().decode(PoseRecord.self, from: Data(lines[1].utf8)).heading == nil)

        let saved = try String(contentsOf: dir.appending(path: "manifest.json"), encoding: .utf8)
        #expect(saved.contains("\"north_yaw_deg\":90"))
        #expect(saved.contains("\"walls_covered\":10") && saved.contains("\"map_status\":\"mapped\""))
        #expect(manifest.compass == compass && manifest.frameCount == 2)
        #expect(manifest.captureMetrics.grade == .good)
        // the intrinsics are scaled to the saved frame (64 px wide stays 64 here: the long edge is below 1024)
        #expect(manifest.files.contains { $0.path == "frames/000000.jpg" } && manifest.files.contains { $0.path == "depth/000001.png" })
    }
}

@Suite("Arrows in the camera view") @MainActor
struct ARLocatorTests {
    private func named(_ locator: ARLocator, _ name: String) -> [SCNNode] {
        locator.scene.rootNode.childNodes { node, _ in node.name == name }
    }

    @Test func theArrowMarksTheThingAndGoes() throws {
        let locator = ARLocator()
        locator.mark([2, 0.8, -2])
        let arrow = try #require(named(locator, "recall.arrow").first)
        #expect(abs(arrow.simdPosition.y - 0.88) < 1e-5)  // just above the thing
        #expect(arrow.constraints?.first is SCNBillboardConstraint)
        locator.mark([1, 0.5, 0])
        #expect(named(locator, "recall.arrow").count == 1)  // moved, never doubled
        locator.mark(nil)
        #expect(named(locator, "recall.arrow").isEmpty)
    }

    @Test func floorChevronsFollowTheRouteAndClear() {
        let locator = ARLocator()
        let route: [SIMD2<Double>] = [[0, 0], [0, -3]]
        locator.showPath(route, floorY: -1.4)
        let chevrons = named(locator, "recall.chevron")
        #expect(chevrons.count == ChevronLayout.place(path: route).count)
        #expect(chevrons.allSatisfy { abs($0.simdPosition.y - -1.39) < 1e-5 })  // 1 cm above the floor
        #expect(chevrons.allSatisfy { $0.childNodes.count == 2 })  // the glow and the light core
        locator.showPath([[0, 0], [2, 0]], floorY: -1.4)
        let turned = named(locator, "recall.chevron")
        #expect(turned.allSatisfy { abs($0.eulerAngles.y + .pi / 2) < 1e-5 })  // towards +x: a quarter turn clockwise
        locator.showPath([], floorY: nil)
        #expect(named(locator, "recall.chevron").isEmpty)
    }

    @Test func anUnreadableRoomMapIsRefusedWithoutStartingARKit() {
        let locator = ARLocator()
        #expect(!locator.start(roomMap: Data("not a map".utf8)))
        #expect(!locator.isRunning)
    }
}

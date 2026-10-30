import Foundation
import simd
import Testing
@testable import RecallDomain

private func pose(x: Float = 0, z: Float = 0, yawDegrees: Float = 0) -> simd_float4x4 {
    let a = yawDegrees * .pi / 180
    var m = simd_float4x4(simd_quatf(angle: a, axis: [0, 1, 0]))
    m.columns.3 = [x, 1.4, z, 1]
    return m
}

@Suite("Keyframes") struct KeyframeTests {
    @Test func firstFrameIsAlwaysKept() {
        #expect(KeyframeSelector().qualifies(pose(), at: 0))
    }

    @Test func keepsAfterFifteenCentimetresOrTenDegrees() {
        var k = KeyframeSelector()
        k.accept(pose(), at: 0)
        #expect(!k.qualifies(pose(x: 0.10), at: 1))
        #expect(k.qualifies(pose(x: 0.16), at: 1))
        #expect(!k.qualifies(pose(yawDegrees: 8), at: 1))
        #expect(k.qualifies(pose(yawDegrees: 11), at: 1))
    }

    @Test func notTwiceWithinTheMinimumInterval() {
        var k = KeyframeSelector()
        k.accept(pose(), at: 0)
        #expect(!k.qualifies(pose(x: 1), at: 0.1))
    }
}

@Suite("Grade") struct GradeTests {
    @Test func goodNeedsTenDirectionsSteadyTrackingAndFewBlurryFrames() {
        #expect(ScanGrade.grade(directions: 11, trackingNormal: 0.95, blurryShare: 0.05) == .good)
        #expect(ScanGrade.grade(directions: 9, trackingNormal: 0.95, blurryShare: 0.05) == .usable)
        #expect(ScanGrade.grade(directions: 11, trackingNormal: 0.95, blurryShare: 0.2) == .usable)
    }

    @Test func redoWhenTooFewDirectionsOrTrackingWasLost() {
        #expect(ScanGrade.grade(directions: 5, trackingNormal: 1, blurryShare: 0) == .redo)
        #expect(ScanGrade.grade(directions: 12, trackingNormal: 0.6, blurryShare: 0) == .redo)
    }

    @Test func metricsCarryTheirGradeAndAReason() {
        let m = CaptureMetrics(directionsCovered: 4, keyframesKept: 40, keyframesDroppedBlurry: 2, trackingNormalRatio: 0.98,
                               meanSpeedMps: 0.3, peakSpeedMps: 0.6, slowDownCues: 1, areaWalkedM2: 6, meanLightLux: 400)
        #expect(m.grade == .redo)
        #expect(ScanGrade.reason(for: m).contains("4 of 12"))
    }
}

@Suite("Speed coach") struct SpeedCoachTests {
    @Test func walkingFastForHalfASecondTriggersOneCue() {
        var c = SpeedCoach()
        #expect(c.update(t: 0.0, speed: 0.8, turnRate: 0, reason: nil) == nil)
        #expect(c.update(t: 0.3, speed: 0.8, turnRate: 0, reason: nil) == nil)
        #expect(c.update(t: 0.6, speed: 0.8, turnRate: 0, reason: nil) == .slowDown(.walkingFast))
        #expect(c.update(t: 1.0, speed: 0.8, turnRate: 0, reason: nil) == nil)  // no nagging
        #expect(c.cues == 1)
    }

    @Test func trackingTroubleIsImmediate() {
        var c = SpeedCoach()
        #expect(c.update(t: 0, speed: 0, turnRate: 0, reason: .excessiveMotion) == .slowDown(.trackingExcessiveMotion))
    }

    @Test func clearsOnlyAfterOneCalmSecond() {
        var c = SpeedCoach()
        _ = c.update(t: 0, speed: 0, turnRate: 0, reason: .excessiveMotion)
        #expect(c.update(t: 0.5, speed: 0.1, turnRate: 0, reason: nil) == nil)
        #expect(c.update(t: 1.2, speed: 0.1, turnRate: 0, reason: nil) == nil)
        #expect(c.update(t: 1.6, speed: 0.1, turnRate: 0, reason: nil) == .clear)
        #expect(!c.active)
    }
}

@Suite("Coverage") struct CoverageTests {
    @Test func turningAroundCoversAllTwelveDirections() {
        var cov = CoverageTracker()
        for i in 0..<36 { cov.add(pose: pose(yawDegrees: Float(i * 10)), t: Double(i) * 0.1, tracking: .normal, lux: 300) }
        #expect(cov.directionsCovered == 12)
        #expect(cov.trackingNormalRatio == 1)
    }

    @Test func speedAndAreaComeFromThePath() {
        var cov = CoverageTracker()
        let square: [(Float, Float)] = [(0, 0), (2, 0), (2, 2), (0, 2)]
        for (i, p) in square.enumerated() { cov.add(pose: pose(x: p.0, z: p.1), t: Double(i), tracking: .normal, lux: nil) }
        #expect(abs(cov.areaWalked - 4) < 0.01)
        #expect(abs(cov.peakSpeed - 2) < 0.01)
    }
}

@Suite("Episode files") struct EpisodeTests {
    @Test func manifestUsesTheSpecsSnakeCaseKeys() throws {
        let m = Manifest(scanId: "x", device: "iPhone17,1", appVersion: "0.1.0", createdAt: Date(timeIntervalSince1970: 0),
                         durationS: 30, frameCount: 1, image: .init(width: 1024, height: 768),
                         depth: .init(width: 256, height: 192), intrinsics: .init(fx: 1, fy: 1, cx: 1, cy: 1),
                         worldMap: nil, files: [],
                         captureMetrics: CaptureMetrics(directionsCovered: 12, keyframesKept: 1, keyframesDroppedBlurry: 0,
                                                        trackingNormalRatio: 1, meanSpeedMps: 0, peakSpeedMps: 0,
                                                        slowDownCues: 0, areaWalkedM2: 0, meanLightLux: 0))
        let json = String(decoding: try Manifest.encoder().encode(m), as: UTF8.self)
        for key in ["\"scan_id\"", "\"frame_count\"", "\"capture_metrics\"", "\"directions_covered\"", "\"recall-episode/1\""] {
            #expect(json.contains(key))
        }
    }

    @Test func posesAreWrittenColumnMajor() {
        var m = matrix_identity_float4x4
        m.columns.3 = [1, 2, 3, 1]
        #expect(Array(m.columnMajor[12...14]) == [1, 2, 3])
    }
}

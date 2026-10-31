import Foundation
import Testing
import simd
@testable import RecallDomain

@Suite("Scan quality")
struct ScanQualityTests {
    @Test func surfacesSplitFloorFromWalls() {
        var s = SurfaceCoverage()
        var pts: [SIMD3<Float>] = []
        for x in stride(from: Float(-1), through: 1, by: 0.25) {
            for z in stride(from: Float(-1), through: 1, by: 0.25) { pts.append([x, 0, z]) }
        }
        pts += [[0, 1.0, -2], [0, 1.4, -2], [2, 1.2, 0]]  // a wall ahead (−z) and one to the right (+x)
        s.add(samples: pts, camera: [0, 1.4, 0])
        #expect(s.floorY == 0)
        #expect(s.floorSeenM2 > 3)
        #expect(s.wallSectors == [0, 3])
        #expect(s.wallsCovered == 2)
    }

    @Test func pathLengthAndDistanceFromStart() {
        var s = SurfaceCoverage()
        for p: SIMD3<Float> in [[0, 1.4, 0], [1, 1.4, 0], [1, 1.4, -1], [0, 1.4, 0]] { s.add(samples: [], camera: p) }
        #expect(abs(s.walkedM - (2 + 2.squareRoot())) < 0.01)
        #expect(s.fromStartM < 0.01)
    }

    private func input(_ t: Double, jump: Double = 0, pitch: Double = 0, depth: Double? = 1.5, high: Double? = 0.8,
                       lux: Double? = 500, floor: Bool = true) -> ScanSignals.Input {
        .init(t: t, speed: 0.2, turnRate: 10, reason: nil, jump: jump, pitch: pitch, centreDepth: depth,
              highConfidence: high, lux: lux, sinceKeyframe: 0, floorSeen: floor)
    }

    @Test func aPoseJumpIsSaidAtOnceThenClears() {
        var s = ScanSignals()
        #expect(s.update(input(1, jump: 0.8)) == .cue(.holdStill, spoken: ScanSignals.say(.holdStill)))
        #expect(s.update(input(1.2)) == nil)  // calm, but not for a second yet
        #expect(s.update(input(2.3)) == .clear)
        #expect(s.cues == 1)
    }

    @Test func conditionsMustLastBeforeTheyAreSaid() {
        var s = ScanSignals()
        #expect(s.update(input(1, depth: 0.2)) == nil)  // too close, but only just now
        #expect(s.update(input(2, depth: 0.2)) == nil)
        #expect(s.update(input(2.6, depth: 0.2)) == .cue(.stepBack, spoken: ScanSignals.say(.stepBack)))
        #expect(s.update(input(4, depth: 0.2)) == nil)  // the same cue waits 8 s before repeating
        #expect(s.update(input(10.7, depth: 0.2)) != nil)
    }

    @Test func darkAndNeverLookingDown() {
        var s = ScanSignals()
        _ = s.update(input(1, lux: 60))
        #expect(s.update(input(4.1, lux: 60)) == .cue(.moreLight, spoken: ScanSignals.say(.moreLight)))
        var t = ScanSignals()
        #expect(t.update(input(31, floor: false)) == .cue(.tiltDown, spoken: ScanSignals.say(.tiltDown)))
    }

    @Test func voiceStepsAdvanceByMeasurement() {
        var g = ScanGuide()
        func p(_ t: Double, dirs: Int = 0, walls: Int = 0, floor: Double = 0, walked: Double = 0, fromStart: Double = 3,
               map: MapStatus = .extending) -> ScanGuide.Progress {
            .init(elapsed: t, directions: dirs, walls: walls, floorSeenM2: floor, areaWalkedM2: 4, walkedM: walked,
                  fromStartM: fromStart, map: map)
        }
        #expect(g.update(p(1)) == nil)
        #expect(g.update(p(4)) == ScanGuide.Step.turnAround.spoken)
        #expect(g.update(p(10, dirs: 8)) == nil)
        #expect(g.update(p(20, dirs: 11)) == ScanGuide.Step.alongWalls.spoken)
        #expect(g.update(p(40, dirs: 12, walls: 9)) == ScanGuide.Step.sweepDown.spoken)
        #expect(g.update(p(60, dirs: 12, walls: 9, floor: 3)) == ScanGuide.Step.returnToStart.spoken)
        #expect(g.update(p(70, dirs: 12, walls: 9, floor: 3, walked: 9, fromStart: 0.6)) == ScanGuide.Step.finish.spoken)
        #expect(g.loopClosed)
        #expect(!g.mapReady)
        #expect(g.update(p(75, map: .mapped)) == "Room map ready. Double tap Stop.")
        #expect(g.mapReady)
        #expect(g.update(p(76, map: .mapped)) == nil)
    }

    @Test func aStuckStepMovesOnAfterAWhile() {
        var g = ScanGuide()
        _ = g.update(.init(elapsed: 4, directions: 0, walls: 0, floorSeenM2: 0, areaWalkedM2: 0, walkedM: 0,
                           fromStartM: 0, map: .limited))
        #expect(g.step == .turnAround)
        _ = g.update(.init(elapsed: 65, directions: 3, walls: 0, floorSeenM2: 0, areaWalkedM2: 0, walkedM: 0,
                           fromStartM: 0, map: .limited))
        #expect(g.step == .alongWalls)
    }

    @Test func keyframesFillGaps() {
        var k = KeyframeSelector()
        k.accept(matrix_identity_float4x4, at: 0)
        var moved = matrix_identity_float4x4
        moved.columns.3 = [0.06, 0, 0, 1]
        #expect(!k.qualifies(moved, at: 1.0))  // 6 cm is not enough yet
        #expect(k.qualifies(moved, at: 1.6))  // but after 1.5 s without a view it is
        #expect(abs(k.since(1.6) - 1.6) < 1e-9)
    }

    @Test func goodNeedsWallsAndTheRoomMap() {
        func g(walls: Int?, map: MapStatus?) -> ScanGrade {
            ScanGrade.grade(directions: 12, trackingNormal: 0.95, blurryShare: 0.05, walls: walls, map: map)
        }
        #expect(g(walls: 10, map: .mapped) == .good)
        #expect(g(walls: 5, map: .mapped) == .usable)
        #expect(g(walls: 10, map: .extending) == .usable)
        #expect(g(walls: nil, map: nil) == .good)  // older scans without the measures
        let m = CaptureMetrics(directionsCovered: 12, keyframesKept: 50, keyframesDroppedBlurry: 1,
                               trackingNormalRatio: 0.95, meanSpeedMps: 0.3, peakSpeedMps: 0.6, slowDownCues: 0,
                               areaWalkedM2: 6, meanLightLux: 300, wallsCovered: 5, mapStatus: .mapped)
        #expect(ScanGrade.reason(for: m) == "Walls were seen on 5 of 12 sides. Walk along the walls next time.")
    }
}

@Suite("Compass")
struct CompassTests {
    @Test func meanWrapsAroundNorth() throws {
        let r = try #require(CompassMath.circularMean([350, 10, 0]))
        #expect(abs(CompassMath.difference(r.mean, 0)) < 0.01)
        #expect(r.spread < 10)
        #expect(CompassMath.circularMean([]) == nil)
    }

    @Test func namesAndFacing() {
        #expect(CompassMath.name(0) == "north")
        #expect(CompassMath.name(44) == "north-east")
        #expect(CompassMath.name(90) == "east")
        #expect(CompassMath.name(350) == "north")
        #expect(CompassMath.name(-90) == "west")
        #expect(CompassMath.facing(355, 5))
        #expect(!CompassMath.facing(30, 0))
        #expect(CompassMath.difference(10, 350) == 20)
    }

    @Test func calibrationUsesUprightReliableReadingsOnly() throws {
        var c = CompassCalibration()
        for _ in 0..<4 { c.add(.init(magneticDeg: 10, accuracyDeg: 5), cameraYaw: 100, pitch: 0) }
        #expect(c.summary == nil)  // too few
        c.add(.init(magneticDeg: 200, accuracyDeg: -1), cameraYaw: 100, pitch: 0)  // invalid
        c.add(.init(magneticDeg: 200, accuracyDeg: 5), cameraYaw: 100, pitch: 50)  // pointing at the ceiling
        #expect(c.offsets.count == 4)
        c.add(.init(magneticDeg: 12, accuracyDeg: 5), cameraYaw: 100, pitch: 10)
        let s = try #require(c.summary)
        #expect(abs(s.northYawDeg - 89.6) < 0.2)
        #expect(s.samples == 5)
    }

    @Test func directionsNameTheCompassPoint() {
        let cue = RouteFollower.Cue(clock: 3, metres: 3, arrived: false, waypoint: 1)
        #expect(Directions.say(cue, heading: 0) == "At 3 o'clock, east, 3 metres.")
        #expect(Directions.say(cue, heading: 280) == "At 3 o'clock, north, 3 metres.")  // 280 + 90 wraps to 10
        #expect(Directions.say(cue) == "At 3 o'clock, 3 metres.")
    }
}

@Suite("Floor arrows")
struct ChevronLayoutTests {
    @Test func evenlySpacedAlongAStraightLegWithGapsAtTheEnds() {
        let c = ChevronLayout.place(path: [[0, 0], [0, -3]])
        #expect(zip(c.map(\.position), [-0.5, -1.1, -1.7, -2.3]).allSatisfy { $0.0.x == 0 && abs($0.0.y - $0.1) < 1e-9 })
        #expect(c.count == 4)  // 2.9 would be past the 0.4 m gap before the thing
        #expect(c.allSatisfy { abs($0.yawDeg) < 1e-9 })  // along −z: straight ahead
    }

    @Test func turnsWithTheRoute() {
        let c = ChevronLayout.place(path: [[0, 0], [0, -1], [2, -1]])
        #expect(c.first.map { abs($0.yawDeg) < 1e-9 } == true)
        #expect(c.last.map { abs($0.yawDeg - 90) < 1e-9 } == true)  // towards +x: a quarter turn clockwise
        #expect(c.contains { abs($0.position.y + 1) < 1e-9 && $0.position.x > 0 })  // carried round the corner
    }

    @Test func shortOrEmptyRoutesHaveNone() {
        #expect(ChevronLayout.place(path: [[0, 0], [0, -0.8]]).isEmpty)
        #expect(ChevronLayout.place(path: []).isEmpty)
        #expect(ChevronLayout.place(path: [[1, 1], [1, 1]]).isEmpty)
        #expect(ChevronLayout.place(path: [[0, 0], [0, -100]]).count == 30)
    }
}

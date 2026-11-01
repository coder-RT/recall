import Foundation
import Testing
@testable import RecallDomain

@Suite("Scan steps that explain themselves, and the report's tips")
struct ScanStepsTests {
    private func p(_ t: Double, dirs: Int = 0, walls: Int = 0, floor: Double = 0, walked: Double = 0, fromStart: Double = 3,
                   map: MapStatus = .extending) -> ScanGuide.Progress {
        .init(elapsed: t, directions: dirs, walls: walls, floorSeenM2: floor, areaWalkedM2: 4, walkedM: walked,
              fromStartM: fromStart, map: map)
    }

    @Test func everyStepSaysWhatWhyAndWhenItsDone() {
        for step in ScanGuide.Step.allCases {
            #expect(!step.instruction.isEmpty && !step.why.isEmpty && step.doneWhen.hasPrefix("Done when"))
        }
        #expect(ScanGuide.Step.alongWalls.instruction.contains("about a metre away"))
        #expect(ScanGuide.Step.alongWalls.why.contains("1 metre"))
    }

    @Test func eachStepHasAMeter() {
        #expect(ScanGuide.progress(of: .turnAround, p(10, dirs: 7)).text == "Directions seen 7 of 11")
        #expect(ScanGuide.progress(of: .alongWalls, p(10, walls: 5)).fraction == 5.0 / 9)
        #expect(ScanGuide.progress(of: .sweepDown, p(10, floor: 1.6)).text == "Floor and tops seen 1.6 of 2.5 m²")
        #expect(ScanGuide.progress(of: .returnToStart, p(10, fromStart: 2.3)).text == "2.3 m from the start")
        #expect(ScanGuide.progress(of: .returnToStart, p(10, fromStart: 0.5)).text == "Back at the start")
        #expect(ScanGuide.progress(of: .finish, p(10, map: .mapped)).fraction == 1)
    }

    @Test func aboutAMetreFromTheWallIsRight() {
        #expect(ScanGuide.wallDistance(1.1) == .good)
        #expect(ScanGuide.wallDistance(0.4) == .tooClose)
        #expect(ScanGuide.wallDistance(2.5) == .tooFar)
    }

    @Test func eachStepIsRecordedDoneOrMovedOn() {
        var g = ScanGuide()
        _ = g.update(p(4))
        _ = g.update(p(20, dirs: 11))
        let line = g.update(p(141, dirs: 12, walls: 6))  // the walls step ran out of time
        #expect(line?.hasPrefix("Moving on: wall sides seen 6 of 9.") == true)
        #expect(g.records.map(\.completed) == [true, true, false])
        #expect(g.records[2].detail == "Wall sides seen 6 of 9" && g.records[2].seconds == 121)
        #expect(g.records[1].title == "Turn all the way round")
    }

    private func metrics(peak: Double = 0.4, walls: Int = 11, dirs: Int = 12, lux: Double = 400, loop: Bool = true,
                         spread: Double = 5) -> CaptureMetrics {
        CaptureMetrics(directionsCovered: dirs, keyframesKept: 100, keyframesDroppedBlurry: 2, trackingNormalRatio: 0.98,
                       meanSpeedMps: 0.3, peakSpeedMps: peak, slowDownCues: 0, areaWalkedM2: 8, meanLightLux: lux,
                       wallsCovered: walls, floorSeenM2: 4, mapStatus: .mapped, loopClosed: loop, compassSpreadDeg: spread)
    }

    @Test func aGoodScanNeedsNoTips() { #expect(ScanTips.make(metrics()).isEmpty) }

    @Test func missedHeightZonesGetATip() {
        var m = metrics()
        m.zonesSeen = 12
        m.zonesTotal = 40
        #expect(ScanTips.make(m) == ["Height zones seen 12 of 40. Point the phone at knee height and up at shelves too, not only straight ahead."])
    }

    @Test func tipsSayWhatToDoBetterAtMostThree() {
        let tips = ScanTips.make(metrics(peak: 0.9, walls: 5, dirs: 7, lux: 50, loop: false, spread: 40))
        #expect(tips.count == 3)
        #expect(tips[0].hasPrefix("You walked at up to 0.9 metres a second"))
        #expect(tips[1].hasPrefix("Walls were seen on 5 of 12 sides"))
        #expect(ScanTips.light(80) == "Dim" && ScanTips.light(400) == "OK")
    }

    @Test func scansSavedBeforeStepsWereRecordedStillOpen() throws {
        let old = #"{"directions_covered":10,"keyframes_kept":50,"keyframes_dropped_blurry":3,"tracking_normal_ratio":0.95,"mean_speed_mps":0.3,"peak_speed_mps":0.5,"slow_down_cues":1,"area_walked_m2":6,"mean_light_lux":300,"grade":"good"}"#
        let m = try JSONDecoder().decode(CaptureMetrics.self, from: Data(old.utf8))
        #expect(m.steps == nil && m.points == nil && m.directionsCovered == 10)
    }
}

@Suite("How high to hold the phone")
struct PhoneHeightTests {
    @Test func chestHeightToLookRoundWaistHeightToSweep() {
        #expect(ScanGuide.Step.alongWalls.heightLabel == "Chest height, 1.1 to 1.5 m")
        #expect(ScanGuide.Step.sweepDown.heightLabel == "Waist height, 0.8 to 1.1 m")
        #expect(HeightCoach.check(1.35, for: .alongWalls) == .good)  // a 180 cm person's chest
        #expect(HeightCoach.check(0.9, for: .alongWalls) == .tooLow)
        #expect(HeightCoach.check(1.35, for: .sweepDown) == .tooHigh)
    }

    @Test func itWaitsBeforeSayingAnythingAndDoesntNag() {
        var coach = HeightCoach()
        #expect(coach.update(t: 0, height: nil, step: .alongWalls) == nil)  // floor not found yet
        #expect(coach.update(t: 1, height: 0.8, step: .alongWalls) == nil)
        #expect(coach.update(t: 4.5, height: 0.8, step: .alongWalls) == "Raise the phone to chest height.")
        #expect(coach.update(t: 6, height: 0.8, step: .alongWalls) == nil)  // not again so soon
        #expect(coach.update(t: 7, height: 1.3, step: .alongWalls) == nil)  // back in the band
        #expect(coach.update(t: 30, height: 1.4, step: .sweepDown) == nil)
        #expect(coach.update(t: 34, height: 1.4, step: .sweepDown) == "Lower the phone to waist height.")
    }
}

@Suite("Height zones and columns")
struct ZoneCoverageTests {
    @Test func pointsLandInTheirColumnAndHeightBand() {
        var z = ZoneCoverage()
        z.add([SIMD3(0.5, -1.4, 0.5), SIMD3(0.5, -0.6, 0.2), SIMD3(1.5, -1.0, 0.5)], floorY: -1.5)  // floor, waist; knee
        #expect(z.seen[.init(x: 0, z: 0)] == [0, 2])
        #expect(z.seen[.init(x: 1, z: 0)] == [1])
        #expect((z.zonesSeen, z.zonesTotal) == (3, 10))
    }

    @Test func bandsAreRecallsHeightBands() {
        #expect(ZoneCoverage.band(0.1) == 0 && ZoneCoverage.band(0.5) == 1 && ZoneCoverage.band(0.9) == 2)
        #expect(ZoneCoverage.band(1.3) == 3 && ZoneCoverage.band(1.8) == 4 && ZoneCoverage.band(2.5) == nil)
    }

    @Test func itSaysWhichHeightIsLeastSeen() {
        var z = ZoneCoverage()
        z.add([SIMD3(0.5, 0.1, 0.5), SIMD3(0.5, 0.9, 0.5), SIMD3(0.5, 1.3, 0.5), SIMD3(0.5, 1.8, 0.5)], floorY: 0)
        #expect(z.weakestBand == "knee")
    }
}

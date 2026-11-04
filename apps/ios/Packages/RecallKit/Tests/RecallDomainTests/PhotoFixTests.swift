import Foundation
import simd
import Testing
@testable import RecallDomain

/// A pose at (x, y, z), turned `yaw` degrees about the vertical (ARKit y).
private func pose(_ x: Double, _ y: Double, _ z: Double, yaw: Double = 0) -> Pose {
    let a = yaw * .pi / 180
    return Pose(columnMajor: [cos(a), 0, -sin(a), 0, 0, 1, 0, 0, sin(a), 0, cos(a), 0, x, y, z, 1])
}

@Test func aCorrectionTurnsSessionPosesIntoTheMapsWorld() {
    let T = MapCorrection.matrix(pose(2, 0, -1, yaw: 30))  // the session's world inside the map's
    let session = pose(0.5, 1.4, 0.2, yaw: -10)
    let map = MapCorrection.apply(T, to: session)
    let back = MapCorrection.between(map: map, session: session)
    let d = MapCorrection.distance(back, T)
    #expect(d.metres < 1e-9 && d.degrees < 1e-6)
    // a later session pose lands where the same correction puts it
    let later = MapCorrection.apply(back, to: pose(1.5, 1.4, 0.2, yaw: -10))
    #expect(abs(simd_distance(SIMD2(later.columnMajor[12], later.columnMajor[14]),
                              SIMD2(map.columnMajor[12], map.columnMajor[14])) - 1) < 1e-9)
}

@Test func twoFixesMustAgreeAndComeFromALiveSession() {
    var a = FixAgreement()
    let T1 = MapCorrection.matrix(pose(2, 0, -1, yaw: 30)), near = MapCorrection.matrix(pose(2.1, 0, -1, yaw: 33))
    #expect(a.add(T1, session: pose(0, 1.4, 0)) == nil)  // one fix proves nothing
    #expect(a.add(near, session: pose(0.05, 1.4, 0)) != nil)  // 10 cm and 3° apart: agreed

    var far = FixAgreement()
    _ = far.add(T1, session: pose(0, 1.4, 0))
    #expect(far.add(MapCorrection.matrix(pose(3, 0, -1, yaw: 30)), session: pose(0.05, 1.4, 0)) == nil)  // 1 m apart
    #expect(far.add(MapCorrection.matrix(pose(3, 0, -1, yaw: 31)), session: pose(0.1, 1.4, 0)) != nil)  // then two agree

    var frozen = FixAgreement()
    _ = frozen.add(T1, session: pose(0, 1.4, 0))
    #expect(frozen.add(T1, session: pose(0, 1.4, 0)) == nil)  // the same session pose twice: ARKit isn't tracking
}

@Test func coachingNamesThingsToPointAt() {
    // what to do with your body, never where to look: nobody has to find a thing they can't see
    for turn in 0..<3 { #expect(!LocateCoaching.keepTurning(turn: turn).contains("Point")) }
    #expect(LocateCoaching.elsewhere(found: "Bedroom", wanted: "Living room")
        == "You seem to be in Bedroom, not Living room. Walk to Living room and I'll keep looking.")
}

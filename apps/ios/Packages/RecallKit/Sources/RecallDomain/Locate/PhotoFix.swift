import Foundation
import simd

/// What the Mac's photo matcher said about one camera photo (classic features + PnP against the scans; no model).
public struct PlaceFix: Sendable, Equatable {
    /// The room the photo was taken in, when one room clearly matched (it may not be the room being looked for).
    public let room: String?
    /// The camera's pose in the room map's world, when that room matched well enough.
    public let pose: Pose?
    public let inliers: Int
    /// What to point the phone at in that room, one-of-a-kind furniture first ("tv", "cabinet").
    public let hint: [String]

    public init(room: String?, pose: Pose?, inliers: Int, hint: [String]) {
        self.room = room; self.pose = pose; self.inliers = inliers; self.hint = hint
    }
}

/// From a photo fix to the phone's own poses: T(map ← session) = map pose × session pose⁻¹, for the same photo.
public enum MapCorrection {
    public static func between(map: Pose, session: Pose) -> simd_double4x4 { matrix(map) * matrix(session).inverse }

    /// A session pose in the room map's world.
    public static func apply(_ T: simd_double4x4, to pose: Pose) -> Pose { Pose(columnMajor: columnMajor(T * matrix(pose))) }

    public static func matrix(_ p: Pose) -> simd_double4x4 {
        let c = p.columnMajor
        return simd_double4x4(columns: (SIMD4(c[0], c[1], c[2], c[3]), SIMD4(c[4], c[5], c[6], c[7]),
                                        SIMD4(c[8], c[9], c[10], c[11]), SIMD4(c[12], c[13], c[14], c[15])))
    }

    public static func columnMajor(_ m: simd_double4x4) -> [Double] {
        [m.columns.0, m.columns.1, m.columns.2, m.columns.3].flatMap { [$0.x, $0.y, $0.z, $0.w] }
    }

    /// How far apart two transforms are: metres between their origins, degrees between their rotations.
    public static func distance(_ a: simd_double4x4, _ b: simd_double4x4) -> (metres: Double, degrees: Double) {
        let ta = SIMD3(a.columns.3.x, a.columns.3.y, a.columns.3.z), tb = SIMD3(b.columns.3.x, b.columns.3.y, b.columns.3.z)
        let ra = simd_double3x3(SIMD3(a.columns.0.x, a.columns.0.y, a.columns.0.z), SIMD3(a.columns.1.x, a.columns.1.y, a.columns.1.z),
                                SIMD3(a.columns.2.x, a.columns.2.y, a.columns.2.z))
        let rb = simd_double3x3(SIMD3(b.columns.0.x, b.columns.0.y, b.columns.0.z), SIMD3(b.columns.1.x, b.columns.1.y, b.columns.1.z),
                                SIMD3(b.columns.2.x, b.columns.2.y, b.columns.2.z))
        let d = ra.transpose * rb
        let cosine = max(-1, min(1, (d.columns.0.x + d.columns.1.y + d.columns.2.z - 1) / 2))
        return (simd_distance(ta, tb), acos(cosine) * 180 / .pi)
    }
}

/// One photo fix can be wrong (on real scans about 1 in 9 from another session), so the phone trusts photo fixes
/// only when two in a row agree on the correction: within 25 cm and 10°. Two wrong fixes rarely agree.
public struct FixAgreement: Sendable {
    public var maxMetres = 0.25
    public var maxDegrees = 10.0
    private var last: (correction: simd_double4x4, session: Pose)?

    public init() {}

    /// Adds a fix's correction and the session pose its photo had; the agreed correction once two in a row agree.
    public mutating func add(_ correction: simd_double4x4, session: Pose) -> simd_double4x4? {
        defer { last = (correction, session) }
        // a session pose that never changed means ARKit isn't tracking: a correction from it would hold nothing
        guard let last, last.session != session else { return nil }
        let d = MapCorrection.distance(last.correction, correction)
        return d.metres <= maxMetres && d.degrees <= maxDegrees ? correction : nil
    }
}

/// The spoken lines while the room is being recognised.
public enum LocateCoaching {
    /// "Point the phone slowly at the TV." then "Now at the cabinet." (`turn` counts the lines said so far).
    public static func point(at hint: [String], turn: Int) -> String? {
        guard !hint.isEmpty else { return nil }
        let name = spoken(hint[turn % hint.count])
        return turn == 0 ? "Point the phone slowly at the \(name)." : "Now at the \(name)."
    }

    public static func elsewhere(found: String, wanted: String) -> String {
        "You seem to be in \(found), not \(wanted). Walk to \(wanted) and I'll keep looking."
    }

    /// A furniture label as said aloud: short ones are initials ("tv" → "TV").
    public static func spoken(_ label: String) -> String { label.count <= 2 ? label.uppercased() : label }
}

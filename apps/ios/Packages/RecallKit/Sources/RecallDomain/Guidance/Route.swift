import Foundation

/// A route the Mac planned to a thing. `waypoints` are in the phone's ARKit world as (x, z); empty when only
/// landmark directions are possible (`landmarksOnly`, with the reason).
public struct Route: Sendable, Equatable {
    public struct Step: Sendable, Equatable {
        public let clock: Int
        public let metres: Double
        public let say: String
        public init(clock: Int, metres: Double, say: String) { self.clock = clock; self.metres = metres; self.say = say }
    }

    public let sessionId: String
    public let landmarksOnly: Bool
    public let reason: String?
    public let steps: [Step]
    public let waypoints: [SIMD2<Double>]
    public let arriveSay: String?
    /// The thing in the phone's ARKit world, where the arrow is drawn.
    public let target: SIMD3<Double>?
    /// Compass bearing (magnetic) from the room's middle to the thing, when the scan had a reliable compass.
    public let bearingDeg: Double?
    /// The floor's height in the phone's ARKit world, where the arrows along the route lie.
    public let floorY: Double?

    public init(sessionId: String, landmarksOnly: Bool, reason: String?, steps: [Step], waypoints: [SIMD2<Double>],
                arriveSay: String?, target: SIMD3<Double>? = nil, bearingDeg: Double? = nil, floorY: Double? = nil) {
        self.sessionId = sessionId; self.landmarksOnly = landmarksOnly; self.reason = reason; self.steps = steps
        self.waypoints = waypoints; self.arriveSay = arriveSay; self.target = target; self.bearingDeg = bearingDeg
        self.floorY = floorY
    }

    /// The route can be walked on the phone (otherwise the steps are only spoken).
    public var isWalkable: Bool { !landmarksOnly && waypoints.count > 1 }

    /// All the steps as one spoken line.
    public var spokenSteps: String { steps.map(\.say).joined(separator: " ") }
}

/// The phone's pose for planning: ARKit camera-to-world, column-major, in the saved map's world.
public struct Pose: Sendable, Equatable {
    public let columnMajor: [Double]

    public init(columnMajor: [Double]) {
        precondition(columnMajor.count == 16, "a pose is a 4 x 4 matrix")
        self.columnMajor = columnMajor
    }

    public static let identity = Pose(columnMajor: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1])

    /// The camera's floor position (x, z).
    public var position: SIMD2<Double> { SIMD2(columnMajor[12], columnMajor[14]) }

    /// Where the camera looks on the floor (x, z): ARKit cameras look along −Z.
    public var forward: SIMD2<Double> { SIMD2(-columnMajor[8], -columnMajor[10]) }
}

/// Decides when a guidance cue is worth saying aloud: a new direction, a metre closer, or a reminder every few
/// seconds; never a stream of repeats.
public struct CueThrottle: Sendable {
    public let reminderSeconds: Double
    private var last: (clock: Int, metres: Double, at: Date)?

    public init(reminderSeconds: Double = 6) { self.reminderSeconds = reminderSeconds }

    public mutating func shouldSay(_ cue: RouteFollower.Cue, at now: Date) -> Bool {
        if let last, last.clock == cue.clock, last.metres - cue.metres < 1, now.timeIntervalSince(last.at) < reminderSeconds {
            return false
        }
        last = (cue.clock, cue.metres, now)
        return true
    }
}

import Foundation

/// Follows a planned route on the phone: from the camera's floor position and facing (ARKit world, x and z), it
/// says which way the next waypoint is as a clock face (12 straight ahead, 3 to the right) and how far.
/// Waypoints are passed when within `reachRadius`; the last one counts as arrived within `arrivalRadius`.
public struct RouteFollower: Sendable {
    public struct Cue: Sendable, Equatable {
        public let clock: Int
        public let metres: Double
        public let arrived: Bool
        public let waypoint: Int
        /// How far the phone is from the leg it is walking (from the previous waypoint to the next).
        public var offRouteMetres: Double = 0

        public init(clock: Int, metres: Double, arrived: Bool, waypoint: Int, offRouteMetres: Double = 0) {
            self.clock = clock; self.metres = metres; self.arrived = arrived; self.waypoint = waypoint
            self.offRouteMetres = offRouteMetres
        }
    }

    public let waypoints: [SIMD2<Double>]
    public let reachRadius: Double
    public let arrivalRadius: Double
    public private(set) var next = 0

    public init(waypoints: [SIMD2<Double>], reachRadius: Double = 0.4, arrivalRadius: Double = 0.5) {
        self.waypoints = waypoints
        self.reachRadius = reachRadius
        self.arrivalRadius = arrivalRadius
        // the first waypoint is where the route starts (the person); aim at the one after it
        next = waypoints.count > 1 ? 1 : 0
    }

    /// `position` is (x, z) in ARKit's world; `forward` is the camera's facing on the floor, (x, z), any length.
    public mutating func update(position: SIMD2<Double>, forward: SIMD2<Double>) -> Cue? {
        guard !waypoints.isEmpty else { return nil }
        while next < waypoints.count - 1, distance(position, waypoints[next]) < reachRadius { next += 1 }
        let target = waypoints[next]
        let metres = distance(position, target)
        let last = next == waypoints.count - 1
        let legStart = waypoints[max(next - 1, 0)]
        return Cue(clock: Self.clock(forward: forward, to: target - position), metres: metres,
                   arrived: last && metres < arrivalRadius, waypoint: next,
                   offRouteMetres: Self.distance(from: position, toSegment: legStart, target))
    }

    /// The direction of `to` seen from `forward`, as an hour on a clock face. ARKit's world is x right, y up and z
    /// towards the viewer, so seen from above a turn to the right is clockwise.
    public static func clock(forward f: SIMD2<Double>, to d: SIMD2<Double>) -> Int {
        let cross = f.y * d.x - f.x * d.y  // y component of f × d in (x, y, z) with y up, negated below
        let dot = f.x * d.x + f.y * d.y
        let degrees = atan2(-cross, dot) * 180 / .pi  // clockwise from straight ahead
        let hour = (Int((degrees / 30).rounded()) % 12 + 12) % 12
        return hour == 0 ? 12 : hour
    }

    /// Distance from `p` to the segment a–b.
    static func distance(from p: SIMD2<Double>, toSegment a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double {
        let ab = b - a
        let len2 = ab.x * ab.x + ab.y * ab.y
        let t = len2 == 0 ? 0 : max(0, min(1, ((p - a).x * ab.x + (p - a).y * ab.y) / len2))
        let d = p - (a + t * ab)
        return (d.x * d.x + d.y * d.y).squareRoot()
    }

    private func distance(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double {
        let d = a - b
        return (d.x * d.x + d.y * d.y).squareRoot()
    }
}

/// How a cue is spoken: "Straight ahead, 2 metres", "At 3 o'clock, 1 metre", "Behind you, turn around".
public enum Directions {
    /// `heading`: the phone's compass heading now (magnetic), to add where that is: "At 2 o'clock, north-east, 3 metres."
    public static func say(_ cue: RouteFollower.Cue, heading: Double? = nil) -> String {
        let way: String
        switch cue.clock {
        case 12: way = "Straight ahead"
        case 6: way = "Behind you, turn around"
        default: way = "At \(cue.clock) o'clock"
        }
        let compass = heading.map { ", " + CompassMath.name($0 + Double(cue.clock % 12) * 30) } ?? ""
        return "\(way)\(compass), \(metres(cue.metres))."
    }

    public static func metres(_ m: Double) -> String {
        if m < 1 { return "\(max(1, Int((m * 10).rounded())) * 10) centimetres" }
        let r = (m * 2).rounded() / 2
        return r == 1 ? "1 metre" : (r == r.rounded() ? "\(Int(r)) metres" : String(format: "%.1f metres", r))
    }
}

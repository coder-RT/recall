import Foundation
import simd

/// Where the floor arrows go along a route: evenly spaced along the path (ARKit x, z), each turned to the way the
/// path runs there, like the arrows on a racing game's track. Leaves a gap at the start (under the person's feet)
/// and at the end (the arrow over the thing takes over).
public enum ChevronLayout {
    public struct Chevron: Sendable, Equatable {
        public let position: SIMD2<Double>
        /// ARKit yaw of the direction it points: 0 = −z, clockwise seen from above (degrees).
        public let yawDeg: Double
    }

    public static func place(path: [SIMD2<Double>], spacing: Double = 0.6, skipStart: Double = 0.5,
                             skipEnd: Double = 0.4, max: Int = 30) -> [Chevron] {
        let legs = zip(path, path.dropFirst()).filter { simd_distance($0.0, $0.1) > 1e-6 }
        let total = legs.reduce(0) { $0 + simd_distance($1.0, $1.1) }
        var out: [Chevron] = []
        var at = skipStart
        var walked = 0.0
        for (a, b) in legs {
            let length = simd_distance(a, b)
            let d = (b - a) / length
            while at <= walked + length, at <= total - skipEnd, out.count < max {
                let p = a + d * (at - walked)
                var yaw = atan2(d.x, -d.y) * 180 / .pi
                if yaw < 0 { yaw += 360 }
                out.append(Chevron(position: p, yawDeg: yaw))
                at += spacing
            }
            walked += length
        }
        return out
    }
}

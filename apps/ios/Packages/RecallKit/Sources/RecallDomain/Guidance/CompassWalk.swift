import Foundation

/// One straight stretch of a walk by compass: a magnetic bearing (clockwise from north) and how far.
public struct CompassLeg: Sendable, Equatable, Codable {
    public let bearing: Double
    public let metres: Double
    public init(bearing: Double, metres: Double) { self.bearing = bearing; self.metres = metres }
}

/// The way to a thing for a watch with a compass and a step counter but no camera: from where the room's scan began,
/// leg by leg. The Mac plans it (GET /homes/{id}/objects/{id}/compass-route).
public struct CompassRoute: Sendable, Equatable, Codable {
    public let thingId: String
    public let label: String
    public let color: String?
    /// "where you started the scan of Living room": where to stand first
    public let start: String
    /// "near the desk, at knee height"
    public let place: String
    public let legs: [CompassLeg]

    public init(thingId: String, label: String, color: String?, start: String, place: String, legs: [CompassLeg]) {
        self.thingId = thingId; self.label = label; self.color = color; self.start = start; self.place = place
        self.legs = legs
    }

    public var title: String { [color, label].compactMap { $0 }.joined(separator: " ") }
}

/// Walks a compass route from the watch's heading and the metres its pedometer counted. Pure: the watch feeds it
/// readings and turns each cue into a haptic and, now and then, a few spoken words.
public struct CompassWalk: Sendable {
    public enum Side: Sendable, Equatable { case left, right }

    public enum Cue: Sendable, Equatable {
        /// face the leg's bearing first: which way, and by how many degrees
        case turn(Side, degrees: Double)
        /// facing the right way: how far is left on this leg
        case onCourse(metresLeft: Double)
        /// a leg is done; the next one starts (its index)
        case nextLeg(Int)
        /// walked well past the leg's end
        case overshot
        case arrived
    }

    public let legs: [CompassLeg]
    public private(set) var leg = 0
    /// pedometer metres when the current leg started
    private var legStart: Double = 0
    /// once facing the right way, small wobbles don't send it back to "turn" (hysteresis)
    private var facing = false

    public var turnWhenOff: Double = 25  // degrees off before it says turn again
    public var facingWithin: Double = 15  // degrees to count as facing the leg
    public var overshootMetres: Double = 2

    public init(legs: [CompassLeg]) { self.legs = legs }

    /// Signed difference from `heading` to `bearing`, -180...180 (positive: turn right, clockwise).
    public static func offset(heading: Double, bearing: Double) -> Double {
        var d = (bearing - heading).truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d
    }

    public mutating func update(heading: Double, metresWalked: Double) -> Cue {
        guard leg < legs.count else { return .arrived }
        let target = legs[leg]
        let walked = metresWalked - legStart
        if walked >= target.metres {
            if walked > target.metres + overshootMetres { return .overshot }
            leg += 1
            legStart = metresWalked
            facing = false
            return leg == legs.count ? .arrived : .nextLeg(leg)
        }
        let off = Self.offset(heading: heading, bearing: target.bearing)
        if facing ? abs(off) > turnWhenOff : abs(off) > facingWithin {
            facing = false
            return .turn(off > 0 ? .right : .left, degrees: abs(off))
        }
        facing = true
        return .onCourse(metresLeft: max(0, target.metres - walked))
    }

    /// "Turn right" / "Turn left" / "Straight on", then the distance: what the watch says for a leg.
    public static func say(_ cue: Cue, leg: CompassLeg?) -> String {
        switch cue {
        case .turn(let side, let degrees):
            return degrees > 135 ? "Turn around" : side == .right ? "Turn right" : "Turn left"
        case .onCourse(let left): return "Straight on, \(Self.metres(left))"
        case .nextLeg: return leg.map { "Next, \(Self.metres($0.metres))" } ?? "Next"
        case .overshot: return "Stop. You've gone past it"
        case .arrived: return "You're there"
        }
    }

    static func metres(_ m: Double) -> String {
        let r = max(1, Int(m.rounded()))
        return r == 1 ? "1 metre" : "\(r) metres"
    }
}

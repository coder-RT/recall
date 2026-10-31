import Foundation

/// "Slow down" from ARKit's tracking reasons plus our own speed and turn-rate limits, with hysteresis and a cue limit.
public struct SpeedCoach: Sendable {
    public struct Limits: Sendable {
        public var maxSpeed: Double = 0.5        // m/s
        public var speedHold: Double = 0.5       // s above maxSpeed before a cue
        public var maxTurnRate: Double = 60      // °/s
        public var turnHold: Double = 0.3        // s above maxTurnRate before a cue
        public var clearAfter: Double = 1.0      // s back under the limits before the cue clears
        public var minCueGap: Double = 3.0       // s between spoken cues
        public init() {}
    }

    public enum Event: Equatable, Sendable { case slowDown(Cause), clear }
    public enum Cause: String, Equatable, Sendable { case walkingFast, turningFast, trackingExcessiveMotion, trackingFewFeatures }

    public var limits: Limits
    public private(set) var active = false
    public private(set) var cues = 0
    private var fastSince: Double?
    private var turningSince: Double?
    private var calmSince: Double?
    private var lastCue: Double = -.infinity

    public init(limits: Limits = Limits()) { self.limits = limits }

    /// Feed one sample (about 30 per second). Returns an event when the coach should speak or clear the banner.
    public mutating func update(t: Double, speed: Double, turnRate: Double, reason: TrackingReason?) -> Event? {
        var cause: Cause?
        switch reason {
        case .excessiveMotion: cause = .trackingExcessiveMotion
        case .insufficientFeatures: cause = .trackingFewFeatures
        default: break
        }
        if speed > limits.maxSpeed { fastSince = fastSince ?? t } else { fastSince = nil }
        if turnRate > limits.maxTurnRate { turningSince = turningSince ?? t } else { turningSince = nil }
        if cause == nil, let s = fastSince, t - s >= limits.speedHold { cause = .walkingFast }
        if cause == nil, let s = turningSince, t - s >= limits.turnHold { cause = .turningFast }

        if let cause {
            calmSince = nil
            guard !active || t - lastCue >= limits.minCueGap else { return nil }
            guard t - lastCue >= limits.minCueGap else { active = true; return nil }
            active = true
            lastCue = t
            cues += 1
            return .slowDown(cause)
        }
        guard active else { return nil }
        calmSince = calmSince ?? t
        if let c = calmSince, t - c >= limits.clearAfter {
            active = false
            calmSince = nil
            return .clear
        }
        return nil
    }

    public static func say(_ cause: Cause) -> String {
        switch cause {
        case .walkingFast: return "Slow down. Walk more slowly."
        case .turningFast: return "Slow down. Turn more slowly."
        case .trackingExcessiveMotion: return "Slow down. The phone is moving too fast to follow."
        case .trackingFewFeatures: return "Point at something with more detail, and turn on a light."
        }
    }
}

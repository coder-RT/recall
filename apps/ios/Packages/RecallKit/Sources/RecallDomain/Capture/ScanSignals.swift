import Foundation

/// Everything the phone can tell about how the scan is going, turned into one spoken cue at a time (the most
/// important first), with the same hold, clear and minimum-gap behaviour as SpeedCoach (which it uses for speed,
/// turning and ARKit's tracking reasons). The rest come from Street View's capture rules applied to a room: no jumps
/// a person couldn't make, no gaps in the views, the right distance to surfaces, enough light, and the floor in view.
public struct ScanSignals: Sendable {
    public enum Cue: String, Sendable, Equatable {
        case slowDown, holdStill, stepBack, moveCloser, moreLight, tiltDown, lowerPhone, keepMoving
    }

    public enum Event: Sendable, Equatable { case cue(Cue, spoken: String), clear }

    public struct Input: Sendable {
        public var t: Double
        public var speed: Double  // m/s on the floor
        public var turnRate: Double  // °/s
        public var reason: TrackingReason?
        public var jump: Double  // metres moved since the previous frame
        public var pitch: Double  // degrees above level (negative: tilted down)
        public var centreDepth: Double?  // metres, middle of the LiDAR image
        public var highConfidence: Double?  // share of LiDAR pixels with high confidence
        public var lux: Double?
        public var sinceKeyframe: Double  // seconds since a view was kept
        public var floorSeen: Bool  // any floor seen so far

        public init(t: Double, speed: Double, turnRate: Double, reason: TrackingReason?, jump: Double, pitch: Double,
                    centreDepth: Double?, highConfidence: Double?, lux: Double?, sinceKeyframe: Double, floorSeen: Bool) {
            self.t = t; self.speed = speed; self.turnRate = turnRate; self.reason = reason; self.jump = jump
            self.pitch = pitch; self.centreDepth = centreDepth; self.highConfidence = highConfidence; self.lux = lux
            self.sinceKeyframe = sinceKeyframe; self.floorSeen = floorSeen
        }
    }

    public private(set) var cues = 0
    public private(set) var active: Cue?
    private var coach = SpeedCoach()
    private var since: [Cue: Double] = [:]
    private var lastSpoken: (cue: Cue, t: Double)?
    private var calmSince: Double?
    private var slowDownLine: String?

    public init() {}

    /// How long each condition must last before it is said (one bad frame says nothing).
    static let hold: [Cue: Double] = [.holdStill: 0, .stepBack: 1.5, .moveCloser: 2, .moreLight: 3, .tiltDown: 0,
                                      .lowerPhone: 3, .keepMoving: 0]

    public mutating func update(_ i: Input) -> Event? {
        var now: [Cue] = []
        if let e = coach.update(t: i.t, speed: i.speed, turnRate: i.turnRate, reason: i.reason) {
            if case .slowDown(let cause) = e { slowDownLine = SpeedCoach.say(cause) }
        }
        if coach.active { now.append(.slowDown) }
        if i.jump > 0.5 { now.append(.holdStill) }
        if let d = i.centreDepth, d < 0.35 { now.append(.stepBack) }
        if let d = i.centreDepth, d > 4.5 { now.append(.moveCloser) }
        if (i.lux.map { $0 > 0 && $0 < 150 } ?? false) || (i.highConfidence.map { $0 < 0.4 } ?? false) { now.append(.moreLight) }
        if i.t > 30, !i.floorSeen, i.pitch > -10 { now.append(.tiltDown) }
        if i.pitch > 35 { now.append(.lowerPhone) }
        if i.t > 5, i.sinceKeyframe > 5 { now.append(.keepMoving) }

        for cue in Set(since.keys).subtracting(now) { since[cue] = nil }
        for cue in now where since[cue] == nil { since[cue] = i.t }
        let ready = now.filter { cue in cue == .slowDown || i.t - (since[cue] ?? i.t) >= (Self.hold[cue] ?? 0) }

        guard let top = ready.first else {
            guard active != nil else { return nil }
            calmSince = calmSince ?? i.t
            guard i.t - (calmSince ?? i.t) >= 1 else { return nil }
            active = nil
            calmSince = nil
            return .clear
        }
        calmSince = nil
        active = top
        // speak a new cue after 3 s, the same one again only after 8 s
        if let last = lastSpoken, i.t - last.t < (last.cue == top ? 8 : 3) { return nil }
        lastSpoken = (top, i.t)
        cues += 1
        return .cue(top, spoken: top == .slowDown ? (slowDownLine ?? Self.say(top)) : Self.say(top))
    }

    public static func say(_ cue: Cue) -> String {
        switch cue {
        case .slowDown: "Slow down."
        case .holdStill: "Hold still a moment while I find my place."
        case .stepBack: "Too close. Step back a little."
        case .moveCloser: "Too far. Move closer to the walls."
        case .moreLight: "It's too dark to see well. Turn on a light, or move closer."
        case .tiltDown: "Tilt the phone down a little so I can see the floor."
        case .lowerPhone: "Lower the phone. Point it at the walls, not the ceiling."
        case .keepMoving: "Keep moving slowly. I haven't seen anything new for a while."
        }
    }
}

/// ARKit's world-mapping status: how well the room map (used later to find you again) covers the room.
public enum MapStatus: String, Codable, Sendable {
    case notAvailable = "not_available", limited, extending, mapped

    public var spoken: String {
        switch self {
        case .notAvailable: "Room map not started"
        case .limited: "Room map: learning"
        case .extending: "Room map: growing"
        case .mapped: "Room map: ready"
        }
    }
}

/// The scan, led by voice, one step at a time; each step ends when the measurements say it's done (or after a while,
/// so nobody gets stuck). Then the room map has to be ready before stopping.
public struct ScanGuide: Sendable {
    public enum Step: Int, Sendable, CaseIterable, Comparable {
        case start, turnAround, alongWalls, sweepDown, returnToStart, finish

        public static func < (a: Step, b: Step) -> Bool { a.rawValue < b.rawValue }

        public var title: String {
            switch self {
            case .start: "Get ready"
            case .turnAround: "Turn all the way round"
            case .alongWalls: "Walk along the walls"
            case .sweepDown: "Sweep tables and floor"
            case .returnToStart: "Back to the start"
            case .finish: "Finish"
            }
        }

        public var spoken: String {
            switch self {
            case .start: "Stand by the door with the phone at chest height, camera facing the room."
            case .turnAround: "Turn slowly all the way round."
            case .alongWalls: "Now walk along the walls, about a metre away, with the phone pointing at the wall."
            case .sweepDown: "Tilt the phone down and slowly sweep the tables, shelves and the floor."
            case .returnToStart: "Walk back to where you started, to close the loop."
            case .finish: "Keep moving slowly until the room map is ready."
            }
        }
    }

    public struct Progress: Sendable {
        public var elapsed: Double
        public var directions: Int
        public var walls: Int
        public var floorSeenM2: Double
        public var areaWalkedM2: Double
        public var walkedM: Double  // path length so far
        public var fromStartM: Double  // distance from where the scan began
        public var map: MapStatus

        public init(elapsed: Double, directions: Int, walls: Int, floorSeenM2: Double, areaWalkedM2: Double,
                    walkedM: Double, fromStartM: Double, map: MapStatus) {
            self.elapsed = elapsed; self.directions = directions; self.walls = walls; self.floorSeenM2 = floorSeenM2
            self.areaWalkedM2 = areaWalkedM2; self.walkedM = walkedM; self.fromStartM = fromStartM; self.map = map
        }
    }

    public private(set) var step = Step.start
    public private(set) var loopClosed = false
    public private(set) var mapReady = false
    private var stepStarted = 0.0

    public init() {}

    /// Steps the scan on; returns a line to say when something changed (a new step, or the map becoming ready).
    public mutating func update(_ p: Progress) -> String? {
        let inStep = p.elapsed - stepStarted
        let done: Bool = switch step {
        case .start: p.elapsed >= 4
        case .turnAround: p.directions >= 11 || inStep > 60
        case .alongWalls: p.walls >= 9 || inStep > 120
        case .sweepDown: p.floorSeenM2 >= max(2.5, 0.5 * p.areaWalkedM2) || inStep > 90
        case .returnToStart: (p.walkedM > 3 && p.fromStartM < 1.0) || inStep > 60
        case .finish: false
        }
        if step == .returnToStart, done, p.fromStartM < 1.0 { loopClosed = true }
        if done, let next = Step(rawValue: step.rawValue + 1) {
            step = next
            stepStarted = p.elapsed
            if next == .finish, p.map == .mapped {
                mapReady = true
                return "Room map ready. Double tap Stop."
            }
            return next.spoken
        }
        if step == .finish, !mapReady, p.map == .mapped {
            mapReady = true
            return "Room map ready. Double tap Stop."
        }
        return nil
    }
}

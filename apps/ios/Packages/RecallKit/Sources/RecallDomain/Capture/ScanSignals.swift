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
        case recognise = -1  // a rescan only: find the earlier scan's room first
        case start, turnAround, alongWalls, sweepDown, returnToStart, finish

        public static func < (a: Step, b: Step) -> Bool { a.rawValue < b.rawValue }

        public var title: String {
            switch self {
            case .recognise: "Recognise the room"
            case .start: "Get ready"
            case .turnAround: "Turn all the way round"
            case .alongWalls: "Walk along the walls"
            case .sweepDown: "Sweep tables and floor"
            case .returnToStart: "Back to the start"
            case .finish: "Finish"
            }
        }

        /// Why the step matters, in one sentence: shown before the scan and on the step card.
        public var why: String {
            switch self {
            case .recognise: "This scan then shares the last one's map, so Recall can tell what moved."
            case .start: "The door is where the Watch's directions start, and a steady start lets tracking lock on."
            case .turnAround: "One full turn shows the whole room from one spot, so nothing is missed between views."
            case .alongWalls: "About 1 metre is where the LiDAR and camera see best: closer, the edges are missed and photos blur; further, small things are too small to find."
            case .sweepDown: "Your things are on tables, shelves and the floor; this is where SAM 3.1 looks for them."
            case .returnToStart: "Ending where you began closes the loop, so the room's shape lines up and doesn't drift."
            case .finish: "The room map lets your iPhone recognise the room later, to guide you there."
            }
        }

        /// How you know the step is done (it also moves on after a while, so nobody gets stuck).
        public var doneWhen: String {
            switch self {
            case .recognise: "Done when the room is recognised, or after 25 seconds."
            case .start: "Done when you have held still for a few seconds."
            case .turnAround: "Done when 11 of 12 directions are seen."
            case .alongWalls: "Done when walls are seen on 9 of 12 sides."
            case .sweepDown: "Done when enough floor and table tops are seen."
            case .returnToStart: "Done when you are back within 1 metre of the start."
            case .finish: "Done when the room map says ready; then press Stop."
            }
        }

        /// What to do, as shown on the step card: the spoken line.
        public var instruction: String { spoken }

        public var spoken: String {
            switch self {
            case .recognise: "Scanning again. Point the phone slowly around the room so I can recognise it."
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

    /// One step as it went: how long, and whether it was done or moved on after its time ran out.
    public struct StepRecord: Sendable, Equatable, Codable {
        public let step: Int  // Step.rawValue
        public let seconds: Double
        public let completed: Bool
        public let detail: String
        public init(step: Int, seconds: Double, completed: Bool, detail: String) {
            self.step = step; self.seconds = seconds; self.completed = completed; self.detail = detail
        }
        public var title: String { Step(rawValue: step)?.title ?? "Step" }
    }

    /// Where a step stands right now, for the card's meter: "Wall sides 5 of 9".
    public struct StepProgress: Sendable, Equatable {
        public let value: Double
        public let target: Double
        public let text: String
        public var fraction: Double { target > 0 ? min(1, value / target) : 0 }
    }

    public private(set) var step: Step
    public private(set) var records: [StepRecord] = []
    public private(set) var loopClosed = false
    public private(set) var mapReady = false
    private var stepStarted = 0.0

    /// `recognising`: a rescan, which first has to find the earlier scan's room.
    public init(recognising: Bool = false) { step = recognising ? .recognise : .start }

    /// Ends the recognise step: the room was found (this scan shares the earlier one's frame) or it wasn't (this
    /// scan starts fresh). Returns the line to say.
    public mutating func endRecognise(recognised: Bool, at t: Double) -> String {
        step = .start
        stepStarted = t
        return (recognised ? "Room recognised. " : "I couldn't recognise the room, so this scan starts fresh. ")
            + Step.start.spoken
    }

    /// Steps the scan on; returns a line to say when something changed (a new step, or the map becoming ready).
    public mutating func update(_ p: Progress) -> String? {
        let inStep = p.elapsed - stepStarted
        let met: Bool = switch step {
        case .recognise, .finish: false  // ended by endRecognise / by Stop
        case .start: inStep >= 4
        case .turnAround: p.directions >= 11
        case .alongWalls: p.walls >= 9
        case .sweepDown: p.floorSeenM2 >= Self.floorTarget(p)
        case .returnToStart: p.walkedM > 3 && p.fromStartM < 1.0
        }
        let timedOut: Bool = switch step {
        case .turnAround: inStep > 60
        case .alongWalls: inStep > 120
        case .sweepDown: inStep > 90
        case .returnToStart: inStep > 60
        default: false
        }
        if step == .returnToStart, met { loopClosed = true }
        if met || timedOut, let next = Step(rawValue: step.rawValue + 1) {
            let now = Self.progress(of: step, p)
            records.append(StepRecord(step: step.rawValue, seconds: inStep.rounded(), completed: met, detail: now.text))
            let missed = met || step == .start ? "" : "Moving on: \(now.text.prefix(1).lowercased() + now.text.dropFirst()). "
            step = next
            stepStarted = p.elapsed
            if next == .finish, p.map == .mapped {
                mapReady = true
                return missed + "Room map ready. Double tap Stop."
            }
            return missed + next.spoken
        }
        if step == .finish, !mapReady, p.map == .mapped {
            mapReady = true
            return "Room map ready. Double tap Stop."
        }
        return nil
    }
}


public extension ScanGuide {
    /// Floor and table tops to see in the sweep: 2.5 m², or half the area walked in a big room.
    static func floorTarget(_ p: Progress) -> Double { max(2.5, 0.5 * p.areaWalkedM2) }

    /// The meter for a step: what's measured against what's needed, in words.
    static func progress(of step: Step, _ p: Progress) -> StepProgress {
        switch step {
        case .recognise: return StepProgress(value: 0, target: 1, text: "Looking for the room")
        case .start: return StepProgress(value: min(p.elapsed, 4), target: 4, text: "Hold still")
        case .turnAround:
            return StepProgress(value: Double(p.directions), target: 11, text: "Directions seen \(min(p.directions, 12)) of 11")
        case .alongWalls:
            return StepProgress(value: Double(p.walls), target: 9, text: "Wall sides seen \(min(p.walls, 12)) of 9")
        case .sweepDown:
            let target = floorTarget(p)
            return StepProgress(value: p.floorSeenM2, target: target,
                                text: String(format: "Floor and tops seen %.1f of %.1f m²", p.floorSeenM2, target))
        case .returnToStart:
            // full when within a metre of the start; the meter fills as you come back
            return StepProgress(value: max(0, 4 - p.fromStartM), target: 3,
                                text: p.fromStartM < 1 ? "Back at the start" : String(format: "%.1f m from the start", p.fromStartM))
        case .finish:
            return StepProgress(value: p.map == .mapped ? 1 : p.map == .extending ? 0.6 : 0.3, target: 1,
                                text: p.map.spoken)
        }
    }

    /// The walls step's distance check: about 1 m from the wall is right.
    enum WallDistance: Equatable { case good, tooClose, tooFar }
    static func wallDistance(_ metres: Double) -> WallDistance {
        metres < 0.7 ? .tooClose : metres > 1.6 ? .tooFar : .good
    }
}

/// How high to hold the phone in each step, measured (camera height above the floor the LiDAR found), so nobody is
/// asked their own height: chest height for looking round and along the walls, waist height to sweep tables and floor.
public extension ScanGuide.Step {
    var phoneHeight: ClosedRange<Double> {
        switch self {
        case .sweepDown: 0.8...1.1
        default: 1.1...1.5
        }
    }

    /// "Chest height, 1.1 to 1.5 m"
    var heightLabel: String {
        let r = phoneHeight
        let name = self == .sweepDown ? "Waist height" : "Chest height"
        return String(format: "%@, %.1f to %.1f m", name, r.lowerBound, r.upperBound)
    }
}

/// Says "raise" or "lower" only after the phone has been out of the step's band for a while, and not too often.
public struct HeightCoach: Sendable {
    public enum Check: Equatable { case good, tooLow, tooHigh }

    public var after: Double = 3  // seconds out of the band before saying anything
    public var gap: Double = 12  // seconds between reminders
    private var outSince: Double?
    private var lastSaid = -Double.infinity

    public init() {}

    public static func check(_ height: Double, for step: ScanGuide.Step) -> Check {
        let r = step.phoneHeight
        return height < r.lowerBound ? .tooLow : height > r.upperBound ? .tooHigh : .good
    }

    /// The line to say now, if any. `height` nil: the floor isn't measured yet, so nothing to say.
    public mutating func update(t: Double, height: Double?, step: ScanGuide.Step) -> String? {
        guard let height, step != .recognise else { outSince = nil; return nil }
        let c = Self.check(height, for: step)
        guard c != .good else { outSince = nil; return nil }
        outSince = outSince ?? t
        guard t - outSince! >= after, t - lastSaid >= gap else { return nil }
        lastSaid = t
        let place = step == .sweepDown ? "waist height" : "chest height"
        return c == .tooLow ? "Raise the phone to \(place)." : "Lower the phone to \(place)."
    }
}

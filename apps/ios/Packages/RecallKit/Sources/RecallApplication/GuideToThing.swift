import Foundation
import RecallDomain

/// Walks the user to a thing: relocalise in the saved room map, ask the Mac for a route from here, then speak
/// clock-face turns and distances as the phone moves, re-planning when the user leaves the route, until the thing
/// is within reach. Without a map match (or a clear path) it says landmark directions only, and why.
@MainActor
public final class GuideToThing {
    public enum Phase: Equatable, Sendable {
        case locating
        case planning
        case guiding(RouteFollower.Cue, weakTracking: Bool)
        case landmarks(String)
        case arrived(String)
        case failed(String)

        public var isFinished: Bool {
            switch self {
            case .landmarks, .arrived, .failed: true
            default: false
            }
        }
    }

    public struct Settings: Sendable {
        public var locateTimeout: Double = 25  // seconds to look for a map match before landmark directions
        public var tick: Double = 0.4  // how often the pose is read while walking
        public var replanAfterMetres: Double = 1.5  // off the route by more than this → a new route
        public var maxReplans = 3
        public var faceTimeout: Double = 30  // seconds to turn towards a compass bearing
        public init() {}
    }

    public let home: String
    public let thing: Thing
    public private(set) var phase = Phase.locating { didSet { onChange(phase) } }
    public var onChange: (Phase) -> Void = { _ in }

    private let roomMap: Data?
    private let locator: any Locator
    private let guide: any GuideService
    private let speech: any SpeechOutput
    private let haptics: any HapticsOutput
    private let clock: any Clock
    private let compass: (any CompassSensor)?
    private let settings: Settings
    private var cancelled = false

    public init(home: String, thing: Thing, roomMap: Data?, locator: any Locator, guide: any GuideService,
                speech: any SpeechOutput, haptics: any HapticsOutput, clock: any Clock,
                compass: (any CompassSensor)? = nil, settings: Settings = .init()) {
        self.home = home; self.thing = thing; self.roomMap = roomMap; self.locator = locator; self.guide = guide
        self.speech = speech; self.haptics = haptics; self.clock = clock; self.compass = compass
        self.settings = settings
    }

    /// The compass heading when it can be trusted (else directions leave out "north-east").
    private var heading: Double? {
        guard let r = compass?.reading, r.isReliable else { return nil }
        return r.magneticDeg
    }

    /// Runs until arrival, landmark directions, a failure or `stop()`.
    public func run() async {
        compass?.start()
        let hasMap = roomMap != nil && locator.start(roomMap: roomMap)
        if !hasMap { _ = locator.start(roomMap: nil) }
        speech.say(hasMap ? "Finding where you are. Hold the phone up at chest height and turn slowly."
                          : "Finding your \(thing.title).", interrupt: true)
        let tracking = hasMap ? await locate() : .limited
        guard !cancelled else { return }
        if tracking == .normal { haptics.tap() }

        var replans = 0
        while !cancelled {
            guard let route = await plan(tracking: tracking) else { return }
            if tracking == .normal { locator.mark(route.target) }  // the arrow, only where the phone knows the room
            guard route.isWalkable else {
                locator.showPath([], floorY: nil)
                await landmarks(route)
                return
            }
            locator.showPath(route.waypoints, floorY: route.floorY)  // arrows on the floor, leading the way
            if let first = route.steps.first { speech.say(first.say, interrupt: true) }
            switch await follow(route) {
            case .done: return
            case .offRoute where replans < settings.maxReplans:
                replans += 1
                speech.say("You're off the route. Finding a new way.", interrupt: true)
            case .offRoute:
                finish(.failed("I keep losing the route. Your \(thing.title) is \(thing.place)."))
                return
            }
        }
    }

    public func stop() {
        cancelled = true
        locator.mark(nil)
        locator.showPath([], floorY: nil)
        locator.stop()
        compass?.stop()
        speech.stop()
    }

    /// Says the current instruction again (the Repeat button and the magic tap).
    public func repeatLast() {
        switch phase {
        case .locating: speech.say("Still finding where you are. Turn slowly.", interrupt: true)
        case .planning: speech.say("Planning the way.", interrupt: true)
        case .guiding(let cue, _): speech.say(Directions.say(cue, heading: heading), interrupt: true)
        case .landmarks(let t), .arrived(let t), .failed(let t): speech.say(t, interrupt: true)
        }
    }

    // MARK: steps

    /// Waits for tracking to turn normal (ARKit recognised the room) or the timeout.
    private func locate() async -> TrackingState {
        let started = clock.now()
        while !cancelled, clock.now().timeIntervalSince(started) < settings.locateTimeout {
            if locator.reading()?.tracking == .normal { return .normal }
            try? await clock.sleep(seconds: 0.3)
        }
        return .limited
    }

    private func plan(tracking: TrackingState) async -> Route? {
        phase = .planning
        let pose = tracking == .normal ? (locator.reading()?.pose ?? .identity) : .identity
        do {
            let route = try await guide.route(home: home, to: thing.id, from: pose, tracking: tracking)
            return cancelled ? nil : route
        } catch {
            if !cancelled { finish(.failed(UserMessage.explain(error))) }
            return nil
        }
    }

    private enum FollowEnd { case done, offRoute }

    private func follow(_ route: Route) async -> FollowEnd {
        var follower = RouteFollower(waypoints: route.waypoints)
        var throttle = CueThrottle()
        var lastTick = Date.distantPast
        var warnedWeak = false
        let arrive = route.arriveSay ?? "You should be at your \(thing.title)."
        while !cancelled {
            try? await clock.sleep(seconds: settings.tick)
            guard !cancelled, let reading = locator.reading() else { continue }
            guard reading.tracking == .normal else {
                // directions would be guesses: pause them, say why once
                if !warnedWeak {
                    warnedWeak = true
                    speech.say("Tracking is weak. Slow down and hold the phone up.", interrupt: true)
                    haptics.warning()
                }
                if case .guiding(let cue, _) = phase { phase = .guiding(cue, weakTracking: true) }
                continue
            }
            warnedWeak = false
            guard let cue = follower.update(position: reading.pose.position, forward: reading.pose.forward) else { continue }
            phase = .guiding(cue, weakTracking: false)
            if cue.arrived {
                locator.showPath([], floorY: nil)
                haptics.success()
                finish(.arrived(arrive))
                return .done
            }
            if cue.offRouteMetres > settings.replanAfterMetres { return .offRoute }
            let now = clock.now()
            if cue.clock == 12, now.timeIntervalSince(lastTick) > 1.5 {  // a tick while facing the right way
                haptics.tap()
                lastTick = now
            }
            if throttle.shouldSay(cue, at: now) { speech.say(Directions.say(cue, heading: heading), interrupt: true) }
        }
        return .done
    }

    /// Landmark directions; with the room's compass bearing and a reliable compass, the phone then ticks while the
    /// person faces the thing ("Your keys are to the north-east. Turn until I tick.").
    private func landmarks(_ route: Route) async {
        guard let bearing = route.bearingDeg, heading != nil else {
            finish(.landmarks(route.spokenSteps))
            return
        }
        let text = route.spokenSteps + " It's to the \(CompassMath.name(bearing)). Turn until I tick."
        phase = .landmarks(text)
        speech.say(text, interrupt: true)
        let started = clock.now()
        var facedSince: Date?
        while !cancelled, clock.now().timeIntervalSince(started) < settings.faceTimeout {
            try? await clock.sleep(seconds: settings.tick)
            guard let h = heading else { continue }
            if CompassMath.facing(h, bearing) {
                haptics.tap()
                if facedSince == nil { speech.say("That way.", interrupt: true) }
                facedSince = facedSince ?? clock.now()
                if let f = facedSince, clock.now().timeIntervalSince(f) >= 2 { break }  // held it: done
            } else {
                facedSince = nil
            }
        }
        locator.stop()
    }

    private func finish(_ end: Phase) {
        phase = end
        switch end {
        case .landmarks(let t), .arrived(let t), .failed(let t): speech.say(t, interrupt: true)
        default: break
        }
        locator.stop()
    }
}

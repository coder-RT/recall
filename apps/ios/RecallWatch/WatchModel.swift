import Foundation
import Observation
import RecallDomain

/// The Watch's flow: greet and listen → (or turn the crown and pick) → the iPhone answers with a compass route →
/// stand where the room's scan began → walk, led by taps → arrived. Every step is said aloud and tapped on the wrist,
/// so none of it needs looking at the screen.
@MainActor @Observable
final class WatchModel {
    enum Stage: Equatable {
        case greeting, listening, thinking
        case picking
        case ready(CompassRoute)
        case walking(CompassRoute)
        case arrived(CompassRoute)
        case message(String)
    }

    private(set) var stage = Stage.greeting
    private(set) var things: [WatchThing] = []
    /// the Digital Crown's position on the dial of things
    var dial: Double = 0 { didSet { dialMoved() } }
    /// the walk's current words, shown large ("Turn right", "Straight on, 3 metres")
    private(set) var step = ""

    private let voice = WatchVoice()
    private let recorder = WatchRecorder()
    private let sensors = WalkSensors()
    private let phone = PhoneLink()
    private var walk: CompassWalk?
    private var lastCue: CompassWalk.Cue?
    private var lastTap = Date.distantPast
    private var lastMetre = 0
    private var spokenIndex = -1
    /// simulator demo: things and a route from here, no iPhone (launch argument -WatchDemo)
    private let demo = ProcessInfo.processInfo.arguments.contains("-WatchDemo")

    var picked: WatchThing? {
        guard !things.isEmpty else { return nil }
        return things[min(things.count - 1, max(0, Int(dial.rounded())))]
    }

    func appeared() {
        phone.activate()
        loadThings()
        greet()
    }

    /// "Hi, I'm Recall. What should I find?" then listen (also what the double tap does when nothing is going on).
    func greet() {
        stopWalking()
        stage = .greeting
        voice.say("Hi, I'm Recall. What should I find? Say it, or turn the crown.") { [weak self] in self?.listen() }
    }

    private func listen() {
        guard stage == .greeting else { return }
        stage = .listening
        WristTaps.start()
        recorder.start { [weak self] url in
            guard let self, stage == .listening else { return }
            guard let url else {
                stage = .message("I didn't hear anything. Double tap to try again, or turn the crown.")
                voice.say("I didn't hear anything. Double tap to try again, or turn the crown.")
                return
            }
            stage = .thinking
            voice.say("Looking.")
            if demo { return answer(Self.demoReply) }
            phone.ask(audio: url) { [weak self] reply in self?.answer(reply) }
        }
    }

    private func loadThings() {
        if demo { things = Self.demoThings; return }
        phone.send(.things) { [weak self] reply in self?.things = reply.things ?? [] }
    }

    private func dialMoved() {
        guard !things.isEmpty, let thing = picked else { return }
        let i = things.firstIndex(of: thing) ?? 0
        if case .walking = stage { return }  // the crown doesn't change the thing mid-walk
        if recorder.isRecording { recorder.cancel() }
        stage = .picking
        guard i != spokenIndex else { return }
        spokenIndex = i
        voice.say(thing.title)  // the crown's own detent taps mark each step; the name says which
    }

    /// The main button / double tap: whatever the next step is.
    func primary() {
        switch stage {
        case .picking:
            guard let thing = picked else { return }
            stage = .thinking
            voice.say("Finding your \(thing.title).")
            if demo { return answer(Self.demoReply) }
            phone.send(.route(thingId: thing.id)) { [weak self] reply in self?.answer(reply) }
        case .ready(let route): startWalking(route)
        case .walking: voice.say(step)  // repeat the current step
        case .greeting, .listening, .thinking, .arrived, .message: greet()
        }
    }

    func stop() {
        stopWalking()
        recorder.cancel()
        voice.say("Stopped.")
        stage = .message("Stopped. Double tap to start again.")
    }

    private func answer(_ reply: WatchReply) {
        if let route = reply.route {
            stage = .ready(route)
            voice.say(reply.say ?? "Found it. Stand \(route.start), then double tap.")
        } else {
            let text = reply.say ?? "I couldn't find that."
            stage = .message(text)
            voice.say(text)
        }
    }

    private func startWalking(_ route: CompassRoute) {
        guard sensors.compassAvailable || demo else {
            stage = .message("This Watch has no compass reading yet. Move your wrist in a figure eight, then try again.")
            return
        }
        walk = CompassWalk(legs: route.legs)
        lastCue = nil
        lastMetre = 0
        stage = .walking(route)
        sensors.changed = { [weak self] in self?.reading() }
        sensors.start()
        voice.say("Let's go.")
    }

    private func stopWalking() {
        sensors.stop()
        sensors.changed = {}
        walk = nil
    }

    /// Each compass or pedometer reading: one cue, as a tap now and words when the kind of cue changes.
    private func reading() {
        guard var w = walk, case .walking(let route) = stage, let heading = sensors.heading else { return }
        let cue = w.update(heading: heading, metresWalked: sensors.metres)
        walk = w
        let leg = w.leg < route.legs.count ? route.legs[w.leg] : nil
        step = CompassWalk.say(cue, leg: leg)
        let changed = !Self.sameKind(cue, lastCue)
        lastCue = cue
        switch cue {
        case .turn(let side, let degrees):
            // the further off, the more often it taps (every 1.4 s far off, every 0.6 s when nearly there)
            let every = 0.6 + min(degrees, 90) / 90 * 0.8
            if Date.now.timeIntervalSince(lastTap) > every { WristTaps.turn(side); lastTap = .now }
            if changed { voice.say(step) }
        case .onCourse:
            if changed { WristTaps.facing(); voice.say(step) }
            let m = Int(sensors.metres)
            if m > lastMetre { lastMetre = m; WristTaps.metre() }
        case .nextLeg:
            WristTaps.nextLeg()
            voice.say(step)
        case .overshot:
            WristTaps.stop()
            if changed { voice.say(step) }
        case .arrived:
            stopWalking()
            WristTaps.arrived()
            stage = .arrived(route)
            voice.say("You're there. Your \(route.title): \(route.place).")
        }
    }

    private static func sameKind(_ a: CompassWalk.Cue, _ b: CompassWalk.Cue?) -> Bool {
        switch (a, b) {
        case (.turn(let x, _), .turn(let y, _)): x == y
        case (.onCourse, .onCourse), (.overshot, .overshot), (.arrived, .arrived): true
        default: false
        }
    }

    private static let demoThings = [
        WatchThing(id: "s1", title: "Beige keys", place: "near the desk, waist height"),
        WatchThing(id: "s2", title: "Grey bag", place: "near the desk, knee height"),
        WatchThing(id: "s6", title: "Brown wallet", place: "on the counter, waist height"),
    ]
    private static let demoReply = WatchReply(
        say: "Sample: your beige keys are near the desk, at waist height. Stand by the door, then double tap.",
        route: CompassRoute(thingId: "s1", label: "keys", color: "beige", start: "by the door", place: "near the desk, at waist height",
                            legs: [CompassLeg(bearing: 90, metres: 3), CompassLeg(bearing: 180, metres: 2)]))
}

import ARKit
import Observation
import RecallDomain
import RecallNetworking
import RecallVoice

/// Walks the user to an object: relocalise into the saved room map, ask the Mac for a route from here, then speak
/// clock-face turns and distances as the phone moves, until the object is within reach.
@MainActor @Observable
final class GuideModel {
    enum Phase: Equatable {
        case locating, planning
        case guiding(RouteFollower.Cue)
        case landmarks(String)  // only directions by landmark (no map match or no clear path)
        case arrived(String)
        case failed(String)
    }

    let target: GuideTarget
    let session = ARSession()
    private(set) var phase = Phase.locating
    private(set) var weakTracking = false
    private var follower: RouteFollower?
    private var arriveSay = ""
    private var loop: Task<Void, Never>?
    private var lastSpoken: (clock: Int, metres: Double, at: Date)?

    /// How long to look for a match with the saved map before falling back to landmark directions.
    static let locateTimeout: TimeInterval = 25

    init(target: GuideTarget) { self.target = target }

    func start(app: AppModel) {
        guard ARWorldTrackingConfiguration.isSupported else {
            phase = .failed("Directions need an iPhone that supports world tracking.")
            return
        }
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = []
        let map = app.roomMapURL.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: $0) }
        config.initialWorldMap = map
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        app.announcer.say(map == nil
            ? "Finding your \(target.title)."
            : "Finding where you are. Hold the phone up at chest height and turn slowly.", interrupt: true)
        loop = Task { [weak self] in await self?.run(app: app, hasMap: map != nil) }
    }

    func stop(app: AppModel) {
        loop?.cancel()
        session.pause()
        app.announcer.stop()
    }

    /// Says the current instruction again (the Repeat button and the magic tap).
    func repeatLast(app: AppModel) {
        switch phase {
        case .locating: app.announcer.say("Still finding where you are. Turn slowly.", interrupt: true)
        case .planning: app.announcer.say("Planning the way.", interrupt: true)
        case .guiding(let cue): app.announcer.say(Directions.say(cue), interrupt: true)
        case .landmarks(let text), .arrived(let text), .failed(let text): app.announcer.say(text, interrupt: true)
        }
    }

    private func run(app: AppModel, hasMap: Bool) async {
        // 1. relocalise: with a saved map, tracking turns normal once ARKit recognises the room
        let started = Date()
        var tracking = Tracking.limited
        while !Task.isCancelled, hasMap, Date().timeIntervalSince(started) < Self.locateTimeout {
            if case .normal = session.currentFrame?.camera.trackingState {
                tracking = .normal
                break
            }
            try? await Task.sleep(for: .milliseconds(300))
        }
        guard !Task.isCancelled, let api = app.api else {
            if app.api == nil { fail(app.setupProblem ?? "Set up the Mac in Settings first.", app: app) }
            return
        }
        if tracking == .normal { Haptics.tap() }
        // without a map the pose isn't in the scan's world, so only landmark directions are honest
        let pose = session.currentFrame?.camera.transform ?? matrix_identity_float4x4

        // 2. plan from here
        phase = .planning
        let route: Route
        do {
            route = try await api.startGuidance(homeId: app.homeId, objectId: target.id,
                                                pose: Self.columnMajor(pose), tracking: tracking)
        } catch {
            fail(APIError.explain(error), app: app)
            return
        }
        arriveSay = route.arriveSay ?? "You should be at your \(target.title)."
        guard !route.landmarksOnly, route.waypoints.count > 1 else {
            let text = route.steps.map(\.say).joined(separator: " ")
            phase = .landmarks(text)
            app.announcer.say(text, interrupt: true)
            session.pause()
            return
        }
        follower = RouteFollower(waypoints: route.waypoints)
        if let first = route.steps.first { app.announcer.say(first.say, interrupt: true) }

        // 3. follow: speak when the direction changes, the distance drops by a metre, or every few seconds
        var lastHaptic = Date.distantPast
        while !Task.isCancelled, var f = follower {
            try? await Task.sleep(for: .milliseconds(400))
            guard let frame = session.currentFrame else { continue }
            let t = frame.camera.transform
            weakTracking = { if case .normal = frame.camera.trackingState { false } else { true } }()
            let position = SIMD2(Double(t.columns.3.x), Double(t.columns.3.z))
            let forward = SIMD2(-Double(t.columns.2.x), -Double(t.columns.2.z))
            guard let cue = f.update(position: position, forward: forward) else { continue }
            follower = f
            phase = .guiding(cue)
            if cue.arrived {
                Haptics.success()
                phase = .arrived(arriveSay)
                app.announcer.say(arriveSay, interrupt: true)
                session.pause()
                return
            }
            if cue.clock == 12, Date().timeIntervalSince(lastHaptic) > 1.5 {  // a tick while facing the right way
                Haptics.tap()
                lastHaptic = Date()
            }
            speakIfChanged(cue, app: app)
        }
    }

    private func speakIfChanged(_ cue: RouteFollower.Cue, app: AppModel) {
        let now = Date()
        if let last = lastSpoken, last.clock == cue.clock, last.metres - cue.metres < 1, now.timeIntervalSince(last.at) < 6 {
            return
        }
        lastSpoken = (cue.clock, cue.metres, now)
        app.announcer.say(Directions.say(cue), interrupt: true)
    }

    private func fail(_ message: String, app: AppModel) {
        phase = .failed(message)
        app.announcer.say(message, interrupt: true)
        session.pause()
    }

    /// The camera-to-world transform as 16 numbers in column order, as the API's Pose expects.
    static func columnMajor(_ m: simd_float4x4) -> [Double] {
        [m.columns.0, m.columns.1, m.columns.2, m.columns.3].flatMap { [Double($0.x), Double($0.y), Double($0.z), Double($0.w)] }
    }
}

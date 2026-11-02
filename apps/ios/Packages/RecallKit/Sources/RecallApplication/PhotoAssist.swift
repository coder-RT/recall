import Foundation
import RecallDomain

/// Helps ARKit recognise the room, never replaces it: while ARKit hasn't matched the saved room map, about once a
/// second one camera photo goes to the Mac's photo matcher (classic features + PnP, no model). From its answers:
/// - the room is somewhere else → said once ("You seem to be in Bedroom, not Living room…");
/// - what to point at → said every few seconds ("Point the phone slowly at the TV.");
/// - two fixes in a row that agree → the locator takes the correction and tracking reads normal at once.
/// The moment ARKit matches by itself it stops asking. No Mac, or an error: nothing is said and ARKit carries on.
@MainActor
public final class PhotoAssist {
    public struct Settings: Sendable {
        public var firstAfter: Double = 1.0  // ARKit often matches within a second: then nothing is sent
        public var every: Double = 1.0  // the Mac answers in about 35 ms; one photo a second is plenty
        public var maxAsks = 40
        public var hintEvery: Double = 8  // seconds between "point at …" lines
        public init() {}
    }

    private let home: String
    private let scan: String
    private let room: String?
    private let locator: any Locator
    private let places: any PlaceLocating
    private let speech: any SpeechOutput
    private let clock: any Clock
    private let settings: Settings
    private var cancelled = false

    /// Whether a photo fix (not ARKit) located the phone.
    public private(set) var fixed = false

    public init(home: String, scan: String, room: String?, locator: any Locator, places: any PlaceLocating,
                speech: any SpeechOutput, clock: any Clock, settings: Settings = .init()) {
        self.home = home; self.scan = scan; self.room = room; self.locator = locator; self.places = places
        self.speech = speech; self.clock = clock; self.settings = settings
    }

    public func cancel() { cancelled = true }

    private var located: Bool { locator.reading()?.tracking == .normal }

    /// Until the room is recognised (by ARKit or two agreeing fixes), `cancel()` or the ask limit.
    public func run() async {
        try? await clock.sleep(seconds: settings.firstAfter)
        var agreement = FixAgreement()
        var turn = 0
        var lastHint: Date?
        var toldElsewhere = false
        for _ in 0..<settings.maxAsks {
            guard !cancelled, !located else { return }
            if let frame = locator.arrivalFrame(),
               let fix = try? await places.locate(home: home, scan: scan, room: room, frame: frame) {
                guard !cancelled, !located else { return }
                if let found = fix.room, let room, found != room {
                    if !toldElsewhere {
                        speech.say(LocateCoaching.elsewhere(found: found, wanted: room), interrupt: true)
                        toldElsewhere = true
                    }
                } else if lastHint.map({ clock.now().timeIntervalSince($0) >= settings.hintEvery }) ?? true,
                          let line = LocateCoaching.point(at: fix.hint, turn: turn) {
                    speech.say(line, interrupt: false)
                    turn += 1
                    lastHint = clock.now()
                }
                if let pose = fix.pose {
                    let session = Pose(columnMajor: frame.pose)
                    if let agreed = agreement.add(MapCorrection.between(map: pose, session: session), session: session) {
                        locator.correct(mapFromSession: Pose(columnMajor: MapCorrection.columnMajor(agreed)))
                        fixed = true
                        return
                    }
                }
            }
            try? await clock.sleep(seconds: settings.every)
        }
    }
}

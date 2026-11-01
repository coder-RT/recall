import Foundation

/// One line of the Mac's audit log, as the owner reads it about robots and other agents.
public struct AuditEntry: Sendable, Equatable, Identifiable {
    public let id: String
    public let at: Date
    public let actor: String  // owner, robot, pipeline, unknown
    public let action: String
    public let outcome: String  // ok, refused, failed
    public let detail: [String: String]

    public init(id: String, at: Date, actor: String, action: String, outcome: String, detail: [String: String] = [:]) {
        self.id = id; self.at = at; self.actor = actor; self.action = action; self.outcome = outcome; self.detail = detail
    }

    /// The entries about robots and other agents (robot access, map reads, questions, refused keys).
    public var isAboutRobots: Bool {
        ["robot_access.changed", "robot_export.read", "home_memory.query", "auth.refused"].contains(action)
    }

    public var refused: Bool { outcome != "ok" }

    /// "A robot asked for keys: answered", "You turned robot access on", "Refused: a wrong key".
    public var summary: String {
        let who = actor == "owner" ? "You" : actor == "robot" ? "A robot" : "Someone without a key"
        switch action {
        case "robot_access.changed":
            return "You turned robot access \(detail["on"] == "true" ? "on" : "off")"
        case "robot_export.read":
            if refused { return "\(who) tried to read the map: refused, robot access was off" }
            return actor == "owner" ? "You exported the robot map" : "A robot read the map of \(detail["room"] ?? "the room")"
        case "home_memory.query":
            if refused {
                switch detail["screen"] {
                case "structure": return "\(who) sent something other than an object name: refused"
                case "injection": return "\(who) sent a name that looked like an instruction: refused"
                case "invalid", "unavailable": return "\(who) asked, but the safety check couldn't run: refused"
                default: return "\(who) asked while robot access was off: refused"
                }
            }
            let what = detail["asked"] ?? "something"
            return detail["found"] == "true" ? "\(who) asked for \(what): answered" : "\(who) asked for \(what): not found"
        case "scan.erased":
            return "You erased a scan of \(detail["room"] ?? "a room") from the Mac"
        case "auth.refused":
            return "Refused: \(detail["why"] ?? "no valid key") (\(detail["path"] ?? "a request"))"
        case "trust.changed":
            return "You set how sure Recall must be to \(detail["level"] ?? "a new level")"
        case "scan.created":
            return "You started uploading a scan of \(detail["room"] ?? "a room")"
        case "scan.uploaded":
            return refused ? "A scan upload failed its check: \(detail["why"] ?? "damaged")"
                           : "Your scan of \(detail["room"] ?? "a room") arrived; the Mac is processing it"
        case "scan.failed":
            return "The Mac couldn't process a scan of \(detail["room"] ?? "a room")"
        case "scan.ingested":
            return "The Mac remembered a scan of \(detail["room"] ?? "a room")"
        case "object.corrected":
            return "You corrected \(detail["label"] ?? "a thing")"
        case "object.forgotten":
            return "You said \(detail["label"] ?? "a thing") isn't there"
        case "arrival.verified":
            return "The camera checked you'd reached a thing"
        case "guide.answered":
            return refused ? "Your question couldn't reach the Guide's model" : "Your question went to the Guide's model"
        case "voice.transcribed":
            return refused ? "Your voice couldn't reach Muse Voice Transcribe"
                           : "Your voice went to Muse Voice Transcribe (not kept)"
        case "audit.pruned":
            return "The Mac dropped \(detail["dropped"] ?? "some") events past the keeping period"
        default:
            return action
        }
    }
}

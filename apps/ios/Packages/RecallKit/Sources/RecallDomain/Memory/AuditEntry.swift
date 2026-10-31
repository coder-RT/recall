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
                return detail["screen"] == "attack" ? "\(who) sent a message that looked like an attack: refused"
                    : "\(who) asked while robot access was off: refused"
            }
            let what = detail["asked"] ?? "something"
            return detail["found"] == "true" ? "\(who) asked for \(what): answered" : "\(who) asked for \(what): not found"
        case "auth.refused":
            return "Refused: \(detail["why"] ?? "no valid key") (\(detail["path"] ?? "a request"))"
        default:
            return action
        }
    }
}

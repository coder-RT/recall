import Foundation

/// One thing that leaves the Mac: what, to whom (and which model), and when. `onThisMac` when a local model keeps it home.
public struct DataFlow: Sendable, Equatable, Identifiable {
    public let what: String
    public let to: String
    public let when: String
    public let onThisMac: Bool
    public var id: String { what }

    public init(what: String, to: String, when: String, onThisMac: Bool = false) {
        self.what = what; self.to = to; self.when = when; self.onThisMac = onThisMac
    }
}

/// What the Mac keeps and sends where, under its current settings (GET /privacy).
public struct PrivacyStatus: Sendable, Equatable {
    public let storedOn: String
    public let sent: [DataFlow]
    public let robotAccess: Bool
    public let auditDays: Int

    public init(storedOn: String, sent: [DataFlow], robotAccess: Bool, auditDays: Int) {
        self.storedOn = storedOn; self.sent = sent; self.robotAccess = robotAccess; self.auditDays = auditDays
    }

    /// "Robot Access is off: robots get nothing." or what they may read.
    public var robotLine: String {
        robotAccess ? "Robot Access is on: robots with the robot key can read the map, things and furniture, never photos."
            : "Robot Access is off: robots get nothing."
    }
}

/// The privacy note's fixed text, the same as docs/privacy.md and the website's /privacy page.
public enum PrivacyNote {
    public static let short = "Your home's memory lives on your own Mac. There is no Recall account and no Recall "
        + "server: nobody else holds your scans or your memory. Some steps use Meta's models online, and this page "
        + "says exactly what they receive."

    public static let kept = [
        "On your Mac: every scan you upload (photos, LiDAR depth, the phone's path), the 3D map, the things and "
            + "furniture found, your own names and notes, and the activity log.",
        "On your iPhone: your scans until you delete them, the room map used to find your way, and the Mac's "
            + "address. The device key is in the Keychain.",
        "Between them: your home network, or an encrypted tunnel you set up (Tailscale or Cloudflare Tunnel). "
            + "Every request needs the device key.",
    ]

    public static let never = [
        "No account, no ads, no analytics, no tracking in the app, and nothing sold.",
        "No Recall server receives your home: the developer never sees your scans, your memory or your questions.",
        "Robots never get photos, your own names or notes for things, or anyone's position.",
    ]

    public static let controls: [(title: String, detail: String)] = [
        ("Delete a scan", "In Scans, hold a scan and choose Delete. It goes from your iPhone and your Mac, with its "
            + "photos and the things only it found."),
        ("Forget a thing", "In Found, open a thing and choose \"Not there, forget it\"."),
        ("Robot Access", "Off by default. Every robot request is in the activity log."),
        ("Private mode", "Run the Guide on Muse Glimmer on your Mac (LM Studio), so your questions stay home. Scans "
            + "and voice still use Meta's online models."),
    ]

    public static let theirTerms = "These services process what they receive under their own terms; Recall doesn't "
        + "claim how long they keep it."
}

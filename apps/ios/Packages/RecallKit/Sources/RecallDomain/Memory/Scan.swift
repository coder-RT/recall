import Foundation

/// Where a scan's upload and processing stand.
public enum UploadState: Sendable, Equatable {
    case notUploaded
    case preparing
    case uploading(fraction: Double)
    case finishing
    case processing
    case processed
    case failed(reason: String)

    /// The stage without its details, to tell a real change (worth saying aloud) from progress.
    public var stage: String {
        switch self {
        case .notUploaded: "local"
        case .preparing: "preparing"
        case .uploading: "uploading"
        case .finishing: "finishing"
        case .processing: "processing"
        case .processed: "processed"
        case .failed: "failed"
        }
    }

    /// The status line under a scan.
    public var description: String {
        switch self {
        case .notUploaded: "Only on this iPhone."
        case .preparing: "Preparing the upload…"
        case .uploading(let f): "Uploading, \(Int(f * 100)) percent"
        case .finishing: "Checking the upload…"
        case .processing: "Uploaded. The Mac is processing it."
        case .processed: "Processed. Ready to ask about."
        case .failed(let why): "Upload failed. \(why)"
        }
    }
}

/// A room the phone has scanned: an aggregate whose upload state only moves through `apply`.
public struct Scan: Identifiable, Sendable, Equatable {
    public let id: String
    public var room: String
    public var createdAt: Date
    public var grade: ScanGrade
    public var directions: Int
    public var frames: Int
    public private(set) var state: UploadState
    /// A rescan: the earlier scan whose room map the phone recognised, so both share one frame.
    public var alignedTo: String?
    /// What the Mac found different after this rescan.
    public var changes: [ScanChange] = []
    /// Scanned before but not recognised: the Mac started this room's memory afresh.
    public var fresh = false

    public init(id: String, room: String, createdAt: Date, grade: ScanGrade, directions: Int, frames: Int,
                state: UploadState = .notUploaded, alignedTo: String? = nil) {
        self.id = id; self.room = room; self.createdAt = createdAt; self.grade = grade
        self.directions = directions; self.frames = frames; self.state = state; self.alignedTo = alignedTo
    }

    /// A rescan whose results are in: "What changed" applies.
    public var showsChanges: Bool { isProcessed && (alignedTo != nil || fresh || !changes.isEmpty) }

    /// An upload can start when the scan is only local or the last try failed.
    public var canUpload: Bool {
        switch state {
        case .notUploaded, .failed: true
        default: false
        }
    }

    /// What deleting this scan reaches: only this phone, the phone and the Mac, or nothing yet (the Mac is busy).
    public enum DeleteReach: Sendable, Equatable { case phoneOnly, phoneAndMac, waitForMac }

    public var deleteReach: DeleteReach {
        switch state {
        case .notUploaded: .phoneOnly
        case .preparing, .uploading, .finishing, .processing: .waitForMac
        case .processed, .failed: .phoneAndMac  // a failed upload may have left parts on the Mac too
        }
    }

    public var isProcessed: Bool { state == .processed }
    public var isProcessing: Bool { state == .processing }

    /// Moves to `next`; true when the stage changed (so the change is worth announcing).
    @discardableResult
    public mutating func apply(_ next: UploadState) -> Bool {
        let changed = next.stage != state.stage
        state = next
        return changed
    }
}

/// The Mac's processing status for a scan.
public enum ScanStatus: String, Sendable { case uploading, uploaded, processing, processed, failed }

/// What the Mac says about a scan: its status, why it failed, and (for a rescan) what changed.
public struct ScanReport: Sendable, Equatable {
    public let status: ScanStatus
    public let detail: String?
    public let changes: [ScanChange]
    public let fresh: Bool

    public init(_ status: ScanStatus, detail: String? = nil, changes: [ScanChange] = [], fresh: Bool = false) {
        self.status = status; self.detail = detail; self.changes = changes; self.fresh = fresh
    }
}

// scans.json keeps the shape older builds wrote (uploadPhase, uploadDetail, uploadFraction), both ways
extension Scan: Codable {
    enum CodingKeys: String, CodingKey {
        case id, room, createdAt, grade, directions, frames, uploadPhase, uploadDetail, uploadFraction, alignedTo, changes, fresh
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        room = try c.decode(String.self, forKey: .room)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        grade = try c.decode(ScanGrade.self, forKey: .grade)
        directions = try c.decode(Int.self, forKey: .directions)
        frames = try c.decode(Int.self, forKey: .frames)
        let phase = try c.decodeIfPresent(String.self, forKey: .uploadPhase)
        let detail = try c.decodeIfPresent(String.self, forKey: .uploadDetail)
        let fraction = try c.decodeIfPresent(Double.self, forKey: .uploadFraction) ?? 0
        alignedTo = try c.decodeIfPresent(String.self, forKey: .alignedTo)
        changes = try c.decodeIfPresent([ScanChange].self, forKey: .changes) ?? []
        fresh = try c.decodeIfPresent(Bool.self, forKey: .fresh) ?? false
        state = switch phase {
        case "preparing": .preparing
        case "uploading": .uploading(fraction: fraction)
        case "finishing": .finishing
        case "processing": .processing
        case "processed": .processed
        case "failed": .failed(reason: detail ?? "")
        default: .notUploaded
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(room, forKey: .room)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(grade, forKey: .grade)
        try c.encode(directions, forKey: .directions)
        try c.encode(frames, forKey: .frames)
        if state != .notUploaded { try c.encode(state.stage, forKey: .uploadPhase) }
        if case .failed(let why) = state { try c.encode(why, forKey: .uploadDetail) }
        if case .uploading(let f) = state { try c.encode(f, forKey: .uploadFraction) }
        try c.encodeIfPresent(alignedTo, forKey: .alignedTo)
        if !changes.isEmpty { try c.encode(changes, forKey: .changes) }
        if fresh { try c.encode(fresh, forKey: .fresh) }
    }
}

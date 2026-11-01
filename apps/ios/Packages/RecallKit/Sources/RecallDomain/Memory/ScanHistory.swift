import Foundation

/// A room's newest processed scan, which holds its memory now, and the processed scans before it: its history.
public struct RoomScans: Identifiable, Sendable, Equatable {
    public let latest: Scan
    public internal(set) var earlier: [Scan]  // newest first

    public var id: String { latest.id }

    /// The scan that came right after `scan` in this room ("Replaced by the scan on 1 Nov").
    public func successor(of scan: Scan) -> Scan? {
        let all = [latest] + earlier
        guard let i = all.firstIndex(where: { $0.id == scan.id }), i > 0 else { return nil }
        return all[i - 1]
    }
}

public enum ScanHistory {
    /// One card per room, newest first. Only processed scans fold under a newer processed scan of the same room;
    /// one still uploading, processing or failed keeps its own card, so its progress and Retry stay in sight.
    /// Room names match whatever their case and spacing ("Living room" and "living room ").
    public static func byRoom(_ scans: [Scan]) -> [RoomScans] {
        var out: [RoomScans] = []
        var current: [String: Int] = [:]  // room → its card in `out`
        for scan in scans.sorted(by: { $0.createdAt > $1.createdAt }) {
            let room = scan.room.trimmingCharacters(in: .whitespaces).lowercased()
            if scan.isProcessed, let i = current[room] {
                out[i].earlier.append(scan)
                continue
            }
            if scan.isProcessed { current[room] = out.count }
            out.append(RoomScans(latest: scan, earlier: []))
        }
        return out
    }
}

import Foundation
import RecallDomain

/// The Mac takes a minute or so per scan. This asks about every scan still processing and says when one is ready:
/// "Living room is ready. 10 things found, 4 to check." After a rescan it says what changed instead: "Living room is
/// ready. 2 changes: your beige keys moved from near the desk to on the shelf. Gone: your grey bag."
@MainActor
public struct TrackProcessing {
    private let processing: any ScanProcessing
    private let memory: any HomeMemory
    private let speech: any SpeechOutput

    public init(processing: any ScanProcessing, memory: any HomeMemory, speech: any SpeechOutput) {
        self.processing = processing; self.memory = memory; self.speech = speech
    }

    /// What changed for one scan: its new state, and for a processed rescan what the Mac found different.
    public struct Outcome: Sendable, Equatable {
        public let state: UploadState
        public let changes: [ScanChange]
        public let fresh: Bool
        public init(_ state: UploadState, changes: [ScanChange] = [], fresh: Bool = false) {
            self.state = state; self.changes = changes; self.fresh = fresh
        }
    }

    /// The scans whose state changed (unreachable Macs change nothing).
    public func callAsFunction(_ scans: [Scan], home: String) async -> [String: Outcome] {
        var out: [String: Outcome] = [:]
        for scan in scans where scan.isProcessing {
            guard let report = try? await processing.status(scan: scan.id) else { continue }
            switch report.status {
            case .processed:
                out[scan.id] = Outcome(.processed, changes: report.changes, fresh: report.fresh)
                let things = (try? await memory.things(home: home)) ?? []
                speech.say(Self.announce(scan, report: report, things: things), interrupt: false)
            case .failed:
                out[scan.id] = Outcome(.failed(reason: report.detail ?? "The Mac couldn't process this scan."))
                speech.say("Processing \(scan.room) failed. The reason is on the scan.", interrupt: false)
            default:
                break
            }
        }
        return out
    }

    /// A rescan says what changed; a first scan (or a fresh start) says how much was found.
    static func announce(_ scan: Scan, report: ScanReport, things: [Thing]) -> String {
        if report.fresh {
            return "I didn't recognise \(scan.room), so its memory started afresh. " + ready(scan.room, things: things)
        }
        if scan.alignedTo != nil || !report.changes.isEmpty {
            return ChangeSummary.say(room: scan.room, changes: report.changes)
        }
        return ready(scan.room, things: things)
    }

    static func ready(_ room: String, things: [Thing]) -> String {
        let unsure = things.filter(\.needsReview).count
        let found = things.count == 1 ? "1 thing found" : "\(things.count) things found"
        return "\(room) is ready. \(found)" + (unsure > 0 ? ", \(unsure) to check." : ".")
    }
}

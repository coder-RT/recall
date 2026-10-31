import Foundation
import RecallDomain

/// The Mac takes a few minutes per scan. This asks about every scan still processing and says when one is ready:
/// "Living room is ready. 10 things found, 4 to check."
@MainActor
public struct TrackProcessing {
    private let processing: any ScanProcessing
    private let memory: any HomeMemory
    private let speech: any SpeechOutput

    public init(processing: any ScanProcessing, memory: any HomeMemory, speech: any SpeechOutput) {
        self.processing = processing; self.memory = memory; self.speech = speech
    }

    /// The new states of the scans that changed (unreachable Macs change nothing).
    public func callAsFunction(_ scans: [Scan], home: String) async -> [String: UploadState] {
        var changes: [String: UploadState] = [:]
        for scan in scans where scan.isProcessing {
            guard let (status, detail) = try? await processing.status(scan: scan.id) else { continue }
            switch status {
            case .processed:
                changes[scan.id] = .processed
                let things = (try? await memory.things(home: home)) ?? []
                speech.say(Self.ready(scan.room, things: things), interrupt: false)
            case .failed:
                changes[scan.id] = .failed(reason: detail ?? "The Mac couldn't process this scan.")
                speech.say("Processing \(scan.room) failed. The reason is on the scan.", interrupt: false)
            default:
                break
            }
        }
        return changes
    }

    static func ready(_ room: String, things: [Thing]) -> String {
        let unsure = things.filter(\.needsReview).count
        let found = things.count == 1 ? "1 thing found" : "\(things.count) things found"
        return "\(room) is ready. \(found)" + (unsure > 0 ? ", \(unsure) to check." : ".")
    }
}

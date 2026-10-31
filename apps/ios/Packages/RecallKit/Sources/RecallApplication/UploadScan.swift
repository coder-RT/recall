import Foundation
import RecallDomain

/// Starts a scan's upload to the Mac (it carries on in the background; progress arrives through ScanUploading).
@MainActor
public struct UploadScan {
    private let files: any EpisodeFiles
    private let uploads: any ScanUploading
    private let server: any ScanServer
    private let speech: any SpeechOutput

    public init(files: any EpisodeFiles, uploads: any ScanUploading, server: any ScanServer, speech: any SpeechOutput) {
        self.files = files; self.uploads = uploads; self.server = server; self.speech = speech
    }

    /// Throws when the Mac isn't set up or the scan's files are incomplete; does nothing for a scan already sent.
    public func callAsFunction(_ scan: Scan, connection: Connection) throws {
        if let issue = connection.issue { throw RecallError.setup(issue) }
        guard scan.canUpload else { return }
        guard let manifest = files.manifest(scan: scan.id) else { throw RecallError.incompleteScan }
        speech.say("Uploading \(scan.room).", interrupt: false)
        let (dir, home, uploads, server) = (files.directory(scan: scan.id), connection.homeId, uploads, server)
        Task { await uploads.upload(scan: scan.id, home: home, room: scan.room, episode: dir, manifest: manifest, server: server) }
    }
}

import CryptoKit
import Foundation

/// The episode folder as one zip (made by the system's own "for uploading" coordination: no third-party zip code),
/// split into parts of about 8 MB, each with its SHA-256.
public struct EpisodeArchive: Sendable {
    public struct Part: Sendable, Codable { public let number: Int; public let file: URL; public let size: Int; public let sha256: String }

    public let zip: URL
    public let size: Int
    public let sha256: String
    public let parts: [Part]

    public static let partSize = 8 * 1024 * 1024

    /// Builds (or reuses) `<episode>.zip` and its parts next to the episode folder.
    public static func make(episode: URL) throws -> EpisodeArchive {
        let fm = FileManager.default
        let zip = episode.deletingLastPathComponent().appending(path: episode.lastPathComponent + ".zip")
        let partsDir = episode.deletingLastPathComponent().appending(path: episode.lastPathComponent + ".parts")
        if !fm.fileExists(atPath: zip.path) {
            var coordError: NSError?
            var copyError: Error?
            NSFileCoordinator().coordinate(readingItemAt: episode, options: .forUploading, error: &coordError) { tmp in
                do { try fm.copyItem(at: tmp, to: zip) } catch { copyError = error }
            }
            if let e = coordError ?? copyError { throw e }
            try? fm.removeItem(at: partsDir)
        }
        let size = (try fm.attributesOfItem(atPath: zip.path)[.size] as? NSNumber)?.intValue ?? 0
        try fm.createDirectory(at: partsDir, withIntermediateDirectories: true)
        let handle = try FileHandle(forReadingFrom: zip)
        defer { try? handle.close() }
        var whole = SHA256()
        var parts: [Part] = []
        var n = 1
        while let chunk = try handle.read(upToCount: partSize), !chunk.isEmpty {
            whole.update(data: chunk)
            let file = partsDir.appending(path: String(format: "%05d.bin", n))
            if !fm.fileExists(atPath: file.path) { try chunk.write(to: file, options: .atomic) }
            parts.append(Part(number: n, file: file, size: chunk.count, sha256: hex(SHA256.hash(data: chunk))))
            n += 1
        }
        return EpisodeArchive(zip: zip, size: size, sha256: hex(whole.finalize()), parts: parts)
    }

    static func hex<D: Digest>(_ d: D) -> String { d.map { String(format: "%02x", $0) }.joined() }
}

import Foundation

/// Zips a folder with the system's own archiver (NSFileCoordinator .forUploading), as the scan upload does.
public enum FolderZip {
    /// Writes `files` into `<directory>/<name>/` and returns `<directory>/<name>.zip` (rebuilt each time).
    public static func make(name: String, files: [String: Data], in directory: URL) throws -> URL {
        let fm = FileManager.default
        let folder = directory.appending(path: name)
        let zip = directory.appending(path: name + ".zip")
        try? fm.removeItem(at: folder)
        try? fm.removeItem(at: zip)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        for (file, data) in files { try data.write(to: folder.appending(path: file), options: .atomic) }
        var coordError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &coordError) { tmp in
            do { try fm.copyItem(at: tmp, to: zip) } catch { copyError = error }
        }
        if let e = coordError ?? copyError { throw e }
        return zip
    }
}

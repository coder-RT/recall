import RecallDesign
import RecallDomain
import SwiftUI
import UniformTypeIdentifiers

/// "Share for robots": one tap opens the share sheet (AirDrop, Save to Files, Mail…); the Mac makes the room's
/// package only once a place is picked, so nothing is fetched just by showing the button.
struct RobotPackageShare: View {
    let room: String?
    var title = "Share for robots"
    @Environment(\.container) private var container
    @Environment(SettingsModel.self) private var settings

    var body: some View {
        if let container {
            let source = container.robotPackages(), home = settings.connection.homeId, room = room
            ShareLink(item: RobotPackageFile(room: room, fetch: { try await source.robotPackage(home: home, room: room) }),
                      preview: SharePreview("\(room ?? "Room") for robots", image: Image(systemName: "shippingbox"))) {
                Label(title, systemImage: "square.and.arrow.up")
            }
            .buttonStyle(SolidPillStyle(fill: Tokens.card, text: Tokens.accent, edge: Tokens.line, compact: true))
            .accessibilityHint("Sends this room's map, things, outline and 3D points to a robot, with AirDrop, Files or Mail.")
        }
    }
}

/// The room's .zip, written to a temporary file when the share sheet asks for it.
struct RobotPackageFile: Transferable {
    let room: String?
    let fetch: @Sendable () async throws -> Data

    var fileName: String {
        let slug = (room ?? "room").lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return "recall-\(String(slug)).zip"
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .zip) { file in
            let url = FileManager.default.temporaryDirectory.appending(path: file.fileName)
            try await file.fetch().write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

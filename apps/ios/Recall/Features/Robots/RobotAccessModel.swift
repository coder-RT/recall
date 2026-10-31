import Foundation
import Observation
import RecallDomain
import RecallUpload

/// Robot Access: the owner's switch on the Mac, and the robot map package to share (a .zip for ROS 2 / Nav2).
@MainActor @Observable
final class RobotAccessModel {
    private(set) var status: RobotAccessStatus?
    private(set) var package: RobotMapPackage?
    /// The newest audit entries about robots (map reads, questions, refusals, the switch).
    private(set) var activity: [AuditEntry] = []
    private(set) var zip: URL?
    private(set) var busy = false
    private(set) var error: String?

    private let sharing: any RobotSharing
    private let settings: SettingsModel
    private let speech: any SpeechOutput

    init(sharing: any RobotSharing, settings: SettingsModel, speech: any SpeechOutput) {
        self.sharing = sharing; self.settings = settings; self.speech = speech
    }

    func load() async {
        await run {
            status = try await sharing.robotAccess()
            package = try? await sharing.robotMap(home: settings.connection.homeId)
            await refreshActivity()
            zip = nil
        }
    }

    func turn(_ on: Bool) async {
        await run {
            status = try await sharing.setRobotAccess(on)
            await refreshActivity()
            speech.say(on ? "Robot access is on. Robots with your robot key can find things in your home."
                          : "Robot access is off. Robots can't read your home's memory.", interrupt: true)
        }
    }

    /// Builds the .zip for the share sheet (map.pgm, map.yaml, objects.json, room.json).
    func prepareExport() async {
        await run {
            let p = try await sharing.robotMap(home: settings.connection.homeId)
            package = p
            zip = try FolderZip.make(name: p.name, files: p.files, in: FileManager.default.temporaryDirectory)
        }
    }

    private func refreshActivity() async {
        activity = Array(((try? await sharing.activity(limit: 50)) ?? []).filter(\.isAboutRobots).prefix(10))
    }

    private func run(_ work: () async throws -> Void) async {
        busy = true
        defer { busy = false }
        do {
            try await work()
            error = nil
        } catch {
            self.error = UserMessage.explain(error)
        }
    }
}

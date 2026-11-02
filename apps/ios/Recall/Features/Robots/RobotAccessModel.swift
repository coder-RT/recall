import Foundation
import Observation
import RecallDomain

/// Robot Access: the owner's switch on the Mac, the room's map preview and recent robot activity. The package
/// itself comes from the Mac (RobotPackageShare).
@MainActor @Observable
final class RobotAccessModel {
    private(set) var status: RobotAccessStatus?
    private(set) var package: RobotMapPackage?
    /// The newest audit entries about robots (map reads, questions, refusals, the switch).
    private(set) var activity: [AuditEntry] = []
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

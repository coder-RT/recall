import Foundation
import Observation
import RecallDomain

/// How sure Recall must be before it tells you about a thing (Settings). The level lives on the Mac; this shows it
/// and changes it. Until it's loaded, or with no Mac, nothing is shown as chosen.
@MainActor @Observable
final class TrustModel {
    private(set) var level: TrustLevel?
    private(set) var error: String?

    private let source: any TrustSettings

    init(source: any TrustSettings) { self.source = source }

    func load() async {
        do {
            level = try await source.trustLevel()
            error = nil
        } catch {
            self.error = UserMessage.explain(error)
        }
    }

    func choose(_ next: TrustLevel) async {
        let was = level
        level = next  // at once, so the choice doesn't jump back while the Mac answers
        do {
            level = try await source.setTrustLevel(next)
            error = nil
        } catch {
            level = was
            self.error = UserMessage.explain(error)
        }
    }
}

import ARKit
import SceneKit
import Observation
import RecallApplication
import RecallDomain

/// The guide screen's state: the GuideToThing use case's phase, and the camera session for a sighted helper.
@MainActor @Observable
final class GuideModel {
    private(set) var phase = GuideToThing.Phase.locating
    let session: ARSession
    /// The arrow over the thing, drawn on the camera feed.
    let scene: SCNScene
    let thing: Thing
    private let guide: GuideToThing
    private let supported: Bool
    private var task: Task<Void, Never>?

    init(guide: GuideToThing, session: ARSession, scene: SCNScene, supported: Bool) {
        self.guide = guide; self.session = session; self.scene = scene; self.supported = supported; thing = guide.thing
        guide.onChange = { [weak self] in self?.phase = $0 }
    }

    func start() {
        guard supported else {
            phase = .failed("Directions need an iPhone that supports world tracking.")
            return
        }
        task = Task { await guide.run() }
    }

    func stop() {
        task?.cancel()
        guide.stop()
    }

    func repeatLast() { guide.repeatLast() }
}

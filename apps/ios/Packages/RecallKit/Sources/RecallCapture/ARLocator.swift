import ARKit
import RecallDomain

/// The Locator port on ARKit: our own world-tracking session started from the saved ARWorldMap (no scene
/// reconstruction, no plane classification). Once ARKit recognises the room, tracking turns normal and the camera's
/// pose is in the scan's world, where the Mac plans routes.
@MainActor
public final class ARLocator: Locator {
    /// The session, for a camera view a sighted helper can watch.
    public let session = ARSession()

    public init() {}

    public static var isSupported: Bool { ARWorldTrackingConfiguration.isSupported }

    public func start(roomMap: Data?) -> Bool {
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = []
        var readable = true
        if let roomMap {
            if let map = try? NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: roomMap) {
                config.initialWorldMap = map
            } else {
                readable = false
            }
        }
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        return readable
    }

    public func stop() { session.pause() }

    public func reading() -> (pose: Pose, tracking: TrackingState)? {
        guard let camera = session.currentFrame?.camera else { return nil }
        let m = camera.transform
        let pose = Pose(columnMajor: [m.columns.0, m.columns.1, m.columns.2, m.columns.3]
            .flatMap { [Double($0.x), Double($0.y), Double($0.z), Double($0.w)] })
        return (pose, CaptureSession.tracking(camera.trackingState).0)
    }
}

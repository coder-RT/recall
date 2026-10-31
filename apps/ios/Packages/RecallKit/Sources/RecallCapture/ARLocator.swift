import ARKit
import RecallDomain
import SceneKit
import UIKit

/// The Locator port on ARKit: our own world-tracking session started from the saved ARWorldMap (no scene
/// reconstruction, no plane classification). Once ARKit recognises the room, tracking turns normal and the camera's
/// pose is in the scan's world, where the Mac plans routes.
@MainActor
public final class ARLocator: Locator {
    /// The session, for a camera view a sighted helper can watch.
    public let session = ARSession()
    /// What the camera view draws over the feed: the arrow above the thing.
    public let scene = SCNScene()
    private var arrow: SCNNode?

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

    public func mark(_ target: SIMD3<Double>?) {
        arrow?.removeFromParentNode()
        arrow = nil
        guard let target else { return }
        let node = Self.arrowNode()
        node.simdPosition = SIMD3(Float(target.x), Float(target.y) + 0.08, Float(target.z))  // tip just above the thing
        if !UIAccessibility.isReduceMotionEnabled {
            let up = SCNAction.moveBy(x: 0, y: 0.05, z: 0, duration: 0.8)
            up.timingMode = .easeInEaseOut
            node.runAction(.repeatForever(.sequence([up, up.reversed()])))
        }
        scene.rootNode.addChildNode(node)
        arrow = node
    }

    /// A Facebook-blue (#3b5998) arrow pointing down, its tip at the node's origin, with a white edge, turning about
    /// the vertical to face the camera.
    static func arrowNode() -> SCNNode {
        let root = SCNNode()
        let head = SCNCone(topRadius: 0.07, bottomRadius: 0, height: 0.12)
        let shaft = SCNCylinder(radius: 0.025, height: 0.16)
        for (geometry, y) in [(head as SCNGeometry, Float(0.06)), (shaft, 0.2)] {
            let blue = SCNMaterial()
            blue.lightingModel = .constant
            blue.diffuse.contents = UIColor(red: 0x3b / 255, green: 0x59 / 255, blue: 0x98 / 255, alpha: 1)
            geometry.materials = [blue]
            let part = SCNNode(geometry: geometry)
            part.simdPosition.y = y
            // the white edge: the same shape a little larger, drawn from the inside
            let edge = SCNNode(geometry: geometry.copy() as? SCNGeometry)
            let white = SCNMaterial()
            white.lightingModel = .constant
            white.diffuse.contents = UIColor.white
            white.cullMode = .front
            edge.geometry?.materials = [white]
            edge.simdScale = SIMD3(repeating: 1.15)
            part.addChildNode(edge)
            root.addChildNode(part)
        }
        let face = SCNBillboardConstraint()
        face.freeAxes = .Y
        root.constraints = [face]
        root.name = "recall.arrow"
        return root
    }

    public func reading() -> (pose: Pose, tracking: TrackingState)? {
        guard let camera = session.currentFrame?.camera else { return nil }
        let m = camera.transform
        let pose = Pose(columnMajor: [m.columns.0, m.columns.1, m.columns.2, m.columns.3]
            .flatMap { [Double($0.x), Double($0.y), Double($0.z), Double($0.w)] })
        return (pose, CaptureSession.tracking(camera.trackingState).0)
    }
}

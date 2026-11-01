import RecallDomain
import SceneKit
import UIKit

/// The LiDAR points captured so far, painted where they are in the room: green dots grow over every surface the scan
/// has seen, so a helper (or the video) sees what's covered. Real depth samples, no model.
@MainActor
final class PointPaint {
    let scene = SCNScene()
    private let node = SCNNode()
    private(set) var trail = PointTrail()

    init() { scene.rootNode.addChildNode(node) }

    func add(_ points: [SIMD3<Float>]) {
        guard !points.isEmpty else { return }
        trail.add(points)
        let vertices = trail.points.map { SCNVector3($0.x, $0.y, $0.z) }
        let source = SCNGeometrySource(vertices: vertices)
        let element = SCNGeometryElement(indices: Array(0..<Int32(vertices.count)), primitiveType: .point)
        element.pointSize = 6
        element.minimumPointScreenSpaceRadius = 2
        element.maximumPointScreenSpaceRadius = 5
        let geometry = SCNGeometry(sources: [source], elements: [element])
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = UIColor(red: 0x42 / 255, green: 0xb7 / 255, blue: 0x2a / 255, alpha: 0.85)  // cta green
        geometry.materials = [m]
        node.geometry = geometry
    }
}

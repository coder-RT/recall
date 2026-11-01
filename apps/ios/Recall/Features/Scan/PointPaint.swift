import RecallDomain
import SceneKit
import UIKit

/// The LiDAR points captured so far, painted where they are in the room: green dots grow over every surface the scan
/// has seen, so a helper (or the video) sees what's covered. Real depth samples, no model.
@MainActor
final class PointPaint {
    let scene = SCNScene()
    private let node = SCNNode()
    private let grid = SCNNode()
    private(set) var trail = PointTrail()
    private var drawnZones = -1

    init() {
        scene.rootNode.addChildNode(node)
        scene.rootNode.addChildNode(grid)
    }

    /// The zone grid in light neon blue: for each 1 m column the scan reached, a square at each height-band edge
    /// (0.3, 0.7, 1.1, 1.5 m: knee, waist, chest, head) and posts at its corners. Lines around zones the LiDAR has seen
    /// glow; the rest stay faint, so the gaps show. Redrawn only when something new was seen.
    func showGrid(_ zones: ZoneCoverage, floorY: Float?, visible: Bool) {
        grid.isHidden = !visible
        guard visible, let floorY, zones.zonesSeen != drawnZones else { return }
        drawnZones = zones.zonesSeen
        var bright: [SCNVector3] = [], faint: [SCNVector3] = []
        let c = ZoneCoverage.column
        for (col, bands) in zones.seen {
            let x0 = Float(col.x) * c, z0 = Float(col.z) * c
            let corners = [(x0, z0), (x0 + c, z0), (x0 + c, z0 + c), (x0, z0 + c)]
            for (i, edge) in ZoneCoverage.edges.dropLast().enumerated() {
                // the ring at the bottom of band i: bright once that band was seen in this column
                let y = floorY + edge + 0.002
                for k in 0..<4 {
                    let a = corners[k], b = corners[(k + 1) % 4]
                    let seg = [SCNVector3(a.0, y, a.1), SCNVector3(b.0, y, b.1)]
                    if bands.contains(i) { bright += seg } else { faint += seg }
                }
            }
            for (x, z) in corners {
                faint += [SCNVector3(x, floorY, z), SCNVector3(x, floorY + ZoneCoverage.edges[4], z)]
            }
        }
        grid.childNodes.forEach { $0.removeFromParentNode() }
        grid.addChildNode(Self.lines(bright, alpha: 0.9))
        grid.addChildNode(Self.lines(faint, alpha: 0.25))
    }

    private static func lines(_ points: [SCNVector3], alpha: CGFloat) -> SCNNode {
        guard !points.isEmpty else { return SCNNode() }
        let element = SCNGeometryElement(indices: Array(0..<Int32(points.count)), primitiveType: .line)
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: points)], elements: [element])
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = UIColor(red: 0.49, green: 0.98, blue: 1.0, alpha: alpha)  // light neon blue
        m.isDoubleSided = true
        g.materials = [m]
        return SCNNode(geometry: g)
    }

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

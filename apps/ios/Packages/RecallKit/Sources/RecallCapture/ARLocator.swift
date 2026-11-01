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
    private let track = SCNNode()
    private let tags = SCNNode()
    private var shown: [ArLabel] = []

    public init() {
        scene.rootNode.addChildNode(track)
        scene.rootNode.addChildNode(tags)
    }

    public static var isSupported: Bool { ARWorldTrackingConfiguration.isSupported }

    /// The map the session runs (or last ran) with, decoded once: starting again with the same map resumes the
    /// session instead of throwing away what ARKit has already recognised.
    private var current: (data: Data, map: ARWorldMap)?
    private var running = false
    private var runningWithMap = false

    /// Starts recognising the room before anyone asks to go (Find's answer is being read out); a guide that starts
    /// soon after finds the session already matched. A no-op when it is already running with this map.
    @discardableResult
    public func prepare(roomMap: Data?) -> Bool { start(roomMap: roomMap) }

    public func start(roomMap: Data?) -> Bool {
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = []
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics = [.sceneDepth]  // LiDAR depth, for the arrival check's one frame
        }
        guard let roomMap else {
            if running, !runningWithMap { return true }
            session.run(config, options: [.resetTracking, .removeExistingAnchors])
            running = true; runningWithMap = false
            return true
        }
        if let current, current.data == roomMap {
            if running, runningWithMap { return true }  // already matching (or matched) this room
            if runningWithMap {
                // paused after a guide: resume, keeping what was recognised (ARKit relocalises itself if needed).
                // TODO(verify) on the iPhone how quickly tracking returns to normal after a resume.
                session.run(config, options: [])
            } else {
                config.initialWorldMap = current.map
                session.run(config, options: [.resetTracking, .removeExistingAnchors])
            }
            running = true; runningWithMap = true
            return true
        }
        guard let map = try? NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: roomMap) else {
            return false
        }
        current = (roomMap, map)
        config.initialWorldMap = map
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        running = true; runningWithMap = true
        return true
    }

    /// Pauses (keeping what ARKit recognised, so the next guide resumes quickly).
    public func stop() {
        session.pause()
        running = false
    }

    private let encoder = FrameEncoder()

    public func arrivalFrame() -> ArrivalFrame? {
        guard let frame = session.currentFrame, let depth = frame.sceneDepth?.depthMap,
              let (jpeg, size) = encoder.jpeg(frame.capturedImage) else { return nil }
        // ARKit's intrinsics are for the full camera image; the JPEG is scaled to a 1024-pixel long edge
        let s = Double(size.width) / Double(frame.camera.imageResolution.width)
        let k = frame.camera.intrinsics
        let pose = frame.camera.transform.columnMajor.map(Double.init)
        guard let (mm, w, h) = Self.millimetres(depth) else { return nil }
        return ArrivalFrame(jpeg: jpeg, depthMM: mm, depthSize: (w, h), imageSize: (Int(size.width), Int(size.height)),
                            intrinsics: (Double(k.columns.0.x) * s, Double(k.columns.1.y) * s,
                                         Double(k.columns.2.x) * s, Double(k.columns.2.y) * s), pose: pose)
    }

    /// Float32 metres to unsigned 16-bit little-endian millimetres, row by row (0 where there is no depth).
    static func millimetres(_ depth: CVPixelBuffer) -> (Data, Int, Int)? {
        CVPixelBufferLockBaseAddress(depth, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depth, .readOnly) }
        guard CVPixelBufferGetPixelFormatType(depth) == kCVPixelFormatType_DepthFloat32,
              let base = CVPixelBufferGetBaseAddress(depth) else { return nil }
        let w = CVPixelBufferGetWidth(depth), h = CVPixelBufferGetHeight(depth), row = CVPixelBufferGetBytesPerRow(depth)
        var mm = [UInt16](repeating: 0, count: w * h)
        for y in 0..<h {
            let line = base.advanced(by: y * row).assumingMemoryBound(to: Float32.self)
            for x in 0..<w {
                let m = line[x]
                mm[y * w + x] = m.isFinite && m > 0 ? UInt16(min(65535, (m * 1000).rounded())).littleEndian : 0
            }
        }
        return (mm.withUnsafeBytes { Data($0) }, w, h)
    }

    /// Whether the session is running at the moment (a prepared locator nobody used is paused after a while).
    public var isRunning: Bool { running }

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

    /// Labels over everything found: a tag (its picture, made by the caller) 35 cm above each thing, facing the camera,
    /// a line down to the thing and a ring on the floor under it, in the label's colour.
    public func showLabels(_ items: [(label: ArLabel, tag: UIImage)], floorY: Double?) {
        clearLabels()
        shown = items.map(\.label)
        let still = UIAccessibility.isReduceMotionEnabled
        for (i, item) in items.enumerated() {
            let p = item.label.position
            let colour = Self.colour(item.label.mark)
            let node = SCNNode()
            node.simdPosition = SIMD3(Float(p.x), Float(p.y), Float(p.z))

            let height: Float = 0.35
            let width = Float(item.tag.size.width / item.tag.size.height) * 0.09
            let plane = SCNPlane(width: CGFloat(width), height: 0.09)
            let face = SCNMaterial()
            face.lightingModel = .constant
            face.diffuse.contents = item.tag
            face.isDoubleSided = true
            face.readsFromDepthBuffer = false  // the tag stays readable in front of furniture
            plane.materials = [face]
            let tag = SCNNode(geometry: plane)
            tag.simdPosition.y = height
            tag.constraints = [SCNBillboardConstraint()]
            tag.renderingOrder = 10
            node.addChildNode(tag)

            let line = SCNCylinder(radius: 0.003, height: CGFloat(height - 0.045))
            line.materials = [Self.flat(colour)]
            let lineNode = SCNNode(geometry: line)
            lineNode.simdPosition.y = (height - 0.045) / 2
            node.addChildNode(lineNode)

            let dot = SCNSphere(radius: 0.015)
            dot.materials = [Self.flat(colour)]
            node.addChildNode(SCNNode(geometry: dot))

            if let floorY {
                let ring = SCNTorus(ringRadius: 0.12, pipeRadius: 0.006)
                ring.materials = [Self.flat(colour.withAlphaComponent(0.85))]
                let ringNode = SCNNode(geometry: ring)
                ringNode.simdPosition.y = Float(floorY - p.y) + 0.005
                node.addChildNode(ringNode)
            }
            if !still {
                node.opacity = 0
                node.runAction(.sequence([.wait(duration: 0.12 * Double(i)), .fadeIn(duration: 0.35)]))
            }
            tags.addChildNode(node)
        }
    }

    public func clearLabels() {
        tags.childNodes.forEach { $0.removeFromParentNode() }
        shown = []
    }

    /// The label the camera points at most directly (within 25°), for "what's this?".
    public func labelInView() -> ArLabel? {
        guard let cam = session.currentFrame?.camera.transform else { return nil }
        let eye = SIMD3<Double>(Double(cam.columns.3.x), Double(cam.columns.3.y), Double(cam.columns.3.z))
        let fwd = -SIMD3<Double>(Double(cam.columns.2.x), Double(cam.columns.2.y), Double(cam.columns.2.z))
        let scored = shown.map { label -> (ArLabel, Double) in
            let to = simd_normalize(label.position - eye)
            return (label, acos(max(-1, min(1, simd_dot(to, simd_normalize(fwd))))) * 180 / .pi)
        }
        return scored.filter { $0.1 < 25 }.min { $0.1 < $1.1 }?.0
    }

    public static func colour(_ mark: ArLabel.Mark) -> UIColor {
        switch mark {
        case .told: UIColor(red: 0x42 / 255, green: 0xb7 / 255, blue: 0x2a / 255, alpha: 1)  // cta green
        case .check: UIColor(red: 0xf2 / 255, green: 0xb3 / 255, blue: 0x3d / 255, alpha: 1)  // amber
        case .seenOnce: UIColor(red: 0xe5 / 255, green: 0x48 / 255, blue: 0x3a / 255, alpha: 1)  // red
        }
    }

    private static func flat(_ colour: UIColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = colour
        return m
    }

    public func showPath(_ path: [SIMD2<Double>], floorY: Double?) {
        track.childNodes.forEach { $0.removeFromParentNode() }
        let chevrons = ChevronLayout.place(path: path)
        guard !chevrons.isEmpty else { return }
        // without the floor from the Mac, assume the phone is held about 1.4 m above it
        let y = Float(floorY ?? Double((session.currentFrame?.camera.transform.columns.3.y ?? 1.4) - 1.4)) + 0.01
        let still = UIAccessibility.isReduceMotionEnabled
        for (i, c) in chevrons.enumerated() {
            let node = Self.chevronNode()
            node.simdPosition = SIMD3(Float(c.position.x), y, Float(c.position.y))
            node.eulerAngles.y = Float(-c.yawDeg * .pi / 180)  // ARKit yaw is clockwise from above; SceneKit's isn't
            if !still {
                // the racing "chase": a bright wave runs forward along the arrows
                node.opacity = 0.35
                let pulse = SCNAction.sequence([.fadeOpacity(to: 1, duration: 0.2), .fadeOpacity(to: 0.35, duration: 0.6),
                                                .wait(duration: 0.4)])
                node.runAction(.sequence([.wait(duration: Double(i) * 0.1), .repeatForever(pulse)]))
            }
            track.addChildNode(node)
        }
    }

    /// One floor arrow: a light-blue chevron with a soft Facebook-blue glow around it, lying flat and pointing along
    /// the node's −z (the way to walk).
    static func chevronNode() -> SCNNode {
        let root = SCNNode()
        let outline = UIBezierPath()
        for (k, p) in [(-0.18, -0.06), (0, 0.12), (0.18, -0.06), (0.18, -0.15), (0, 0.03), (-0.18, -0.15)].enumerated() {
            let pt = CGPoint(x: p.0, y: p.1)
            if k == 0 { outline.move(to: pt) } else { outline.addLine(to: pt) }
        }
        outline.close()
        let shape = SCNShape(path: outline, extrusionDepth: 0)
        for (colour, scale, order, glow) in [(UIColor(red: 0x3b / 255, green: 0x59 / 255, blue: 0x98 / 255, alpha: 1), Float(1.35), 20, true),
                                             (UIColor(red: 0xa9 / 255, green: 0xc4 / 255, blue: 1, alpha: 1), 1, 21, false)] {
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.diffuse.contents = colour
            m.isDoubleSided = true
            m.writesToDepthBuffer = false
            if glow { m.blendMode = .add; m.transparency = 0.7 }
            let g = shape.copy() as? SCNGeometry
            g?.materials = [m]
            let part = SCNNode(geometry: g)
            part.eulerAngles.x = -.pi / 2  // the shape's +y (its point) to −z, its face up
            part.simdScale = SIMD3(repeating: scale)
            part.renderingOrder = order
            root.addChildNode(part)
        }
        root.name = "recall.chevron"
        return root
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

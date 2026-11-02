import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo

/// What the camera looks like in the scan and AR views: the plain camera, the LiDAR depth as heat, or edges like a
/// scanner. Classic image processing (Core Image); no model sees the pictures.
public enum CameraLook: String, CaseIterable, Sendable {
    case camera, lidar, edges

    public var title: String {
        switch self {
        case .camera: "Camera"
        case .lidar: "LiDAR"
        case .edges: "Edges"
        }
    }

    public var hint: String {
        switch self {
        case .camera: "The plain camera."
        case .lidar: "The LiDAR's distance as colour: warm is near, cool is far, with the points already captured."
        case .edges: "The camera drawn as edges, like a scanner."
        }
    }
}

/// Renders the overlays from one ARKit frame, small and fast (about 10 times a second is plenty for a layer).
public final class ScannerFilter: @unchecked Sendable {
    private let context = CIContext(options: [.cacheIntermediates: false])
    public init() {}

    /// The camera image as glowing pale-blue edges on near-black, portrait, `longEdge` pixels on its long side.
    public func edges(_ image: CVPixelBuffer, longEdge: CGFloat = 480) -> CGImage? {
        let input = scaled(CIImage(cvPixelBuffer: image).oriented(.right), longEdge: longEdge)
        let edges = CIFilter.edges()
        edges.inputImage = input
        edges.intensity = 6
        guard let e = edges.outputImage else { return nil }
        // grey edges → the site's pale blue (#dfe3ee) glow; everything else stays dark
        let mono = CIFilter.maximumComponent()
        mono.inputImage = e
        let tint = CIFilter.colorMatrix()
        tint.inputImage = mono.outputImage
        tint.rVector = CIVector(x: 0.87, y: 0, z: 0, w: 0)
        tint.gVector = CIVector(x: 0, y: 0.89, z: 0, w: 0)
        tint.bVector = CIVector(x: 0, y: 0, z: 0.93, w: 0)
        tint.biasVector = CIVector(x: 0.02, y: 0.03, z: 0.06, w: 0)
        guard let out = tint.outputImage else { return nil }
        return context.createCGImage(out, from: input.extent)
    }

    /// LiDAR depth as heat: warm near, cool far (0.3 to 4 m), portrait; pixels with no depth are clear.
    public func heat(_ depth: CVPixelBuffer) -> CGImage? {
        let d = CIImage(cvPixelBuffer: depth).oriented(.right)
        // depth (metres) → 0...1, near = 1
        let norm = CIFilter.colorMatrix()
        norm.inputImage = d
        let k: CGFloat = -1 / 3.7
        norm.rVector = CIVector(x: k, y: 0, z: 0, w: 0)
        norm.gVector = CIVector(x: k, y: 0, z: 0, w: 0)
        norm.bVector = CIVector(x: k, y: 0, z: 0, w: 0)
        norm.biasVector = CIVector(x: 1 + 0.3 / 3.7, y: 1 + 0.3 / 3.7, z: 1 + 0.3 / 3.7, w: 0)
        norm.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        let colours = CIFilter.falseColor()
        colours.inputImage = norm.outputImage?.clampedToExtent().cropped(to: d.extent)
        colours.color0 = CIColor(red: 0.16, green: 0.28, blue: 0.49)  // far: fb-blue-dark
        colours.color1 = CIColor(red: 0.95, green: 0.45, blue: 0.2)  // near: warm
        guard let out = colours.outputImage else { return nil }
        return context.createCGImage(out, from: d.extent)
    }

    private func scaled(_ image: CIImage, longEdge: CGFloat) -> CIImage {
        let s = longEdge / max(image.extent.width, image.extent.height)
        guard s < 1 else { return image }
        return image.transformed(by: CGAffineTransform(scaleX: s, y: s))
    }
}

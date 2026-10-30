import Accelerate
import CoreImage
import CoreVideo
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Pixel work for one keyframe: JPEG, 16-bit millimetre depth PNG, confidence PNG and a sharpness score.
/// Everything runs on the capture queue; no buffer outlives the call.
final class FrameEncoder: @unchecked Sendable {
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let longEdge: CGFloat

    init(longEdge: CGFloat = 1024) { self.longEdge = longEdge }

    /// JPEG of the camera image scaled so its long edge is `longEdge`, kept in the sensor's landscape orientation so the
    /// scaled intrinsics stay valid. Returns the data and the output size.
    func jpeg(_ buffer: CVPixelBuffer, quality: CGFloat = 0.85) -> (Data, CGSize)? {
        let image = CIImage(cvPixelBuffer: buffer)
        let scale = longEdge / max(image.extent.width, image.extent.height)
        let scaled = image.applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1.0])
        let rect = CGRect(x: 0, y: 0, width: (image.extent.width * scale).rounded(), height: (image.extent.height * scale).rounded())
        let cropped = scaled.cropped(to: rect)
        let options = [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality]
        guard let data = context.jpegRepresentation(of: cropped, colorSpace: colorSpace, options: options) else { return nil }
        return (data, rect.size)
    }

    /// Variance of the Laplacian of the luma plane, downscaled to about 480 px wide. Higher is sharper.
    func sharpness(_ buffer: CVPixelBuffer) -> Float {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard CVPixelBufferGetPlaneCount(buffer) >= 1, let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return 0 }
        var src = vImage_Buffer(data: base, height: vImagePixelCount(CVPixelBufferGetHeightOfPlane(buffer, 0)),
                                width: vImagePixelCount(CVPixelBufferGetWidthOfPlane(buffer, 0)),
                                rowBytes: CVPixelBufferGetBytesPerRowOfPlane(buffer, 0))
        let w = 480, h = Int(Double(src.height) * 480 / Double(src.width))
        guard var small = try? vImage_Buffer(width: w, height: h, bitsPerPixel: 8),
              var smallF = try? vImage_Buffer(width: w, height: h, bitsPerPixel: 32),
              var lap = try? vImage_Buffer(width: w, height: h, bitsPerPixel: 32) else { return 0 }
        defer { small.free(); smallF.free(); lap.free() }
        vImageScale_Planar8(&src, &small, nil, vImage_Flags(kvImageNoFlags))
        vImageConvert_Planar8toPlanarF(&small, &smallF, 255, 0, vImage_Flags(kvImageNoFlags))
        let kernel: [Float] = [0, 1, 0, 1, -4, 1, 0, 1, 0]
        vImageConvolve_PlanarF(&smallF, &lap, nil, 0, 0, kernel, 3, 3, 0, vImage_Flags(kvImageEdgeExtend))
        let count = w * h
        var mean: Float = 0, std: Float = 0
        // rows may be padded: copy row by row into a contiguous array first
        var values = [Float](repeating: 0, count: count)
        for row in 0..<h {
            let rowPtr = lap.data.advanced(by: row * lap.rowBytes).assumingMemoryBound(to: Float.self)
            values.withUnsafeMutableBufferPointer { dst in
                dst.baseAddress!.advanced(by: row * w).update(from: rowPtr, count: w)
            }
        }
        vDSP_normalize(values, 1, nil, 1, &mean, &std, vDSP_Length(count))
        return std * std
    }

    /// ARKit scene depth (Float32 metres) as a 16-bit PNG in millimetres (0 = no depth). Returns data and size.
    func depthPNG(_ depth: CVPixelBuffer) -> (Data, CGSize)? {
        CVPixelBufferLockBaseAddress(depth, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depth, .readOnly) }
        let w = CVPixelBufferGetWidth(depth), h = CVPixelBufferGetHeight(depth)
        guard let base = CVPixelBufferGetBaseAddress(depth) else { return nil }
        let rowBytes = CVPixelBufferGetBytesPerRow(depth)
        var mm = [UInt16](repeating: 0, count: w * h)
        for y in 0..<h {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: Float32.self)
            for x in 0..<w {
                let m = row[x]
                mm[y * w + x] = m.isFinite && m > 0 ? UInt16(min(65535, (m * 1000).rounded())) : 0
            }
        }
        return png(mm.withUnsafeBytes { Data($0) }, width: w, height: h, bits: 16).map { ($0, CGSize(width: w, height: h)) }
    }

    /// ARKit's depth confidence (0 low, 1 medium, 2 high) as an 8-bit PNG.
    func confidencePNG(_ conf: CVPixelBuffer) -> Data? {
        CVPixelBufferLockBaseAddress(conf, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(conf, .readOnly) }
        let w = CVPixelBufferGetWidth(conf), h = CVPixelBufferGetHeight(conf)
        guard let base = CVPixelBufferGetBaseAddress(conf) else { return nil }
        let rowBytes = CVPixelBufferGetBytesPerRow(conf)
        var out = Data(count: w * h)
        out.withUnsafeMutableBytes { dst in
            for y in 0..<h { dst.baseAddress!.advanced(by: y * w).copyMemory(from: base.advanced(by: y * rowBytes), byteCount: w) }
        }
        return png(out, width: w, height: h, bits: 8)
    }

    private func png(_ pixels: Data, width: Int, height: Int, bits: Int) -> Data? {
        let info: CGBitmapInfo = bits == 16 ? [CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), .byteOrder16Little]
                                            : CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
        guard let provider = CGDataProvider(data: pixels as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: bits, bitsPerPixel: bits,
                                  bytesPerRow: width * bits / 8, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: info,
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }
}

enum Hash {
    static func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}

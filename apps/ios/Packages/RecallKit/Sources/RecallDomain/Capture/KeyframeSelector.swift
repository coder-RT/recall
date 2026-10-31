import simd

/// Keep a frame when the phone moved about 15 cm or turned about 10° since the last kept frame.
public struct KeyframeSelector: Sendable {
    public var minTranslation: Float
    public var minRotationDegrees: Float
    public var minInterval: Double
    /// After this long without a view, a small move (5 cm or 5°) is enough, so the views have no gaps.
    public var gapInterval: Double
    private var last: (pose: simd_float4x4, t: Double)?

    public init(minTranslation: Float = 0.15, minRotationDegrees: Float = 10, minInterval: Double = 0.2,
                gapInterval: Double = 1.5) {
        self.minTranslation = minTranslation; self.minRotationDegrees = minRotationDegrees; self.minInterval = minInterval
        self.gapInterval = gapInterval
    }

    /// Seconds since the last kept view (0 before the first).
    public func since(_ t: Double) -> Double { last.map { t - $0.t } ?? 0 }

    /// Whether this pose is far enough from the last kept one. Call `accept` when the frame was actually kept
    /// (a blurry frame is not kept, so the next sharp one still qualifies).
    public func qualifies(_ pose: simd_float4x4, at t: Double) -> Bool {
        guard let last else { return true }
        if t - last.t < minInterval { return false }
        let moved = simd_distance(pose.columns.3.xyz, last.pose.columns.3.xyz)
        let turned = Self.angleDegrees(last.pose, pose)
        if t - last.t >= gapInterval { return moved >= 0.05 || turned >= 5 }
        return moved >= minTranslation || turned >= minRotationDegrees
    }

    public mutating func accept(_ pose: simd_float4x4, at t: Double) { last = (pose, t) }

    /// Rotation between two camera orientations, in degrees.
    public static func angleDegrees(_ a: simd_float4x4, _ b: simd_float4x4) -> Float {
        let ra = simd_quatf(simd_float3x3(a.columns.0.xyz, a.columns.1.xyz, a.columns.2.xyz))
        let rb = simd_quatf(simd_float3x3(b.columns.0.xyz, b.columns.1.xyz, b.columns.2.xyz))
        let d = simd_mul(rb, ra.inverse)
        let w = min(1, abs(d.real))
        return 2 * acos(w) * 180 / .pi
    }
}

extension simd_float4 {
    public var xyz: simd_float3 { simd_float3(x, y, z) }
}

extension simd_float4x4 {
    /// Column-major floats, the layout poses.jsonl uses.
    public var columnMajor: [Float] {
        [columns.0, columns.1, columns.2, columns.3].flatMap { [$0.x, $0.y, $0.z, $0.w] }
    }

    /// How far the camera looks above level, in degrees (negative: tilted down).
    public var pitchDegrees: Float {
        let f = -columns.2.xyz
        return asin(max(-1, min(1, f.y))) * 180 / .pi
    }

    /// The camera's horizontal heading in degrees (0 to 360) on the floor plane. ARKit: y is up, the camera looks along −Z.
    public var headingDegrees: Float {
        let f = -columns.2.xyz
        let deg = atan2(f.x, -f.z) * 180 / .pi
        return deg < 0 ? deg + 360 : deg
    }
}

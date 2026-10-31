import simd

/// Running numbers for the live metrics: directions covered, speed, tracking quality, light, area walked.
public struct CoverageTracker: Sendable {
    public private(set) var sectors = Set<Int>()
    public private(set) var samples = 0
    public private(set) var normalSamples = 0
    public private(set) var speedSum = 0.0
    public private(set) var peakSpeed = 0.0
    public private(set) var lightSum = 0.0
    public private(set) var lightSamples = 0
    private var path: [SIMD2<Float>] = []
    private var last: (position: simd_float3, heading: Float, t: Double)?

    public init() {}

    /// Returns (speed m/s, turn rate °/s) for the SpeedCoach.
    @discardableResult
    public mutating func add(pose: simd_float4x4, t: Double, tracking: TrackingState, lux: Double?) -> (Double, Double) {
        samples += 1
        if tracking == .normal { normalSamples += 1 }
        if let lux { lightSum += lux; lightSamples += 1 }
        let p = pose.columns.3.xyz
        let heading = pose.headingDegrees
        if tracking == .normal { sectors.insert(Int(heading / 30) % 12) }
        var speed = 0.0, turn = 0.0
        if let last, t > last.t {
            let dt = t - last.t
            let flat = SIMD2(p.x, p.z) - SIMD2(last.position.x, last.position.z)
            speed = Double(simd_length(flat)) / dt
            var dh = abs(heading - last.heading)
            if dh > 180 { dh = 360 - dh }
            turn = Double(dh) / dt
            speedSum += speed
            peakSpeed = max(peakSpeed, speed)
        }
        last = (p, heading, t)
        if path.last.map({ simd_distance($0, SIMD2(p.x, p.z)) > 0.1 }) ?? true { path.append(SIMD2(p.x, p.z)) }
        return (speed, turn)
    }

    public var directionsCovered: Int { sectors.count }
    public var trackingNormalRatio: Double { samples == 0 ? 0 : Double(normalSamples) / Double(samples) }
    public var meanSpeed: Double { samples < 2 ? 0 : speedSum / Double(samples - 1) }
    public var meanLight: Double { lightSamples == 0 ? 0 : lightSum / Double(lightSamples) }

    /// Area of the convex hull of the walked path (m²).
    public var areaWalked: Double { Double(Self.hullArea(path)) }

    static func hullArea(_ pts: [SIMD2<Float>]) -> Float {
        guard pts.count >= 3 else { return 0 }
        let s = pts.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        func cross(_ o: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        var lower: [SIMD2<Float>] = [], upper: [SIMD2<Float>] = []
        for p in s { while lower.count >= 2, cross(lower[lower.count - 2], lower.last!, p) <= 0 { lower.removeLast() }; lower.append(p) }
        for p in s.reversed() { while upper.count >= 2, cross(upper[upper.count - 2], upper.last!, p) <= 0 { upper.removeLast() }; upper.append(p) }
        let hull = Array(lower.dropLast() + upper.dropLast())
        var a: Float = 0
        for i in hull.indices { let j = (i + 1) % hull.count; a += hull[i].x * hull[j].y - hull[j].x * hull[i].y }
        return abs(a) / 2
    }
}

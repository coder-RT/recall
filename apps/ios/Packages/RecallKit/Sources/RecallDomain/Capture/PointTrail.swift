import Foundation

/// The LiDAR points captured so far, for painting on the camera while scanning: newest kept, the total capped so
/// drawing stays smooth (the oldest are thinned, every other one, when it's full).
public struct PointTrail: Sendable {
    public let cap: Int
    public private(set) var points: [SIMD3<Float>] = []
    /// every point ever added, including thinned ones: the "Points" readout
    public private(set) var total = 0

    public init(cap: Int = 30_000) { self.cap = cap }

    public mutating func add(_ new: [SIMD3<Float>]) {
        total += new.count
        points.append(contentsOf: new)
        if points.count > cap {
            let old = points.count - cap / 2  // thin the older part, keep the newest half whole
            let thinned = points[..<old].enumerated().compactMap { $0.offset.isMultiple(of: 2) ? $0.element : nil }
            points = Array(thinned) + points[old...]
            if points.count > cap { points.removeFirst(points.count - cap) }
        }
    }
}

/// Walking speed for the scan readout, and whether it's too fast for sharp photos.
public enum ScanSpeed {
    /// metres per second above which the readout turns amber (the speed coach's own limit)
    public static let tooFast = SpeedCoach.Limits().maxSpeed
    public static func isTooFast(_ metresPerSecond: Double) -> Bool { metresPerSecond > tooFast }
    public static func text(_ metresPerSecond: Double) -> String { String(format: "%.1f m/s", metresPerSecond) }
}

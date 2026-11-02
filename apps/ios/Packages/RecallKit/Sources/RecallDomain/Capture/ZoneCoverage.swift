import Foundation

/// The room cut into zones while scanning: 1 m columns on the floor, each split into Recall's five height bands
/// (floor, knee, waist, chest, head; the same bands answers use). A zone counts as seen once LiDAR points land in it,
/// so the scan shows which parts of the room, at which heights, nobody has looked at yet.
public struct ZoneCoverage: Sendable, Equatable {
    /// Band edges above the floor, metres: floor < 0.3 ≤ knee < 0.7 ≤ waist < 1.1 ≤ chest < 1.5 ≤ head < 2.2.
    public static let edges: [Float] = [0, 0.3, 0.7, 1.1, 1.5, 2.2]
    public static let bandNames = ["floor", "knee", "waist", "chest", "head"]
    public static let column: Float = 1.0

    public struct Column: Hashable, Sendable {
        public let x: Int32
        public let z: Int32
    }

    /// For each column: the bands seen in it (0 = floor ... 4 = head).
    public private(set) var seen: [Column: Set<Int>] = [:]

    public init() {}

    /// LiDAR points (ARKit world) with the floor's height; points above 2.2 m or below the floor are left out.
    public mutating func add(_ points: [SIMD3<Float>], floorY: Float) {
        for p in points {
            let h = p.y - floorY
            guard h >= -0.05, h < Self.edges.last!, let band = Self.band(Double(max(h, 0))) else { continue }
            let c = Column(x: Int32((p.x / Self.column).rounded(.down)), z: Int32((p.z / Self.column).rounded(.down)))
            seen[c, default: []].insert(band)
        }
    }

    public static func band(_ height: Double) -> Int? {
        for i in 0..<(edges.count - 1) where height >= Double(edges[i]) && height < Double(edges[i + 1]) { return i }
        return nil
    }

    /// Zones seen, of all zones in the columns the scan reached (a column counts once anything in it was seen).
    public var zonesSeen: Int { seen.values.reduce(0) { $0 + $1.count } }
    public var zonesTotal: Int { seen.count * Self.bandNames.count }

    /// The height band seen least, across the columns: what to point at next ("knee height").
    public var weakestBand: String? {
        guard !seen.isEmpty else { return nil }
        let counts = (0..<Self.bandNames.count).map { b in seen.values.filter { $0.contains(b) }.count }
        let low = counts.enumerated().min { $0.element < $1.element }!
        return low.element == seen.count ? nil : Self.bandNames[low.offset]
    }
}

import simd

/// How much of the room the LiDAR actually saw, from a few depth samples per keyframe (world points, ARKit: y up).
/// Floor: 25 cm cells where points lie at the floor's level. Walls: 12 bearings (30° each) around the middle of where
/// the person walked, where a tall surface was seen between knee and head height. Both feed the scan's mini-map and
/// its voice steps; headings alone said nothing about whether the walls themselves were in view.
public struct SurfaceCoverage: Sendable, Equatable {
    public static let cell: Float = 0.25

    public private(set) var floorCells = Set<SIMD2<Int32>>()
    public private(set) var wallSectors = Set<Int>()
    public private(set) var floorY: Float?
    public private(set) var path: [SIMD2<Float>] = []
    private var walkedSum = SIMD2<Float>(0, 0)
    private var walkedCount = 0

    public init() {}

    /// The middle of where the person walked (x, z).
    public var centre: SIMD2<Float> { walkedCount == 0 ? .zero : walkedSum / Float(walkedCount) }
    public var floorSeenM2: Double { Double(floorCells.count) * Double(Self.cell * Self.cell) }
    public var wallsCovered: Int { wallSectors.count }

    /// Length of the walked path so far (metres).
    public var walkedM: Double {
        zip(path, path.dropFirst()).reduce(0) { $0 + Double(simd_distance($1.0, $1.1)) }
    }

    /// How far the phone is now from where the scan began (metres).
    public var fromStartM: Double {
        guard let a = path.first, let b = path.last else { return 0 }
        return Double(simd_distance(a, b))
    }

    public mutating func add(samples: [SIMD3<Float>], camera: SIMD3<Float>) {
        let here = SIMD2(camera.x, camera.z)
        walkedSum += here
        walkedCount += 1
        if path.last.map({ simd_distance($0, here) > 0.1 }) ?? true { path.append(here) }
        guard !samples.isEmpty else { return }

        // the floor: the lowest level seen, never more than 2.2 m below the phone (stray points below are ignored)
        let ys = samples.map(\.y).filter { $0 > camera.y - 2.2 }.sorted()
        if ys.count >= 10 {
            let low = ys[ys.count / 20]  // 5th percentile
            floorY = min(floorY ?? low, low)
        }
        guard let floorY else { return }
        let c = centre
        for p in samples {
            let h = p.y - floorY
            if h < 0.08 {
                floorCells.insert(SIMD2(Int32((p.x / Self.cell).rounded(.down)), Int32((p.z / Self.cell).rounded(.down))))
            } else if h > 0.6, h < 1.9 {
                let d = SIMD2(p.x, p.z) - c
                guard simd_length(d) >= 0.6 else { continue }
                var deg = atan2(d.x, -d.y) * 180 / .pi  // ARKit yaw: 0 = −Z, clockwise from above
                if deg < 0 { deg += 360 }
                wallSectors.insert(Int(deg / 30) % 12)
            }
        }
    }
}

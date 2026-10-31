import Foundation

/// One compass reading: magnetic heading (clockwise from magnetic north) and its accuracy, both in degrees.
/// A negative accuracy means the heading is invalid (uncalibrated, or strong magnetic interference).
public struct HeadingReading: Sendable, Equatable {
    public let magneticDeg: Double
    public let accuracyDeg: Double

    public init(magneticDeg: Double, accuracyDeg: Double) { self.magneticDeg = magneticDeg; self.accuracyDeg = accuracyDeg }

    /// Good enough to use indoors (within 20°).
    public var isReliable: Bool { accuracyDeg >= 0 && accuracyDeg <= 20 }
}

/// Angles on a compass: means that wrap around north, names a person says, and "am I facing it?".
public enum CompassMath {
    public static func normalise(_ deg: Double) -> Double {
        let d = deg.truncatingRemainder(dividingBy: 360)
        return d < 0 ? d + 360 : d
    }

    /// a − b, in (−180, 180].
    public static func difference(_ a: Double, _ b: Double) -> Double {
        let d = normalise(a - b)
        return d > 180 ? d - 360 : d
    }

    /// Circular mean and spread (circular standard deviation) of angles in degrees; nil for no angles.
    public static func circularMean(_ degs: [Double]) -> (mean: Double, spread: Double)? {
        guard !degs.isEmpty else { return nil }
        let s = degs.reduce(0) { $0 + sin($1 * .pi / 180) }
        let c = degs.reduce(0) { $0 + cos($1 * .pi / 180) }
        let n = Double(degs.count)
        let r = min(1, (s * s + c * c).squareRoot() / n)
        let spread = r <= 1e-9 ? 180 : (-2 * log(r)).squareRoot() * 180 / .pi
        return (normalise(atan2(s, c) * 180 / .pi), spread)
    }

    /// "north", "north-east", … (eight points, as people say them).
    public static func name(_ bearing: Double) -> String {
        let names = ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
        return names[Int((normalise(bearing) + 22.5) / 45) % 8]
    }

    /// Facing the bearing, within `tolerance` degrees either side.
    public static func facing(_ heading: Double, _ bearing: Double, tolerance: Double = 15) -> Bool {
        abs(difference(heading, bearing)) <= tolerance
    }
}

/// Learns, during a scan, where magnetic north lies in that scan's ARKit world: the mean of (camera yaw − compass)
/// over readings taken while the phone was upright (the same way it is held while being guided) and reliable.
public struct CompassCalibration: Sendable {
    public private(set) var offsets: [Double] = []

    public init() {}

    /// `cameraYaw`: ARKit yaw of where the camera faces (0 = −Z, clockwise from above); `pitch`: degrees above level.
    public mutating func add(_ reading: HeadingReading, cameraYaw: Double, pitch: Double) {
        guard reading.isReliable, abs(pitch) < 30 else { return }
        offsets.append(CompassMath.normalise(cameraYaw - reading.magneticDeg))
    }

    /// Where north is (ARKit yaw), the samples' spread, and how many; nil without readings.
    public var summary: Manifest.Compass? {
        guard offsets.count >= 5, let (mean, spread) = CompassMath.circularMean(offsets) else { return nil }
        return Manifest.Compass(northYawDeg: (mean * 10).rounded() / 10, spreadDeg: (spread * 10).rounded() / 10,
                                samples: offsets.count)
    }
}

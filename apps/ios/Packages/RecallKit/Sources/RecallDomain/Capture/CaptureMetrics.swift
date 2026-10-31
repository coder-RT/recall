import Foundation

/// The scan report's numbers (Manifest.capture_metrics), and the grade rules.
public struct CaptureMetrics: Codable, Sendable, Equatable {
    public var directionsCovered: Int
    public var keyframesKept: Int
    public var keyframesDroppedBlurry: Int
    public var trackingNormalRatio: Double
    public var meanSpeedMps: Double
    public var peakSpeedMps: Double
    public var slowDownCues: Int
    public var areaWalkedM2: Double
    public var meanLightLux: Double
    public var wallsCovered: Int?
    public var floorSeenM2: Double?
    public var mapStatus: MapStatus?
    public var loopClosed: Bool?
    public var compassSpreadDeg: Double?
    public var grade: ScanGrade

    enum CodingKeys: String, CodingKey {
        case directionsCovered = "directions_covered", keyframesKept = "keyframes_kept"
        case keyframesDroppedBlurry = "keyframes_dropped_blurry", trackingNormalRatio = "tracking_normal_ratio"
        case meanSpeedMps = "mean_speed_mps", peakSpeedMps = "peak_speed_mps", slowDownCues = "slow_down_cues"
        case areaWalkedM2 = "area_walked_m2", meanLightLux = "mean_light_lux", grade
        case wallsCovered = "walls_covered", floorSeenM2 = "floor_seen_m2", mapStatus = "map_status"
        case loopClosed = "loop_closed", compassSpreadDeg = "compass_spread_deg"
    }

    public init(directionsCovered: Int, keyframesKept: Int, keyframesDroppedBlurry: Int, trackingNormalRatio: Double,
                meanSpeedMps: Double, peakSpeedMps: Double, slowDownCues: Int, areaWalkedM2: Double, meanLightLux: Double,
                wallsCovered: Int? = nil, floorSeenM2: Double? = nil, mapStatus: MapStatus? = nil,
                loopClosed: Bool? = nil, compassSpreadDeg: Double? = nil) {
        self.directionsCovered = directionsCovered; self.keyframesKept = keyframesKept
        self.keyframesDroppedBlurry = keyframesDroppedBlurry; self.trackingNormalRatio = trackingNormalRatio
        self.meanSpeedMps = meanSpeedMps; self.peakSpeedMps = peakSpeedMps; self.slowDownCues = slowDownCues
        self.areaWalkedM2 = areaWalkedM2; self.meanLightLux = meanLightLux
        self.wallsCovered = wallsCovered; self.floorSeenM2 = floorSeenM2; self.mapStatus = mapStatus
        self.loopClosed = loopClosed; self.compassSpreadDeg = compassSpreadDeg
        self.grade = ScanGrade.grade(directions: directionsCovered, trackingNormal: trackingNormalRatio,
                                     blurryShare: Self.blurryShare(kept: keyframesKept, dropped: keyframesDroppedBlurry),
                                     walls: wallsCovered, map: mapStatus)
    }

    public static func blurryShare(kept: Int, dropped: Int) -> Double {
        let total = kept + dropped
        return total == 0 ? 0 : Double(dropped) / Double(total)
    }
}

public enum ScanGrade: String, Codable, Sendable {
    case good, usable, redo

    /// Good: at least 10 of 12 directions, tracking normal 90 % or more, under 15 % blurry frames, and (when measured)
    /// walls seen on at least 9 of 12 bearings with the room map ready. Redo: fewer than 6 directions or tracking
    /// normal under 70 %. Otherwise usable.
    public static func grade(directions: Int, trackingNormal: Double, blurryShare: Double, walls: Int? = nil,
                             map: MapStatus? = nil) -> ScanGrade {
        if directions < 6 || trackingNormal < 0.7 { return .redo }
        let wallsOK = (walls ?? 12) >= 9
        let mapOK = (map ?? .mapped) == .mapped
        if directions >= 10, trackingNormal >= 0.9, blurryShare < 0.15, wallsOK, mapOK { return .good }
        return .usable
    }

    /// The one-sentence reason a person hears with the grade.
    public static func reason(for m: CaptureMetrics) -> String {
        switch m.grade {
        case .good: return "You covered \(m.directionsCovered) of 12 directions with steady tracking."
        case .redo where m.directionsCovered < 6:
            return "Only \(m.directionsCovered) of 12 directions were covered. Turn slowly all the way around."
        case .redo: return "Tracking was lost too often. Move slower, with the lights on."
        case .usable where (m.wallsCovered ?? 12) < 9:
            return "Walls were seen on \(m.wallsCovered ?? 0) of 12 sides. Walk along the walls next time."
        case .usable where (m.mapStatus ?? .mapped) != .mapped:
            return "The room map wasn't finished. Move slowly a little longer before stopping."
        case .usable where m.directionsCovered < 10:
            return "\(m.directionsCovered) of 12 directions covered. More turning would help."
        case .usable where CaptureMetrics.blurryShare(kept: m.keyframesKept, dropped: m.keyframesDroppedBlurry) >= 0.15:
            return "Some frames were blurry. Hold the phone steadier."
        case .usable: return "Tracking was a little unsteady."
        }
    }
}

import Foundation

/// "Next time": up to three concrete things to do better, from what the scan measured. Nothing for a scan that went well.
public enum ScanTips {
    public static func make(_ m: CaptureMetrics) -> [String] {
        var tips: [String] = []
        if m.peakSpeedMps > SpeedCoach.Limits().maxSpeed + 0.2 {
            tips.append(String(format: "You walked at up to %.1f metres a second. Stay under %.1f: slower means sharper photos.",
                               m.peakSpeedMps, SpeedCoach.Limits().maxSpeed))
        }
        if let walls = m.wallsCovered, walls < 9 {
            tips.append("Walls were seen on \(walls) of 12 sides. Walk the whole way round, about a metre from each wall.")
        }
        if let seen = m.zonesSeen, let total = m.zonesTotal, total > 0, Double(seen) / Double(total) < 0.6 {
            tips.append("Height zones seen \(seen) of \(total). Point the phone at knee height and up at shelves too, not only straight ahead.")
        }
        if m.directionsCovered < 10 {
            tips.append("\(m.directionsCovered) of 12 directions were seen. Turn slowly all the way round at the start.")
        }
        if CaptureMetrics.blurryShare(kept: m.keyframesKept, dropped: m.keyframesDroppedBlurry) >= 0.15 {
            tips.append("Some photos were blurry. Hold the phone steady with both hands.")
        }
        if m.meanLightLux > 0, m.meanLightLux < 150 {
            tips.append("It was dim. Turn on the lights before scanning.")
        }
        if m.loopClosed == false {
            tips.append("End where you started, by the door: it lines the room up, and the Watch starts its walk there.")
        }
        if let spread = m.compassSpreadDeg, spread > 25 {
            tips.append("The compass wandered. Keep away from big metal things and speakers when you start.")
        }
        if m.mapStatus.map({ $0 != .mapped }) == true {
            tips.append("The room map wasn't ready. Keep moving slowly until it says ready, then press Stop.")
        }
        return Array(tips.prefix(3))
    }

    /// The light, in a word, for the report's tile.
    public static func light(_ lux: Double) -> String {
        lux <= 0 ? "Unknown" : lux < 150 ? "Dim" : lux < 1500 ? "OK" : "Bright"
    }
}

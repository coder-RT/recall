import RecallDesign
import RecallDomain
import SwiftUI

/// The spoken scan report: a grade (Good, Usable, Redo), the reason, the numbers, and what to do next.
struct ReportView: View {
    @Environment(ScansModel.self) private var scans
    let scan: Scan
    let metrics: CaptureMetrics
    let close: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    IconTile(RoomIcon.for(scan.room))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(scan.room).font(.title.weight(.bold)).foregroundStyle(Tokens.ink)
                            .accessibilityAddTraits(.isHeader)
                        GradeBadge(grade: scan.grade)
                    }
                }
                .padding(.top, 12)
                    Text(ScanGrade.reason(for: metrics)).font(.body).foregroundStyle(Tokens.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .card()
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        StatTile("\(metrics.directionsCovered)/12", "directions covered")
                        StatTile("\(metrics.keyframesKept)", "sharp frames")
                        StatTile("\(Int((metrics.trackingNormalRatio * 100).rounded())) %", "steady tracking")
                        StatTile(String(format: "%.1f m/s", metrics.meanSpeedMps), "average pace")
                        StatTile("\(metrics.slowDownCues)", "slow-down cues")
                        StatTile(String(format: "%.0f m²", metrics.areaWalkedM2), "area walked")
                        if let seen = metrics.zonesSeen, let total = metrics.zonesTotal, total > 0 {
                            StatTile("\(seen)/\(total)", "height zones seen")
                        }
                        if let walls = metrics.wallsCovered { StatTile("\(walls)/12", "wall sides seen") }
                        if let floor = metrics.floorSeenM2 { StatTile(String(format: "%.1f m²", floor), "floor seen") }
                        if let points = metrics.points {
                            StatTile(points >= 1000 ? "\(points / 1000) k" : "\(points)", "LiDAR points")
                        }
                        StatTile(String(format: "%.1f m/s", metrics.peakSpeedMps), "fastest pace")
                        StatTile("\(Int((CaptureMetrics.blurryShare(kept: metrics.keyframesKept, dropped: metrics.keyframesDroppedBlurry) * 100).rounded())) %",
                                 "blurry photos")
                        if let loop = metrics.loopClosed { StatTile(loop ? "Yes" : "No", "back at the start") }
                        if let spread = metrics.compassSpreadDeg { StatTile(spread <= 25 ? "Good" : "Poor", "compass") }
                        StatTile(ScanTips.light(metrics.meanLightLux), "light")
                    }
                    if let steps = metrics.steps, !steps.isEmpty { StepTimeline(steps: steps) }
                    let tips = ScanTips.make(metrics)
                    if !tips.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Next time").font(.headline).foregroundStyle(Tokens.ink).accessibilityAddTraits(.isHeader)
                            ForEach(tips, id: \.self) { tip in
                                Label(tip, systemImage: "lightbulb").font(.subheadline).foregroundStyle(Tokens.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card()
                        .accessibilityIdentifier("report-tips")
                    }
                BigButton("Upload to the Mac", systemImage: "arrow.up.circle.fill",
                          hint: "Send the scan to your Mac so Recall can remember the room.") {
                    scans.upload(scan); close()
                }
                if scan.grade == .redo {
                    Text("This scan is likely too thin to use. You can still upload it, or scan the room again.")
                        .foregroundStyle(Tokens.ink).card()
                }
                BigButton("Done", systemImage: "checkmark", hint: "Keep the scan on this phone for now.", style: .secondary,
                          action: close)
            }
            .padding(Tokens.gutter)
        }
        .recallScreen()
    }
}


/// How each step went: done (a tick) or moved on when its time ran out, how long it took, and what it measured.
private struct StepTimeline: View {
    let steps: [ScanGuide.StepRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How each step went").font(.headline).foregroundStyle(Tokens.ink).accessibilityAddTraits(.isHeader)
            ForEach(Array(steps.enumerated()), id: \.offset) { _, r in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: r.completed ? "checkmark.circle.fill" : "arrow.right.circle")
                        .foregroundStyle(r.completed ? Tokens.goText : Tokens.danger)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.title).font(.subheadline.weight(.semibold)).foregroundStyle(Tokens.ink)
                        Text("\(r.detail) · \(Int(r.seconds)) s\(r.completed ? "" : " · moved on")")
                            .font(.subheadline).foregroundStyle(Tokens.muted)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(r.title): \(r.completed ? "done" : "moved on before it was done"). \(r.detail). \(Int(r.seconds)) seconds.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityIdentifier("report-steps")
    }
}

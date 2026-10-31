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

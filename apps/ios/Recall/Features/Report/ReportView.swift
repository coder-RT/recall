import RecallDesign
import RecallDomain
import SwiftUI

/// The spoken scan report: a grade (Good, Usable, Redo), the reason, the numbers, and what to do next.
struct ReportView: View {
    @Environment(AppModel.self) private var app
    let record: ScanRecord
    let close: () -> Void
    @State private var metrics: CaptureMetrics?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    IconTile(RoomIcon.for(record.room))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.room).font(.title.weight(.bold)).foregroundStyle(Tokens.ink)
                            .accessibilityAddTraits(.isHeader)
                        GradeBadge(grade: record.grade)
                    }
                }
                .padding(.top, 12)
                if let metrics {
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
                }
                BigButton("Upload to the Mac", systemImage: "arrow.up.circle.fill",
                          hint: "Send the scan to your Mac so Recall can remember the room.") {
                    app.upload(record); close()
                }
                if record.grade == .redo {
                    Text("This scan is likely too thin to use. You can still upload it, or scan the room again.")
                        .foregroundStyle(Tokens.ink).card()
                }
                BigButton("Done", systemImage: "checkmark", hint: "Keep the scan on this phone for now.", style: .secondary,
                          action: close)
            }
            .padding(Tokens.gutter)
        }
        .recallScreen()
        .task {
            let url = app.episodeDir(record.id).appending(path: "manifest.json")
            if let data = try? Data(contentsOf: url), let m = try? JSONDecoder.iso.decode(Manifest.self, from: data) {
                metrics = m.captureMetrics
                let grade = m.captureMetrics.grade == .good ? "good" : m.captureMetrics.grade == .usable ? "usable" : "a redo"
                app.announcer.say("Scan saved. Quality: \(grade). \(ScanGrade.reason(for: m.captureMetrics))", interrupt: true)
            }
        }
    }
}

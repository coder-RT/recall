import RecallDesign
import RecallDomain
import SwiftUI

/// Home: one big action (scan a room) and the scans this phone has made, with their upload state.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var askingRoom = false
    @State private var scanningRoom: String?
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Recall remembers where you put things, and walks you back to them.")
                        .font(.title3).foregroundStyle(Tokens.muted)

                    if !model.isConfigured {
                        Label("Add your Mac's address and device key in Settings before uploading.", systemImage: "exclamationmark.circle")
                            .font(.body).foregroundStyle(Tokens.ink)
                            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Tokens.bluePale, in: RoundedRectangle(cornerRadius: 12))
                    }

                    BigButton("Scan a room", systemImage: "viewfinder", hint: "Walk slowly around one room with the phone.") {
                        askingRoom = true
                    }

                    Text("Your scans").font(.title2.weight(.bold)).foregroundStyle(Tokens.ink)
                        .accessibilityAddTraits(.isHeader)
                    if model.scans.isEmpty {
                        Text("No scans yet.").foregroundStyle(Tokens.muted)
                    }
                    ForEach(model.scans) { scan in
                        ScanRow(scan: scan)
                    }
                }
                .padding(20)
            }
            .background(Tokens.grey)
            .navigationTitle("Recall")
            .toolbar {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Settings")
            }
            .sheet(isPresented: $askingRoom) {
                RoomNameView { room in
                    askingRoom = false
                    scanningRoom = room
                }
            }
            .fullScreenCover(item: Binding(get: { scanningRoom.map(RoomName.init) }, set: { scanningRoom = $0?.id })) { room in
                ScanView(room: room.id) { scanningRoom = nil }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }
}

struct RoomName: Identifiable { let id: String }

private struct ScanRow: View {
    @Environment(AppModel.self) private var model
    let scan: ScanRecord
    @State private var shareURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(scan.room).font(.headline).foregroundStyle(Tokens.ink)
                Spacer()
                GradeBadge(grade: scan.grade)
            }
            Text("\(scan.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(scan.frames) frames · \(scan.directions) of 12 directions")
                .font(.subheadline).foregroundStyle(Tokens.muted)
            if let phase = scan.uploadPhase {
                UploadStatus(phase: phase, fraction: scan.uploadFraction ?? 0, detail: scan.uploadDetail)
            }
            HStack(spacing: 12) {
                if scan.uploadPhase == nil || scan.uploadPhase == "failed" {
                    Button(scan.uploadPhase == "failed" ? "Retry upload" : "Upload to the Mac") { model.upload(scan) }
                        .buttonStyle(.borderedProminent).tint(Tokens.cta)
                        .frame(minHeight: 44)
                }
                if let url = shareURL {
                    ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                        .frame(minHeight: 44)
                        .accessibilityHint("Send this scan with AirDrop or save it to Files.")
                }
            }
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
        .task(id: scan.id) {
            // the zip for AirDrop or Files is built off the main thread, once
            let dir = model.episodeDir(scan.id)
            shareURL = await Task.detached { AppModel.archive(dir) }.value
        }
        .accessibilityElement(children: .contain)
        .contextMenu {
            Button("Delete scan", role: .destructive) { model.delete(scan) }
        }
        .accessibilityAction(named: "Delete scan") { model.delete(scan) }
    }
}

struct GradeBadge: View {
    let grade: ScanGrade

    var body: some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(color, in: Capsule())
            .accessibilityLabel("Scan quality: \(title)")
    }

    private var title: String { grade == .good ? "Good" : grade == .usable ? "Usable" : "Redo" }
    private var icon: String { grade == .good ? "checkmark.circle.fill" : grade == .usable ? "circle.lefthalf.filled" : "arrow.counterclockwise" }
    private var color: Color { grade == .good ? Tokens.cta : grade == .usable ? Tokens.blue : Tokens.danger }
}

private struct UploadStatus: View {
    let phase: String
    let fraction: Double
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if phase == "uploading" {
                ProgressView(value: fraction).tint(Tokens.blue)
                    .accessibilityLabel("Uploading")
                    .accessibilityValue("\(Int(fraction * 100)) percent")
            }
            Text(text).font(.subheadline).foregroundStyle(phase == "failed" ? Tokens.danger : Tokens.ink)
        }
    }

    private var text: String {
        switch phase {
        case "preparing": "Preparing the upload…"
        case "uploading": "Uploading, \(Int(fraction * 100)) percent"
        case "finishing": "Checking the upload…"
        case "processing": "Uploaded. The Mac is processing it."
        case "processed": "Processed. Ready to ask about."
        default: "Upload failed. \(detail ?? "")"
        }
    }
}

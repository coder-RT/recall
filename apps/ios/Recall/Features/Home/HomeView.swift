import RecallDesign
import RecallDomain
import SwiftUI
import UIKit

/// Home: one big action (scan a room) and the scans this phone has made, with their upload state.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var askingRoom = false
    @State private var scanningRoom: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Header()
                    ScanHero { askingRoom = true }
                        .padding(.top, 8)

                    if let problem = model.setupProblem {
                        SetupNotice(problem: problem) { model.tab = .settings }
                    }

                    SectionTitle("Your scans", count: count)
                        .padding(.top, 12)
                    if model.scans.isEmpty {
                        EmptyState("viewfinder", "No scans yet. Scan a room to start.")
                    }
                    ForEach(model.scans) { scan in
                        ScanRow(scan: scan) { model.tab = .found }
                    }
                }
                .padding(.horizontal, Tokens.gutter)
                .padding(.bottom, 24)
            }
            .recallScreen()
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $askingRoom) {
                RoomNameView { room in
                    askingRoom = false
                    scanningRoom = room
                }
            }
            .fullScreenCover(item: Binding(get: { scanningRoom.map(RoomName.init) }, set: { scanningRoom = $0?.id })) { room in
                ScanView(room: room.id) { scanningRoom = nil }
            }
        }
    }

    private var count: String? {
        model.scans.isEmpty ? nil : model.scans.count == 1 ? "1 scan" : "\(model.scans.count) scans"
    }
}

/// The app's mark, name and promise at the top of Home.
private struct Header: View {
    var body: some View {
        HStack(spacing: 14) {
            BrailleMark()
            VStack(alignment: .leading, spacing: 2) {
                Wordmark().accessibilityAddTraits(.isHeader)
                Text("Where are your things?").font(.subheadline).foregroundStyle(Tokens.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 12)
        .accessibilityElement(children: .combine)
    }
}

/// The one big action: a card in old-Facebook blue with a white glass button.
private struct ScanHero: View {
    let scan: () -> Void
    @Environment(\.highContrast) private var hc

    // on the brand gradient the words are white; in high contrast the card is plain and the words are ink
    private var text: Color { hc ? Tokens.ink : .white }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Scan a room").font(.title2.weight(.bold)).foregroundStyle(text)
                    Text("Walk slowly around one room. Recall remembers what's there and walks you back to it.")
                        .font(.subheadline).foregroundStyle(text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "viewfinder")
                    .font(.system(size: 26, weight: .semibold)).foregroundStyle(text)
                    .frame(width: 56, height: 56)
                    .background(text.opacity(0.14), in: .circle)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .combine)
            // a solid fill so the words keep their contrast; the glass is the rim and the touch response
            Button(action: scan) {
                Label("Start a scan", systemImage: "camera.viewfinder")
                    .font(.headline).foregroundStyle(hc ? Tokens.onAccent : Tokens.blueDeep)
                    .frame(maxWidth: .infinity, minHeight: Tokens.minTarget)
                    .background(hc ? Tokens.accentFill : .white, in: Capsule())
            }
            .buttonStyle(.plain)
            .glassRim(.capsule, .regular.interactive())
            .accessibilityHint("Walk slowly around one room with the phone.")
        }
        .padding(20)
        .background {
            if hc {
                RoundedRectangle(cornerRadius: 28).fill(Tokens.card)
                    .overlay(RoundedRectangle(cornerRadius: 28).stroke(Tokens.line, lineWidth: 2))
            } else {
                ZStack(alignment: .topTrailing) {
                    LinearGradient(colors: [Tokens.blue, Tokens.blueDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
                    // a soft light in the corner; decoration only
                    Circle().fill(Tokens.ringCool.opacity(0.45)).frame(width: 220).blur(radius: 50).offset(x: 80, y: -90)
                }
                .clipShape(.rect(cornerRadius: 28))
                .shadow(color: Tokens.blueDeep.opacity(0.25), radius: 16, y: 8)
            }
        }
    }
}

/// Setup isn't finished: say what's missing and go to Settings.
private struct SetupNotice: View {
    let problem: String
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                IconTile("exclamationmark.triangle.fill", tint: Tokens.danger)
                Text(problem).font(.subheadline).foregroundStyle(Tokens.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Open Settings", action: openSettings)
                .font(.subheadline.weight(.semibold)).foregroundStyle(Tokens.accent)
                .buttonStyle(.glass)
        }
        .card()
    }
}

struct RoomName: Identifiable { let id: String }

private struct ScanRow: View {
    @Environment(AppModel.self) private var model
    let scan: ScanRecord
    let review: () -> Void
    @State private var shareURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                IconTile(RoomIcon.for(scan.room))
                VStack(alignment: .leading, spacing: 2) {
                    Text(scan.room).font(.headline).foregroundStyle(Tokens.ink)
                    Text(scan.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.footnote).foregroundStyle(Tokens.muted)
                }
                Spacer(minLength: 8)
                GradeBadge(grade: scan.grade)
            }
            Text("\(scan.frames) frames · \(scan.directions) of 12 directions")
                .font(.footnote).foregroundStyle(Tokens.muted)
            if let phase = scan.uploadPhase {
                UploadStatus(phase: phase, fraction: scan.uploadFraction ?? 0, detail: scan.uploadDetail)
            }
            HStack(spacing: 10) {
                if scan.uploadPhase == nil || scan.uploadPhase == "failed" {
                    Button { model.upload(scan) } label: {
                        Label(scan.uploadPhase == "failed" ? "Retry upload" : "Upload to the Mac", systemImage: "arrow.up.circle")
                            .foregroundStyle(Tokens.onGo)
                    }
                    .buttonStyle(.glassProminent).tint(Tokens.go)
                }
                if scan.uploadPhase == "processed" {
                    Button(action: review) {
                        Label("Check what was found", systemImage: "checklist").foregroundStyle(Tokens.onAccent)
                    }
                    .buttonStyle(.glassProminent).tint(Tokens.accentFill)
                }
                Spacer(minLength: 0)
                if let url = shareURL {
                    ShareLink(item: url) { Image(systemName: "square.and.arrow.up").foregroundStyle(Tokens.accent) }
                        .buttonStyle(.glass).buttonBorderShape(.circle)
                        .accessibilityLabel("Share the scan")
                        .accessibilityHint("Send this scan with AirDrop or save it to Files.")
                }
            }
            .font(.subheadline.weight(.semibold))
            .controlSize(.large)
        }
        .card()
        .task(id: scan.id) {
            // the zip for AirDrop or Files is built off the main thread, once
            let dir = model.episodeDir(scan.id)
            shareURL = await Task.detached { AppModel.archive(dir) }.value
        }
        .accessibilityElement(children: .contain)
        .contextMenu {
            Button("Delete scan", systemImage: "trash", role: .destructive) { model.delete(scan) }
        }
        .accessibilityAction(named: "Delete scan") { model.delete(scan) }
    }
}

/// An SF Symbol for a room name, so the list can be scanned at a glance.
enum RoomIcon {
    static func `for`(_ room: String) -> String {
        let r = room.lowercased()
        if r.contains("kitchen") { return "fork.knife" }
        if r.contains("bed") { return "bed.double" }
        if r.contains("bath") { return "shower" }
        if r.contains("office") || r.contains("study") { return "desktopcomputer" }
        if r.contains("hall") || r.contains("entr") { return "door.left.hand.open" }
        if r.contains("living") || r.contains("lounge") { return "sofa" }
        return "square.split.bottomrightquarter"
    }
}

struct GradeBadge: View {
    let grade: ScanGrade

    var body: some View {
        Chip(title, systemImage: icon, color: color)
            .accessibilityLabel("Scan quality: \(title)")
    }

    private var title: String { grade == .good ? "Good" : grade == .usable ? "Usable" : "Redo" }
    private var icon: String { grade == .good ? "checkmark.circle.fill" : grade == .usable ? "circle.lefthalf.filled" : "arrow.counterclockwise" }
    private var color: Color { grade == .good ? Tokens.goText : grade == .usable ? Tokens.accent : Tokens.danger }
}

private struct UploadStatus: View {
    let phase: String
    let fraction: Double
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if phase == "uploading" {
                ProgressView(value: fraction).tint(Tokens.blue)
                    .accessibilityLabel("Uploading")
                    .accessibilityValue("\(Int(fraction * 100)) percent")
            }
            Label(text, systemImage: icon)
                .font(.subheadline).foregroundStyle(phase == "failed" ? Tokens.danger : Tokens.ink)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if phase == "failed" {
                Button { UIPasteboard.general.string = text } label: {
                    Label("Copy error", systemImage: "doc.on.doc").font(.subheadline.weight(.semibold))
                        .foregroundStyle(Tokens.accent).frame(minHeight: 44)
                }
                .accessibilityLabel("Copy the error")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.canvas, in: .rect(cornerRadius: 12))
    }

    private var icon: String {
        switch phase {
        case "processed": "checkmark.seal.fill"
        case "processing": "gearshape.2"
        case "failed": "exclamationmark.triangle"
        default: "arrow.up.circle"
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

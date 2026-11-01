import RecallDesign
import RecallDomain
import SwiftUI
import UIKit

/// Home: one big action (scan a room) and the scans this phone has made, with their upload state.
struct HomeView: View {
    @Environment(ScansModel.self) private var scans
    @Environment(SettingsModel.self) private var settings
    @Environment(Router.self) private var router
    @Environment(\.container) private var container
    @State private var askingRoom = false
    @State private var scanning: ScanRequest?

    var body: some View {
        let rooms = ScanHistory.byRoom(scans.scans)  // one card per room; its earlier scans fold inside it
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.stack) {
                    BrandHeader("Scans", subtitle: "Where are your things?")
                    ScanHero { askingRoom = true }
                        .padding(.top, 4)

                    if let issue = settings.issue {
                        SetupNotice(problem: issue.message) { router.tab = .settings }
                    }

                    SectionTitle("Your scans", count: count)
                        .padding(.top, Tokens.sectionGap)
                    if scans.scans.isEmpty {
                        EmptyState("viewfinder", "No scans yet. Scan a room to start.")
                    }
                    ForEach(rooms) { room in
                        ScanRow(history: room, review: { router.tab = .found },
                                again: { scanning = ScanRequest(room: room.latest.room, again: room.latest) })
                    }
                }
                .padding(.horizontal, Tokens.gutter)
                .padding(.bottom, 24)
            }
            .tabScreen()
            .sheet(isPresented: $askingRoom) {
                RoomNameView { room in
                    askingRoom = false
                    scanning = ScanRequest(room: room, again: nil)
                }
            }
            .fullScreenCover(item: $scanning) { request in
                if let container {
                    ScanView(model: container.scanModel(room: request.room, again: request.again)) { scanning = nil }
                }
            }
        }
    }

    private var count: String? {
        scans.scans.isEmpty ? nil : scans.scans.count == 1 ? "1 scan" : "\(scans.scans.count) scans"
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
            .buttonStyle(.plainTap)
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

/// A scan to start: a new room, or a room scanned again (in the earlier scan's frame).
struct ScanRequest: Identifiable {
    let room: String
    let again: Scan?
    var id: String { "\(room)|\(again?.id ?? "new")" }
}

private struct ScanRow: View {
    @Environment(ScansModel.self) private var scans
    let history: RoomScans
    let review: () -> Void
    let again: () -> Void
    @State private var shareURL: URL?
    @State private var confirmingDelete = false
    @State private var showingEarlier = false

    private var scan: Scan { history.latest }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // the details read as one block, which also holds the long-press menu (Delete)
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
                if scan.state != .notUploaded { UploadStatus(state: scan.state) }
                if scan.isProcessing && scan.workerStopped { WorkerStopped() }
            }
            .contentShape(.rect)
            .accessibilityElement(children: .combine)
            .accessibilityAction(named: "Delete scan") { askToDelete() }
            .contextMenu {
                Button("Delete scan", systemImage: "trash", role: .destructive) { askToDelete() }
            }
            if scan.showsChanges { WhatChanged(scan: scan) }
            HStack(spacing: 10) {
                if scan.canUpload {
                    let retry = if case .failed = scan.state { true } else { false }
                    Button { scans.upload(scan) } label: {
                        Label(retry ? "Retry upload" : "Upload to the Mac", systemImage: "arrow.up.circle")
                    }
                    .buttonStyle(SolidPillStyle(fill: Tokens.go, text: Tokens.onGo, compact: true))
                }
                if scan.isProcessed {
                    Button(action: review) { Label("Check", systemImage: "checklist") }
                        .buttonStyle(SolidPillStyle(fill: Tokens.accentFill, text: Tokens.onAccent, compact: true))
                        .accessibilityLabel("Check what was found")
                    Button(action: again) { Label("Scan again", systemImage: "arrow.triangle.2.circlepath.camera") }
                        .buttonStyle(SolidPillStyle(fill: Tokens.card, text: Tokens.accent, edge: Tokens.line, compact: true))
                        .accessibilityHint("Scans \(scan.room) again and tells you what changed.")
                }
                Spacer(minLength: 0)
                if let url = shareURL {
                    ShareLink(item: url) { Image(systemName: "square.and.arrow.up").foregroundStyle(Tokens.accent) }
                        .buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.large)
                        .accessibilityLabel("Share the scan")
                        .accessibilityHint("Sends the scan's photos of your home, its depth and path, with AirDrop or to Files. Share only with people you trust.")
                }
            }
            if !history.earlier.isEmpty {
                EarlierScans(history: history, open: $showingEarlier)
            }
        }
        .card()
        .task(id: scan.id) { shareURL = await scans.archive(scan) }  // built once, off the main thread
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Delete scan") { askToDelete() }
        .deleteScanAlert(scan, isPresented: $confirmingDelete)
    }

    /// Asks first; while the Mac is still busy with the scan, says so instead.
    private func askToDelete() {
        if scan.deleteReach == .waitForMac { Task { await scans.delete(scan) } } else { confirmingDelete = true }
    }
}

/// A room's earlier scans, folded at the foot of its card: the memory now comes from the newest one, so these are
/// history, kept to share or delete. No Check or Scan again here; those belong to the current scan.
private struct EarlierScans: View {
    let history: RoomScans
    @Binding var open: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().overlay(Tokens.line.opacity(0.5))
            Button {
                withAnimation(reduceMotion ? nil : .snappy) { open.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Label("Earlier scans", systemImage: "clock.arrow.circlepath")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Tokens.ink)
                    Spacer(minLength: 8)
                    Text("\(history.earlier.count)").font(.subheadline).foregroundStyle(Tokens.muted)
                    Image(systemName: "chevron.down").font(.footnote.weight(.bold)).foregroundStyle(Tokens.muted)
                        .rotationEffect(.degrees(open ? 0 : -90))
                }
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plainTap)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Earlier scans of \(history.latest.room), \(scansText)")
            .accessibilityValue(open ? "Open" : "Folded")
            .accessibilityHint(open ? "Hides them." : "Shows them.")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("earlier-scans")
            if open {
                ForEach(history.earlier) { earlier in
                    EarlierScanRow(scan: earlier, after: history.successor(of: earlier))
                }
            }
        }
    }

    private var scansText: String { history.earlier.count == 1 ? "1 scan" : "\(history.earlier.count) scans" }
}

/// One earlier scan, compact: when, how good, and which scan took over from it. Long press to share or delete.
private struct EarlierScanRow: View {
    @Environment(ScansModel.self) private var scans
    let scan: Scan
    let after: Scan?
    @State private var shareURL: URL?
    @State private var confirmingDelete = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(scan.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Tokens.ink)
                Text("\(scan.frames) frames · \(took)").font(.footnote).foregroundStyle(Tokens.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            GradeBadge(grade: scan.grade)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.canvas, in: .rect(cornerRadius: 12))
        .contentShape(.rect)
        .contextMenu {
            if let url = shareURL { ShareLink("Share scan", item: url) }
            Button("Delete scan", systemImage: "trash", role: .destructive) { confirmingDelete = true }
        }
        .task(id: scan.id) { shareURL = await scans.archive(scan) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(scan.room), \(scan.createdAt.formatted(date: .abbreviated, time: .shortened)), \(took)")
        .accessibilityAction(named: "Delete scan") { confirmingDelete = true }
        .accessibilityIdentifier("earlier-scan-\(scan.id)")
        .deleteScanAlert(scan, isPresented: $confirmingDelete)
    }

    // a recognised rescan built on this one; one that didn't line up made a fresh map of the room
    private var took: String {
        guard let after else { return "earlier scan" }
        let day = after.createdAt.formatted(.dateTime.day().month())
        return after.alignedTo == nil ? "replaced by the scan on \(day)" : "updated by the scan on \(day)"
    }
}

private extension View {
    /// Asks before deleting a scan, saying what it reaches. An alert, not a confirmation dialog: iOS 26 shows that as
    /// a popover with no Cancel, hard to leave by VoiceOver.
    func deleteScanAlert(_ scan: Scan, isPresented: Binding<Bool>) -> some View {
        modifier(DeleteScanAlert(scan: scan, isPresented: isPresented))
    }
}

private struct DeleteScanAlert: ViewModifier {
    @Environment(ScansModel.self) private var scans
    let scan: Scan
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.alert(title, isPresented: $isPresented) {
            Button(scan.deleteReach == .phoneAndMac ? "Delete from iPhone and Mac" : "Delete", role: .destructive) {
                Task { await scans.delete(scan) }
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text(scan.deleteReach == .phoneAndMac
                 ? "Its photos, depth and the things only this scan found are erased from both. Memory goes back to "
                   + "your other scans of \(scan.room). This can't be undone."
                 : "It was never uploaded, so nothing of it is on your Mac.")
        }
    }

    private var title: String {
        scan.deleteReach == .phoneAndMac ? "Delete this scan from your iPhone and your Mac?" : "Delete this scan?"
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
    let state: UploadState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if case .uploading(let fraction) = state {
                ProgressView(value: fraction).tint(Tokens.blue)
                    .accessibilityLabel("Uploading")
                    .accessibilityValue("\(Int(fraction * 100)) percent")
            }
            Label(state.description, systemImage: icon)
                .font(.subheadline).foregroundStyle(failed ? Tokens.danger : Tokens.ink)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if failed {
                Button { UIPasteboard.general.string = state.description } label: {
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

    private var failed: Bool { if case .failed = state { true } else { false } }

    private var icon: String {
        switch state {
        case .processed: "checkmark.seal.fill"
        case .processing: "gearshape.2"
        case .failed: "exclamationmark.triangle"
        default: "arrow.up.circle"
        }
    }
}

/// After a rescan: what moved, what's new, what's gone, each with its icon and the places in words; or that the room
/// didn't line up with the last one, so it is a fresh map (nothing lost, nothing compared). "Hear it again" says it.
private struct WhatChanged: View {
    @Environment(ScansModel.self) private var scans
    let scan: Scan

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(scan.fresh ? ChangeSummary.freshTitle(room: scan.room) : "What changed",
                      systemImage: scan.fresh ? "map" : "arrow.left.arrow.right")
                    .font(.headline).foregroundStyle(Tokens.ink)
                Spacer(minLength: 8)
                let speaking = scans.speakingScan == scan.id
                Button { scans.toggleChanges(scan) } label: {
                    Label(speaking ? "Stop" : "Hear it again", systemImage: speaking ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .labelStyle(.iconOnly)
                        .font(.title3).foregroundStyle(Tokens.accent).frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel(speaking ? "Stop reading" : "Hear what changed again")
            }
            if scan.fresh {
                Text(ChangeSummary.freshBody)
                    .font(.subheadline).foregroundStyle(Tokens.ink).fixedSize(horizontal: false, vertical: true)
                Label(ChangeSummary.freshTip, systemImage: "lightbulb")
                    .font(.subheadline).foregroundStyle(Tokens.muted).fixedSize(horizontal: false, vertical: true)
            } else if scan.changes.isEmpty {
                Text("Nothing has moved since the last scan.").font(.subheadline).foregroundStyle(Tokens.ink)
            } else {
                ForEach(scan.changes) { change in ChangeRow(change: change) }
            }
        }
        .padding(14)
        .background(Tokens.tile, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("what-changed")
    }
}

private struct ChangeRow: View {
    let change: ScanChange

    var body: some View {
        HStack(spacing: 12) {
            ThingIcon(kind: change.thingKind, color: change.color, side: 36)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(change.title.capitalizedFirst).font(.subheadline.weight(.semibold)).foregroundStyle(Tokens.ink)
                    Label(badge, systemImage: icon).font(.caption.weight(.bold)).foregroundStyle(colour)
                }
                Text(change.places).font(.footnote).foregroundStyle(Tokens.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(change.title.capitalizedFirst): \(change.line).")
    }

    private var badge: String {
        switch change.kind {
        case .moved: "Moved"
        case .new: "New"
        case .gone: "Gone"
        }
    }

    private var icon: String {
        switch change.kind {
        case .moved: "arrow.right.circle.fill"
        case .new: "plus.circle.fill"
        case .gone: "minus.circle.fill"
        }
    }

    private var colour: Color {
        switch change.kind {
        case .moved: Tokens.accent
        case .new: Tokens.goText
        case .gone: Tokens.danger
        }
    }
}


/// A scan waiting with nobody to process it: the Mac's scan worker isn't running. Says what to run, and copies it.
private struct WorkerStopped: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(Scan.workerStoppedMessage, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline).foregroundStyle(Tokens.danger)
                .fixedSize(horizontal: false, vertical: true)
            Button { UIPasteboard.general.string = "make worker" } label: {
                Label("Copy \"make worker\"", systemImage: "doc.on.doc").font(.subheadline.weight(.semibold))
                    .foregroundStyle(Tokens.accent).frame(minHeight: 44)
            }
            .accessibilityHint("Copies the command to run in the recall folder on your Mac.")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.canvas, in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("worker-stopped")
    }
}

import RecallDesign
import RecallDomain
import SwiftUI

/// Robot Access: whether a home robot may use Recall's memory to go and find things, what it receives (and never
/// receives), the map it navigates by, and the package to hand to it. The robot finds the thing; picking it up is
/// the robot's own skill.
struct RobotAccessView: View {
    @Environment(\.container) private var container
    @State private var model: RobotAccessModel?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Today Recall guides you there. Your home robot can use the same memory to go and find it.")
                    .font(.title3.weight(.semibold)).foregroundStyle(Tokens.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let model {
                    AccessSwitch(model: model)
                    if let p = model.package { MapPreview(package: p) }
                    SharedList()
                    ExportCard(model: model)
                    ActivityCard(entries: model.activity)
                    if let s = model.status { DeveloperCard(status: s) }
                    if let e = model.error { ErrorBox(text: e) }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 32)
                }
                Text("Works with ROS 2 robots using Nav2 that you connect yourself. Recall finds the thing on the map; "
                     + "picking it up is the robot's own skill.")
                    .font(.footnote).foregroundStyle(Tokens.muted).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Tokens.gutter)
            .padding(.bottom, 24)
        }
        .recallScreen()
        .navigationTitle("Robot Access")
        .navigationBarTitleDisplayMode(.large)
        .task {
            if model == nil, let container { model = container.robotAccessModel() }
            await model?.load()
        }
    }
}

/// The switch, with what it means.
private struct AccessSwitch: View {
    let model: RobotAccessModel

    var body: some View {
        let on = model.status?.on ?? false
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(get: { on }, set: { v in Task { await model.turn(v) } })) {
                Text("Share home map with robots").font(.headline).foregroundStyle(Tokens.ink)
            }
            .tint(Tokens.go)
            .disabled(model.busy || model.status == nil)
            .accessibilityIdentifier("robot-access-switch")
            Text(on ? "On. A robot with your robot key can ask where things are and get this map."
                    : "Off. Robots can't read your home's memory. You can still export the map yourself.")
                .font(.subheadline).foregroundStyle(Tokens.muted).fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }
}

/// The map a robot navigates by, with the things Recall remembers as blue dots.
private struct MapPreview: View {
    let package: RobotMapPackage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(package.room) map").font(.headline).foregroundStyle(Tokens.ink)
            RoomMapCanvas(package: package)
                .frame(height: 220)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Map of \(package.room) for robots, with \(package.things.count) things marked.")
            RoomMapLegend()
        }
        .card()
    }
}

/// What robots receive, and what never leaves the Mac.
private struct SharedList: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What robots receive").font(.headline).foregroundStyle(Tokens.ink)
            Point(icon: "map", "The room's map: floor, walls and furniture")
            Point(icon: "mappin.and.ellipse", "Where things are and when they were last seen")
            Divider().overlay(Tokens.line.opacity(0.5))
            Text("Never shared").font(.headline).foregroundStyle(Tokens.ink)
            Point(icon: "photo", "Photos or camera frames", never: true)
            Point(icon: "text.quote", "Your own names and notes for things", never: true)
            Point(icon: "location", "Where you or anyone is right now", never: true)
        }
        .card()
        .accessibilityIdentifier("robot-shared-list")
    }
}

private struct Point: View {
    let icon: String
    let text: String
    let never: Bool
    init(icon: String, _ text: String, never: Bool = false) { self.icon = icon; self.text = text; self.never = never }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: never ? "xmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(never ? Tokens.danger : Tokens.goText)
                .accessibilityHidden(true)
            Text(text).foregroundStyle(Tokens.ink).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel((never ? "Never: " : "Shared: ") + text)
    }
}

/// The package to hand to a robot: map.pgm, map.yaml, objects.json, room.json, as one .zip.
private struct ExportCard: View {
    let model: RobotAccessModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Export map for robots").font(.headline).foregroundStyle(Tokens.ink)
            Text("A ready-to-load package for ROS 2 and Nav2: the map, where things are, and the room outline.")
                .font(.subheadline).foregroundStyle(Tokens.muted).fixedSize(horizontal: false, vertical: true)
            if let zip = model.zip {
                ShareLink(item: zip) { Label("Share robot map", systemImage: "square.and.arrow.up") }
                    .buttonStyle(SolidPillStyle(fill: Tokens.go, text: Tokens.onGo))
                    .accessibilityHint("Send the package with AirDrop, Files or Mail.")
            } else {
                Button { Task { await model.prepareExport() } } label: {
                    Label(model.busy ? "Preparing…" : "Prepare robot map", systemImage: "shippingbox")
                }
                .buttonStyle(SolidPillStyle(fill: Tokens.accentFill, text: Tokens.onAccent))
                .disabled(model.busy)
            }
        }
        .card()
    }
}

/// What robots did lately, from the Mac's audit log, newest first.
private struct ActivityCard: View {
    let entries: [AuditEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent robot activity").font(.headline).foregroundStyle(Tokens.ink)
                .accessibilityAddTraits(.isHeader)
            if entries.isEmpty {
                Text("No robot has used your home's memory yet.").font(.subheadline).foregroundStyle(Tokens.muted)
            }
            ForEach(entries) { e in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: e.refused ? "hand.raised.fill" : "checkmark.circle.fill")
                        .foregroundStyle(e.refused ? Tokens.danger : Tokens.goText)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.summary).foregroundStyle(Tokens.ink).fixedSize(horizontal: false, vertical: true)
                        Text(e.at, format: .relative(presentation: .named)).font(.footnote).foregroundStyle(Tokens.muted)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            Text("Kept on your Mac for 90 days. Keys are never recorded.")
                .font(.footnote).foregroundStyle(Tokens.muted).fixedSize(horizontal: false, vertical: true)
        }
        .card()
        .accessibilityIdentifier("robot-activity")
    }
}

/// Where a developer points the robot (and the key it needs).
private struct DeveloperCard: View {
    let status: RobotAccessStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("For developers").font(.headline).foregroundStyle(Tokens.ink)
            Address(title: "Home Memory agent (A2A)", value: status.a2aURL)
            Address(title: "Agent Card", value: status.agentCardURL)
            Address(title: "Map export", value: status.exportURL)
            Text("Robots use the robot key set on the Mac (RECALL_ROBOT_KEY), never your phone's key.")
                .font(.footnote).foregroundStyle(Tokens.muted).fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }
}

private struct Address: View {
    let title: String
    let value: String
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Tokens.ink)
                Text(value).font(.footnote.monospaced()).foregroundStyle(Tokens.muted).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // one element: the title is the label, the address its value (a bare URL isn't a readable label)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(value)
            Spacer(minLength: 4)
            Button { UIPasteboard.general.string = value } label: {
                Image(systemName: "doc.on.doc").frame(minWidth: 44, minHeight: 44)
            }
            .foregroundStyle(Tokens.accent)
            .accessibilityLabel("Copy \(title) address")
        }
    }
}

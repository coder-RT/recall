import RecallDesign
import SwiftUI

/// Where Recall runs: the iPhone today; the Apple Watch and Meta's AI glasses next. Every card says plainly whether it
/// works yet (a word and an icon, never colour alone), so nothing planned reads as finished. No other company's logos,
/// only their product names.
struct DevicesView: View {
    @Environment(Router.self) private var router

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    BrandHeader("Devices", subtitle: "One memory of your home, wherever you are")
                    Pitch()
                    SectionTitle("Where Recall runs", count: "3 devices")
                    ForEach(Device.all) { DeviceCard(device: $0) }
                    SectionTitle("Why it works")
                    ForEach(Promise.all) { PromiseRow(promise: $0) }
                    HStack(spacing: 12) {
                        Button { router.tab = .find } label: { Label("Ask now", systemImage: "location.magnifyingglass") }
                            .buttonStyle(SolidPillStyle(fill: Tokens.go, text: Tokens.onGo))
                            .accessibilityHint("Opens Find, to ask where something is.")
                        Button { router.tab = .scans } label: { Label("Scan a room", systemImage: "viewfinder") }
                            .buttonStyle(SolidPillStyle(fill: Tokens.card, text: Tokens.accent, edge: Tokens.line))
                            .accessibilityHint("Opens Scans, to record a room.")
                    }
                    Text("Only the iPhone app works today; the Watch and glasses are being built. Recall is an independent project, not affiliated with Apple or Meta.")
                        .font(.footnote).foregroundStyle(Tokens.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Tokens.gutter)
                .padding(.bottom, 24)
            }
            .tabScreen()
        }
    }
}

/// The product in two sentences.
private struct Pitch: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ask where it is. Be walked there.")
                .font(.title2.weight(.bold)).foregroundStyle(Tokens.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Walk through a room once with your iPhone. Then ask \u{201C}where are my keys?\u{201D} and hear the way, step by step, with a tap when you face the right way.")
                .foregroundStyle(Tokens.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}

/// One device Recall is for, how far along it is, and what it does there.
struct Device: Identifiable {
    enum Status {
        case available, next, planned

        var title: String {
            switch self {
            case .available: "Available now"
            case .next: "Coming next"
            case .planned: "Planned"
            }
        }

        var icon: String {
            switch self {
            case .available: "checkmark.circle.fill"
            case .next: "hammer.fill"
            case .planned: "calendar"
            }
        }
    }

    let id: String
    let name: String
    let systemImage: String
    let status: Status
    let pitch: String
    let points: [String]

    static let all = [
        Device(id: "iphone", name: "iPhone", systemImage: "iphone.gen3", status: .available,
               pitch: "The whole of Recall today, by voice and without looking.",
               points: ["Scan a room with LiDAR, led step by step by voice",
                        "Ask out loud; hear clock-face turns with compass points",
                        "A blue arrow over the thing on the camera, for a helper"]),
        Device(id: "watch", name: "Apple Watch Ultra 4", systemImage: "applewatch", status: .next,
               pitch: "Directions you can feel, with the phone in your pocket.",
               points: ["A tap on the wrist for each turn, a buzz when you arrive",
                        "Ask from your wrist and hear the answer",
                        "Hands free for a cane or a guide dog"]),
        Device(id: "glasses", name: "Meta AI glasses", systemImage: "eyeglasses", status: .planned,
               pitch: "Ask hands-free and be guided by what the glasses see.",
               points: ["Ask through the glasses; hear the answer in their speakers",
                        "Guidance from the glasses' own camera view",
                        "Nothing to hold, nothing to look at"]),
    ]
}

private struct DeviceCard: View {
    let device: Device

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: device.systemImage)
                    .font(.system(size: 30, weight: .semibold)).foregroundStyle(Tokens.accent)
                    .frame(width: 56, height: 56)
                    .background(Tokens.tile, in: .rect(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 4) {
                    Text(device.name).font(.headline).foregroundStyle(Tokens.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    StatusBadge(status: device.status)
                }
            }
            Text(device.pitch).font(.body.weight(.semibold)).foregroundStyle(Tokens.ink)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(device.points, id: \.self) { point in
                    Label(point, systemImage: "checkmark")
                        .labelStyle(PointLabel())
                }
            }
        }
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(device.name). \(device.status.title). \(device.pitch) \(device.points.joined(separator: ". ")).")
        .accessibilityIdentifier("device-\(device.id)")
    }
}

/// "Available now" in the go colour; the others in the accent; always with its word and icon.
private struct StatusBadge: View {
    let status: Device.Status

    var body: some View {
        Label(status.title, systemImage: status.icon)
            .font(.footnote.weight(.bold))
            .foregroundStyle(status == .available ? Tokens.onGo : Tokens.accent)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(status == .available ? Tokens.go : Tokens.tile, in: .capsule)
    }
}

private struct PointLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon.font(.footnote.weight(.bold)).foregroundStyle(Tokens.goText)
            configuration.title.foregroundStyle(Tokens.ink).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// What makes Recall trustworthy, in plain words (each one is true of the iPhone app today).
struct Promise: Identifiable {
    let id: String
    let systemImage: String
    let title: String
    let text: String

    static let all = [
        Promise(id: "geometry", systemImage: "ruler", title: "Measured, not guessed",
                text: "Places, heights and distances come from the 3D scan. The language model only puts them into words."),
        Promise(id: "meta", systemImage: "cpu", title: "Meta's models",
                text: "Muse, SAM 3.1 and MapAnything do the work, and your room is rebuilt in 3D on your own Mac."),
        Promise(id: "voice", systemImage: "speaker.wave.2.fill", title: "Built for VoiceOver first",
                text: "Every step is spoken, every control is labelled, and nothing needs to be seen."),
    ]
}

private struct PromiseRow: View {
    let promise: Promise

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: promise.systemImage)
                .font(.system(size: 20, weight: .semibold)).foregroundStyle(Tokens.accent)
                .frame(width: 40, height: 40)
                .background(Tokens.tile, in: .circle)
            VStack(alignment: .leading, spacing: 4) {
                Text(promise.title).font(.headline).foregroundStyle(Tokens.ink)
                Text(promise.text).foregroundStyle(Tokens.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}

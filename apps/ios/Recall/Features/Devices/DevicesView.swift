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
                }
                .padding(.horizontal, Tokens.gutter)
                DeviceCarousel()
                    .padding(.top, 4)
                VStack(alignment: .leading, spacing: 16) {
                    SectionTitle("Why it works")
                    Promises()
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
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .tabScreen()
        }
    }
}

/// The devices as a row of icons to tap and, under it, cards to swipe; each follows the other. The card in focus
/// is full size, its neighbours peek in smaller and fainter (still, when Reduce Motion is on).
private struct DeviceCarousel: View {
    @State private var focused: String? = Device.all.first?.id
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var pill

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                ForEach(Device.all) { device in
                    let on = focused == device.id
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.85)) { focused = device.id }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: device.systemImage).font(.system(size: 22, weight: .semibold))
                                .frame(height: 28)  // the symbols differ in height; the words line up
                            Text(device.short).font(.footnote.weight(.semibold))
                        }
                        .foregroundStyle(on ? Tokens.onAccent : Tokens.accent)
                        .frame(maxWidth: .infinity, minHeight: Tokens.minTarget)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: 16).fill(Tokens.accentFill)
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(device.name)
                    .accessibilityHint("Shows it below.")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(4)
            .background(Tokens.card, in: .rect(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Tokens.line.opacity(0.6), lineWidth: 0.5))
            .padding(.horizontal, Tokens.gutter)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(Device.all) { device in
                        DeviceCard(device: device)
                            .containerRelativeFrame(.horizontal) { width, _ in width * 0.84 }
                            .scrollTransition(axis: .horizontal) { content, phase in
                                content
                                    .scaleEffect(phase.isIdentity || reduceMotion ? 1 : 0.92)
                                    .opacity(phase.isIdentity ? 1 : 0.55)
                            }
                            .id(device.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()  // the cards' shadows and the peeking neighbours aren't cut off
            .scrollPosition(id: $focused)
            .contentMargins(.horizontal, Tokens.gutter, for: .scrollContent)
            .accessibilityIdentifier("devices-carousel")

            HStack(spacing: 8) {
                ForEach(Device.all) { device in
                    Capsule().fill(focused == device.id ? Tokens.accent : Tokens.line)
                        .frame(width: focused == device.id ? 22 : 8, height: 8)
                }
            }
            .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8), value: focused)
            .accessibilityHidden(true)
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
    let short: String
    let systemImage: String
    let status: Status
    let pitch: String
    let points: [String]

    static let all = [
        Device(id: "iphone", name: "iPhone", short: "iPhone", systemImage: "iphone.gen3", status: .available,
               pitch: "The whole of Recall today, by voice and without looking.",
               points: ["Scan a room with LiDAR, led step by step by voice",
                        "Ask out loud; hear clock-face turns with compass points",
                        "A blue arrow over the thing on the camera, for a helper"]),
        Device(id: "watch", name: "Apple Watch Ultra 4", short: "Watch", systemImage: "applewatch", status: .next,
               pitch: "Directions you can feel, with the phone in your pocket.",
               points: ["A tap on the wrist for each turn, a buzz when you arrive",
                        "Ask from your wrist and hear the answer",
                        "Hands free for a cane or a guide dog"]),
        Device(id: "glasses", name: "Meta AI glasses", short: "Glasses", systemImage: "eyeglasses", status: .planned,
               pitch: "Ask hands-free and be guided by what the glasses see.",
               points: ["Ask through the glasses; hear the answer in their speakers",
                        "Guidance from the glasses' own camera view",
                        "Nothing to hold, nothing to look at"]),
    ]
}

private struct DeviceCard: View {
    let device: Device

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [Tokens.blue, Tokens.blueDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().fill(.white.opacity(0.10)).frame(width: 170).offset(x: 150, y: -40)  // a soft light
                Image(systemName: device.systemImage)
                    .font(.system(size: 76, weight: .regular))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                StatusBadge(status: device.status).padding(14)
            }
            .frame(height: 170)
            .clipShape(.rect(topLeadingRadius: Tokens.cardRadius, topTrailingRadius: Tokens.cardRadius))
            VStack(alignment: .leading, spacing: 10) {
                Text(device.name).font(.title3.weight(.bold)).foregroundStyle(Tokens.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(device.pitch).foregroundStyle(Tokens.ink)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(device.points, id: \.self) { point in
                        Label(point, systemImage: "checkmark").labelStyle(PointLabel())
                    }
                }
                .font(.subheadline)
                Spacer(minLength: 0)
            }
            .padding(16)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Tokens.card, in: .rect(cornerRadius: Tokens.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Tokens.cardRadius).stroke(Tokens.line.opacity(0.6), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(device.name). \(device.status.title). \(device.pitch) \(device.points.joined(separator: ". ")).")
        .accessibilityIdentifier("device-\(device.id)")
    }
}

/// On the blue stage: "Available now" in the go colour, the others white; always a word and an icon.
private struct StatusBadge: View {
    let status: Device.Status

    var body: some View {
        Label(status.title, systemImage: status.icon)
            .font(.footnote.weight(.bold))
            .foregroundStyle(status == .available ? Tokens.onGo : Tokens.blueDeep)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(status == .available ? Tokens.go : .white, in: .capsule)
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

/// The three promises in one card, a line each.
private struct Promises: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Promise.all) { promise in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: promise.systemImage)
                        .font(.system(size: 17, weight: .semibold)).foregroundStyle(Tokens.accent)
                        .frame(width: 34, height: 34)
                        .background(Tokens.tile, in: .circle)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(promise.title).font(.headline).foregroundStyle(Tokens.ink)
                        Text(promise.text).font(.subheadline).foregroundStyle(Tokens.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .card()
    }
}

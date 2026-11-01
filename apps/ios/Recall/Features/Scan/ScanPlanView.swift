import RecallDesign
import RecallDomain
import SwiftUI

/// "How to scan well", before every scan: each step with what to do, why it matters, when it's done, and how high to
/// hold the phone. The same words are spoken during the scan; here they can be read (or heard) first.
struct ScanPlanView: View {
    let room: String
    let rescan: Bool
    let readAloud: () -> Void
    let start: () -> Void
    let cancel: () -> Void

    private var steps: [ScanGuide.Step] { ScanGuide.Step.allCases.filter { $0 != .recognise || rescan } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.stack) {
                    Text("Scanning \(room) takes about 2 minutes. Recall says each step as you go; here is the whole plan.")
                        .font(.body).foregroundStyle(Tokens.ink).fixedSize(horizontal: false, vertical: true)
                    ForEach(Array(steps.enumerated()), id: \.element) { i, step in
                        PlanStep(number: i + 1, step: step)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Good to know").font(.headline).foregroundStyle(Tokens.ink).accessibilityAddTraits(.isHeader)
                        ForEach(Self.tips, id: \.self) { tip in
                            Label(tip, systemImage: "checkmark.circle").font(.subheadline).foregroundStyle(Tokens.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .card()
                    Button("Read the steps aloud", systemImage: "speaker.wave.2.fill", action: readAloud)
                        .buttonStyle(SolidPillStyle(fill: Tokens.card, text: Tokens.accent, edge: Tokens.line))
                        .accessibilityIdentifier("plan-read")
                    Button("Start scanning", systemImage: "camera.viewfinder", action: start)
                        .buttonStyle(SolidPillStyle(fill: Tokens.go, text: Tokens.onGo))
                        .accessibilityIdentifier("plan-start")
                }
                .padding(Tokens.gutter)
            }
            .recallScreen()
            .navigationTitle("How to scan well")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: cancel) } }
        }
    }

    static let tips = [
        "Turn the lights on, and open doors you want in the scan.",
        "Walk slowly, as if carrying a full cup.",
        "Hold the phone with both hands, screen facing you.",
        "Start at the room's door: the Watch starts its directions there.",
    ]
}

private struct PlanStep: View {
    let number: Int
    let step: ScanGuide.Step

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(step == .recognise ? "↺" : "\(number)").font(.headline.monospacedDigit()).foregroundStyle(Tokens.onAccent)
                .frame(width: 32, height: 32).background(Tokens.accentFill, in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(step.title).font(.headline).foregroundStyle(Tokens.ink)
                Text(step.instruction).font(.subheadline).foregroundStyle(Tokens.ink)
                Text("Why: \(step.why)").font(.subheadline).foregroundStyle(Tokens.muted)
                Text(step.doneWhen).font(.subheadline.weight(.semibold)).foregroundStyle(Tokens.goText)
                Label("Phone: \(step.heightLabel)", systemImage: "iphone.gen3").font(.footnote).foregroundStyle(Tokens.muted)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(number): \(step.title). \(step.instruction) Why: \(step.why) \(step.doneWhen) Phone at \(step.heightLabel).")
        .accessibilityIdentifier("plan-step-\(step.rawValue)")
    }
}

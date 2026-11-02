import RecallDomain
import SwiftUI

/// One screen: the Recall mark, what is happening in large words, the main button (also the double tap) and Stop.
/// The crown turns through the things; every label is read by VoiceOver.
struct WatchView: View {
    @Bindable var model: WatchModel

    var body: some View {
        ScrollView {
        VStack(spacing: 8) {
            RecallMark()
                .frame(width: 34, height: 44)
                .accessibilityHidden(true)
            Text(headline)
                .font(isMessage ? .headline : .title3.weight(.bold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)  // long messages wrap and scroll, never cut off
                .accessibilityAddTraits(.updatesFrequently)
            if let sub = subline {
                Text(sub).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).lineLimit(2)
            }
            Button(action: model.primary) {
                Text(primaryLabel).font(.headline).foregroundStyle(.white).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.23, green: 0.35, blue: 0.6))  // white on fb-blue: 7.4:1
            .handGestureShortcut(.primaryAction)  // the double tap (pinch twice) does the same
            .accessibilityHint("Double tap with two fingers does the same.")
            if showsStop {
                Button("Stop", role: .destructive, action: model.stop)
            }
        }
        .padding(.horizontal, 6)
        }
        .focusable()
        .digitalCrownRotation($model.dial, from: 0, through: Double(max(model.things.count - 1, 0)), by: 1,
                              sensitivity: .low, isContinuous: true, isHapticFeedbackEnabled: true)
        .onAppear { model.appeared() }
    }

    private var headline: String {
        switch model.stage {
        case .greeting: "Hi, I'm Recall"
        case .listening: "Listening…"
        case .thinking: "Looking…"
        case .picking: model.picked?.title ?? "Nothing yet"
        case .ready(let r): "Your \(r.title)"
        case .walking: model.step.isEmpty ? "Hold your wrist level" : model.step
        case .arrived(let r): "Your \(r.title)"
        case .message(let m): m
        }
    }

    private var isMessage: Bool {
        if case .message = model.stage { true } else { false }
    }

    private var subline: String? {
        switch model.stage {
        case .greeting, .listening: "Say it, or turn the crown"
        case .picking: model.picked?.place
        case .ready(let r): "Stand \(r.start)"
        case .arrived(let r): r.place
        default: nil
        }
    }

    private var primaryLabel: String {
        switch model.stage {
        case .picking: "Find it"
        case .ready: "Walk there"
        case .walking: "Repeat"
        default: "Ask"
        }
    }

    private var showsStop: Bool {
        switch model.stage {
        case .walking, .ready, .listening, .thinking: true
        default: false
        }
    }
}

/// The Recall mark: one Braille cell, dots 1, 2, 3 and 5 raised (the letter R).
struct RecallMark: View {
    var body: some View {
        Grid(horizontalSpacing: 5, verticalSpacing: 5) {
            ForEach(0..<3, id: \.self) { row in
                GridRow {
                    ForEach(0..<2, id: \.self) { col in
                        let n = col * 3 + row + 1
                        Circle()
                            .fill([1, 2, 3, 5].contains(n) ? Color(red: 0.23, green: 0.35, blue: 0.6) : Color.gray.opacity(0.35))
                            .frame(width: 11, height: 11)
                    }
                }
            }
        }
    }
}

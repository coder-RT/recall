import RecallDesign
import RecallDomain
import SwiftUI

/// Privacy, in plain words: what stays on your devices, what leaves the Mac (to whom and when, as the Mac is set up
/// right now), what never happens, and the controls. The same text as docs/privacy.md and the website's /privacy.
struct PrivacyView: View {
    @Environment(\.container) private var container
    @State private var status: PrivacyStatus?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(PrivacyNote.short)
                    .font(.title3.weight(.semibold)).foregroundStyle(Tokens.ink)
                    .fixedSize(horizontal: false, vertical: true)
                RightNow(status: status, error: error)
                Points(title: "Kept on your devices", items: PrivacyNote.kept, mark: "lock.fill")
                Points(title: "Never", items: PrivacyNote.never, mark: "xmark.circle.fill", never: true)
                Controls()
                Text(PrivacyNote.theirTerms)
                    .font(.footnote).foregroundStyle(Tokens.muted).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Tokens.gutter)
            .padding(.bottom, 24)
        }
        .recallScreen()
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.large)
        .task {
            guard status == nil, let container else { return }
            do { status = try await container.privacySource().privacy() } catch {
                self.error = "Pair with your Mac to see what it sends right now. " + UserMessage.explain(error)
            }
        }
    }
}

/// What leaves the Mac under its current settings, from the Mac itself.
private struct RightNow: View {
    let status: PrivacyStatus?
    let error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Right now").font(.headline).foregroundStyle(Tokens.ink).accessibilityAddTraits(.isHeader)
            if let status {
                Text("Your scans and memory are kept on: \(status.storedOn).")
                    .foregroundStyle(Tokens.ink).fixedSize(horizontal: false, vertical: true)
                ForEach(status.sent) { flow in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(flow.what).font(.subheadline.weight(.semibold)).foregroundStyle(Tokens.ink)
                        Label(flow.to, systemImage: flow.onThisMac ? "desktopcomputer" : "arrow.up.forward.circle")
                            .font(.subheadline).foregroundStyle(flow.onThisMac ? Tokens.goText : Tokens.accent)
                        Text(flow.when).font(.footnote).foregroundStyle(Tokens.muted)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(flow.what). Sent to \(flow.to). \(flow.when).")
                }
                Text(status.robotLine + " The activity log keeps \(status.auditDays) days.")
                    .font(.footnote).foregroundStyle(Tokens.muted).fixedSize(horizontal: false, vertical: true)
            } else if let error {
                Text(error).foregroundStyle(Tokens.muted).fixedSize(horizontal: false, vertical: true)
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .card()
        .accessibilityIdentifier("privacy-right-now")
    }
}

private struct Points: View {
    let title: String
    let items: [String]
    let mark: String
    var never = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline).foregroundStyle(Tokens.ink).accessibilityAddTraits(.isHeader)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: mark).foregroundStyle(never ? Tokens.danger : Tokens.goText).accessibilityHidden(true)
                    Text(item).foregroundStyle(Tokens.ink).fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(never ? "Never: \(item)" : item)
            }
        }
        .card()
    }
}

private struct Controls: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your controls").font(.headline).foregroundStyle(Tokens.ink).accessibilityAddTraits(.isHeader)
            ForEach(PrivacyNote.controls, id: \.title) { c in
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.title).font(.subheadline.weight(.semibold)).foregroundStyle(Tokens.ink)
                    Text(c.detail).font(.subheadline).foregroundStyle(Tokens.muted)
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
            }
        }
        .card()
    }
}

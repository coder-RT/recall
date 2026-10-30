import RecallDesign
import RecallNetworking
import SwiftUI
import UIKit

/// Where the Mac is and the shared device key (pairing, not a login). The key is kept in the Keychain.
/// Plain labelled fields instead of a system Form, so every text scales with Dynamic Type and nothing clips.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var testResult: String?
    @State private var testing = false
    @State private var showKey = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Field(title: "Mac address",
                          note: "The address the Mac's API prints when it starts, or a Cloudflare Tunnel URL.") {
                        TextField("Mac address", text: $model.serverURL,
                                  prompt: Text("http://192.168.1.20:8000").foregroundStyle(Tokens.muted), axis: .vertical)
                            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityIdentifier("macAddress")
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Field(title: "Device key", note: "RECALL_DEVICE_KEY from the Mac's .env. Stored in this iPhone's Keychain.") {
                            Group {
                                if showKey {
                                    TextField("Device key", text: $model.deviceKey,
                                              prompt: Text("Paste the key").foregroundStyle(Tokens.muted), axis: .vertical)
                                } else {
                                    SecureField("Device key", text: $model.deviceKey,
                                                prompt: Text("Paste the key").foregroundStyle(Tokens.muted))
                                }
                            }
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityIdentifier("deviceKey")
                        }
                        Text(keySummary).font(.footnote).foregroundStyle(Tokens.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 10) {
                            SmallButton(showKey ? "Hide" : "Show", systemImage: showKey ? "eye.slash" : "eye",
                                        label: showKey ? "Hide the key" : "Show the key") { showKey.toggle() }
                            PasteButton(payloadType: String.self) { strings in
                                guard let text = strings.first else { return }
                                Task { @MainActor in
                                    model.deviceKey = text.trimmingCharacters(in: .whitespacesAndNewlines)
                                    model.announcer.say("Key pasted. \(keySummary)")
                                }
                            }
                            .buttonBorderShape(.roundedRectangle(radius: 10))
                            .tint(Tokens.blueDark)
                            .frame(minHeight: Tokens.minTarget)
                            .accessibilityLabel("Paste the key")
                            SmallButton("Copy", systemImage: "doc.on.doc", label: "Copy the key") {
                                UIPasteboard.general.string = model.cleanKey
                                model.announcer.say("Key copied.")
                            }
                            .disabled(model.cleanKey.isEmpty)
                        }
                    }
                    Field(title: "Home name", note: "One name per home; every scan joins it.") {
                        TextField("Home name", text: $model.homeId, axis: .vertical)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    BigButton(testing ? "Testing…" : "Test connection", systemImage: "antenna.radiowaves.left.and.right",
                              hint: "Checks the address and the device key.", style: .secondary) {
                        Task { await test() }
                    }
                    .disabled(testing)
                    if let testResult {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(testResult).font(.body).foregroundStyle(Tokens.ink)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                            SmallButton("Copy message", systemImage: "doc.on.doc", label: "Copy the message") {
                                UIPasteboard.general.string = testResult
                            }
                        }
                    }
                }
                .glassCard(padding: 12)
                .padding(.horizontal, 12).padding(.vertical, 20)
            }
            .recallScreen()
            .navigationTitle("Settings")
        }
    }

    private func test() async {
        testing = true
        defer { testing = false }
        guard let api = model.api else {
            testResult = model.setupProblem ?? "Check the address and the device key."
            return
        }
        // errors stay on screen to read or copy; only success is spoken
        do {
            let provider = try await api.health()
            // a status call for a scan that doesn't exist checks the key: "not found" means the key was accepted
            do { _ = try await api.scanStatus(scanId: "00000000-0000-4000-8000-000000000000") } catch APIError.server {}
            testResult = "Connected. The Mac's Guide runs on \(provider)."
            model.announcer.say("Connected.")
        } catch {
            testResult = APIError.explain(error)
        }
    }
}

/// A short summary of the key, so it can be compared with the Mac's without showing it.
extension SettingsView {
    var keySummary: String {
        let key = model.cleanKey
        guard !key.isEmpty else { return "No key yet." }
        return "\(key.count) characters, ending in \(key.suffix(4).map(String.init).joined(separator: " "))."
    }
}

/// A compact outlined button for the row under a field.
private struct SmallButton: View {
    let title: String
    let systemImage: String
    let label: String
    let action: () -> Void
    init(_ title: String, systemImage: String, label: String, action: @escaping () -> Void) {
        self.title = title; self.systemImage = systemImage; self.label = label; self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage).font(.body.weight(.semibold))
                .padding(.horizontal, 14).frame(minHeight: Tokens.minTarget)
                .foregroundStyle(Tokens.blueDark)
                .background(.white, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Tokens.line, lineWidth: 1))
        }
        .accessibilityLabel(label)
    }
}

/// A labelled text field: the label is the field's accessibility label, the note its hint.
private struct Field<Content: View>: View {
    let title: String
    let note: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).foregroundStyle(Tokens.ink)
                .accessibilityHidden(true)
            content
                .font(.body).foregroundStyle(Tokens.ink)
                .padding(14)
                .frame(minHeight: Tokens.minTarget)
                .background(.white, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Tokens.line, lineWidth: 1))
                .accessibilityLabel(title)
                .accessibilityHint(note)
            Text(note).font(.footnote).foregroundStyle(Tokens.muted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
        }
    }
}

/// Section text in contrast-safe colours for the forms that remain (the system's secondary grey is under 4.5:1).
struct SectionHeader: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(Tokens.muted).textCase(nil) }
}

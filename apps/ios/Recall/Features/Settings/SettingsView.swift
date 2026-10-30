import RecallDesign
import RecallNetworking
import SwiftUI
import UIKit

/// Where the Mac is and the shared device key (pairing, not a login). The key is kept in the Keychain.
/// A native grouped Form: the system draws its rows and bars, and every text scales with Dynamic Type.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var testResult: String?
    @State private var testOK = false
    @State private var testing = false
    @State private var showKey = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    TextField("Mac address", text: $model.serverURL,
                              prompt: Text("https://your-mac.ts.net:8445").foregroundStyle(Tokens.muted), axis: .vertical)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("macAddress")
                } header: { Header("Mac address") } footer: {
                    Note("The address the Mac's API prints when it starts, a Tailscale or a Cloudflare Tunnel URL.")
                }

                Section {
                    Group {
                        if !showKey && !model.cleanKey.isEmpty {
                            // a secure field draws its dots too small to see in a form row; this shows the key is there
                            Text("•••• •••• \(String(model.cleanKey.suffix(4)))")
                                .font(.body.monospaced()).foregroundStyle(Tokens.ink)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityLabel("Device key, \(keySummary)")
                        } else if showKey {
                            TextField("Device key", text: $model.deviceKey,
                                      prompt: Text("Paste the key").foregroundStyle(Tokens.muted), axis: .vertical)
                                .font(.body.monospaced())
                        } else {
                            SecureField("Device key", text: $model.deviceKey,
                                        prompt: Text("Paste the key").foregroundStyle(Tokens.muted))
                        }
                    }
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("deviceKey")
                    HStack(spacing: 8) {
                        Button(showKey ? "Hide" : "Show", systemImage: showKey ? "eye.slash" : "eye") { showKey.toggle() }
                            .accessibilityLabel(showKey ? "Hide the key" : "Show the key")
                        PasteButton(payloadType: String.self) { strings in
                            guard let text = strings.first else { return }
                            Task { @MainActor in
                                model.deviceKey = text.trimmingCharacters(in: .whitespacesAndNewlines)
                                model.announcer.say("Key pasted. \(keySummary)")
                            }
                        }
                        .labelStyle(.titleAndIcon)
                        .buttonBorderShape(.capsule)
                        .tint(Tokens.blueDark)
                        .accessibilityLabel("Paste the key")
                        Button("Copy", systemImage: "doc.on.doc") {
                            UIPasteboard.general.string = model.cleanKey
                            model.announcer.say("Key copied.")
                        }
                        .accessibilityLabel("Copy the key")
                        .disabled(model.cleanKey.isEmpty)
                    }
                    .buttonStyle(.glass)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Tokens.blueDark)
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                } header: { Header("Device key") } footer: {
                    Note("\(keySummary) RECALL_DEVICE_KEY from the Mac's .env, kept in this iPhone's Keychain.")
                }

                Section {
                    TextField("Home name", text: $model.homeId, axis: .vertical)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("homeName")
                } header: { Header("Home name") } footer: { Note("One name per home; every scan joins it.") }

                Section {
                    Button { Task { await test() } } label: {
                        Label(testing ? "Testing…" : "Test connection", systemImage: "antenna.radiowaves.left.and.right")
                            .font(.headline).foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: Tokens.minTarget - 14)
                    }
                    .buttonStyle(.glassProminent).tint(Tokens.blue).controlSize(.large)
                    .accessibilityHint("Checks the address and the device key.")
                    .disabled(testing)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    if let testResult {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(testResult, systemImage: testOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .font(.subheadline).foregroundStyle(testOK ? Tokens.cta : Tokens.danger)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                            Button("Copy message", systemImage: "doc.on.doc") { UIPasteboard.general.string = testResult }
                                .font(.subheadline.weight(.semibold)).foregroundStyle(Tokens.blueDark)
                                .buttonStyle(.borderless)
                                .frame(minHeight: 44)
                                .accessibilityLabel("Copy the message")
                        }
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func test() async {
        testing = true
        defer { testing = false }
        guard let api = model.api else {
            testResult = model.setupProblem ?? "Check the address and the device key."
            testOK = false
            return
        }
        // errors stay on screen to read or copy; only success is spoken
        do {
            let provider = try await api.health()
            // a status call for a scan that doesn't exist checks the key: "not found" means the key was accepted
            do { _ = try await api.scanStatus(scanId: "00000000-0000-4000-8000-000000000000") } catch APIError.server {}
            testResult = "Connected. The Mac's Guide runs on \(provider)."
            testOK = true
            model.announcer.say("Connected.")
        } catch {
            testResult = APIError.explain(error)
            testOK = false
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

/// Form section text in contrast-safe colours (the system's secondary grey is under 4.5:1 on the grouped background).
private struct Header: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(Tokens.muted).textCase(nil)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct Note: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.footnote).foregroundStyle(Tokens.muted).fixedSize(horizontal: false, vertical: true) }
}

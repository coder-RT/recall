import RecallDesign
import RecallNetworking
import SwiftUI

/// Where the Mac is and the shared device key (pairing, not a login). The key is kept in the Keychain.
/// Plain labelled fields instead of a system Form, so every text scales with Dynamic Type and nothing clips.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var testResult: String?
    @State private var testing = false

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
                    Field(title: "Device key", note: "RECALL_DEVICE_KEY from the Mac's .env. Stored in this iPhone's Keychain.") {
                        SecureField("Device key", text: $model.deviceKey,
                                    prompt: Text("Paste the key").foregroundStyle(Tokens.muted))
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
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
                        Text(testResult).font(.body).foregroundStyle(Tokens.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(20)
            }
            .background(Tokens.grey)
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func test() async {
        testing = true
        defer { testing = false }
        guard let api = model.api else {
            testResult = "Enter an address starting with http and the device key."
            model.announcer.say(testResult ?? "")
            return
        }
        do {
            let provider = try await api.health()
            // a status call for a scan that doesn't exist checks the key: "not found" means the key was accepted
            do { _ = try await api.scanStatus(scanId: "00000000-0000-4000-8000-000000000000") } catch APIError.server {}
            testResult = "Connected. The Mac's Guide runs on \(provider)."
        } catch {
            testResult = error.localizedDescription
        }
        model.announcer.say(testResult ?? "")
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

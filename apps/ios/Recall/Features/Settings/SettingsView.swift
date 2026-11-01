import RecallDesign
import RecallDomain
import SwiftUI
import UIKit

/// Where the Mac is and the shared device key (pairing, not a login). The key is kept in the Keychain.
/// A native grouped Form: the system draws its rows and bars, and every text scales with Dynamic Type.
struct SettingsView: View {
    @Environment(SettingsModel.self) private var model
    @State private var testResult: String?
    @State private var testOK = false
    @State private var testing = false
    @State private var showKey = false
    @State private var canPaste = UIPasteboard.general.hasStrings  // checking doesn't read it (no paste prompt)
    @AppStorage(Theme.appearanceKey) private var appearance = Appearance.system
    @AppStorage(Theme.highContrastKey) private var highContrast = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Group {
                    Section {
                        BrandHeader("Settings", subtitle: "Your Mac, your key, your theme")
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                    }

                    Section {
                        NavigationLink {
                            PrivacyView()
                        } label: {
                            Label("Privacy", systemImage: "hand.raised.fill").foregroundStyle(Tokens.ink)
                        }
                        .accessibilityHint("What stays on your Mac and iPhone, and what is sent where.")
                        .accessibilityIdentifier("privacy")
                    }

                    Section {
                        NavigationLink {
                            AppearanceView()
                        } label: {
                            HStack {
                                Label("Appearance", systemImage: "circle.lefthalf.filled").foregroundStyle(Tokens.ink)
                                Spacer()
                                Text(highContrast ? "\(appearance.title), high contrast" : appearance.title)
                                    .foregroundStyle(Tokens.muted)
                            }
                        }
                        .accessibilityIdentifier("appearance")
                    }

                    Section {
                        TextField("Mac address", text: $model.connection.address,
                                  prompt: Text("https://your-mac.ts.net:8445").foregroundStyle(Tokens.muted), axis: .vertical)
                            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityIdentifier("macAddress")
                    } header: { FormHeader("Mac address") } footer: {
                        FormNote("The address the Mac's API prints when it starts, a Tailscale or a Cloudflare Tunnel URL.")
                    }

                    Section {
                        Group {
                            if !showKey && !model.connection.cleanKey.isEmpty {
                                // a secure field draws its dots too small to see in a form row; this shows the key is there
                                Text("•••• •••• \(String(model.connection.cleanKey.suffix(4)))")
                                    .font(.body.monospaced()).foregroundStyle(Tokens.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityLabel("Device key, \(model.connection.keySummary)")
                            } else if showKey {
                                TextField("Device key", text: $model.connection.key,
                                          prompt: Text("Paste the key").foregroundStyle(Tokens.muted), axis: .vertical)
                                    .font(.body.monospaced())
                            } else {
                                SecureField("Device key", text: $model.connection.key,
                                            prompt: Text("Paste the key").foregroundStyle(Tokens.muted))
                            }
                        }
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("deviceKey")
                        HStack(spacing: 8) {
                            Button(showKey ? "Hide" : "Show", systemImage: showKey ? "eye.slash" : "eye") { showKey.toggle() }
                                .accessibilityLabel(showKey ? "Hide the key" : "Show the key")
                            // our own button, styled like its neighbours: the system PasteButton greys out when there is
                            // nothing to paste and draws white on the dark theme's pale tint (both too faint). It shows
                            // only when there's text; iOS may ask once to allow pasting.
                            if canPaste {
                                Button("Paste", systemImage: "doc.on.clipboard") {
                                    guard let text = UIPasteboard.general.string else { return }
                                    model.connection.key = text.trimmingCharacters(in: .whitespacesAndNewlines)
                                    model.say("Key pasted. \(model.connection.keySummary)")
                                }
                                .accessibilityLabel("Paste the key")
                            }
                            Button("Copy", systemImage: "doc.on.doc") {
                                UIPasteboard.general.string = model.connection.cleanKey
                                model.say("Key copied.")
                            }
                            .accessibilityLabel("Copy the key")
                            .disabled(model.connection.cleanKey.isEmpty)
                        }
                        // solid fills: glass would tint the words (and did fail contrast)
                        .buttonStyle(SolidPillStyle(fill: Tokens.card, text: Tokens.accent, edge: Tokens.line, compact: true))
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    } header: { FormHeader("Device key") } footer: {
                        FormNote("\(model.connection.keySummary) RECALL_DEVICE_KEY from the Mac's .env, kept in this iPhone's Keychain.")
                    }

                    Section {
                        TextField("Home name", text: $model.connection.home, axis: .vertical)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityIdentifier("homeName")
                    } header: { FormHeader("Home name") } footer: { FormNote("One name per home; every scan joins it.") }

                    Section {
                        Button { Task { await test() } } label: {
                            Label(testing ? "Testing…" : "Test connection", systemImage: "antenna.radiowaves.left.and.right")
                        }
                        .buttonStyle(SolidPillStyle(fill: Tokens.accentFill, text: Tokens.onAccent))
                        .accessibilityHint("Checks the address and the device key.")
                        .disabled(testing)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                        if let testResult {
                            VStack(alignment: .leading, spacing: 8) {
                                Label(testResult, systemImage: testOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .font(.subheadline).foregroundStyle(testOK ? Tokens.goText : Tokens.danger)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                                Button("Copy message", systemImage: "doc.on.doc") { UIPasteboard.general.string = testResult }
                                    .font(.subheadline.weight(.semibold)).foregroundStyle(Tokens.accent)
                                    .buttonStyle(.borderless)
                                    .frame(minHeight: 44)
                                    .accessibilityLabel("Copy the message")
                            }
                        }
                    }

                }
                .listRowBackground(Tokens.card)
            }
            .recallScreen()
            .toolbar(.hidden, for: .navigationBar)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in
                canPaste = UIPasteboard.general.hasStrings
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                canPaste = UIPasteboard.general.hasStrings  // copied on the Mac, then back in the app
            }
        }
    }

    private func test() async {
        testing = true
        defer { testing = false }
        (testResult, testOK) = await model.testConnection()
    }
}

/// Theme: automatic, light or dark, high contrast, and the tab tap sound.
private struct AppearanceView: View {
    @AppStorage(Theme.appearanceKey) private var appearance = Appearance.system
    @AppStorage(Theme.highContrastKey) private var highContrast = false
    @AppStorage(TapSound.enabledKey) private var tapSounds = true

    var body: some View {
        Form {
            Group {
                Section {
                    ForEach(Appearance.allCases, id: \.self) { a in
                        Button { appearance = a } label: {
                            HStack {
                                Text(a.title).foregroundStyle(Tokens.ink)
                                Spacer()
                                if appearance == a {
                                    Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(Tokens.accent)
                                }
                            }
                        }
                        .accessibilityAddTraits(appearance == a ? .isSelected : [])
                    }
                } header: { FormHeader("Theme") } footer: { FormNote("Automatic follows the iPhone's light or dark setting.") }
                Section {
                    Toggle("High contrast", isOn: $highContrast).tint(Tokens.go)
                } footer: {
                    FormNote("Black, white and yellow, like the website's high contrast. It also turns on with iOS's Increase Contrast.")
                }
                Section {
                    Toggle("Tap sounds", isOn: $tapSounds).tint(Tokens.go)
                } footer: {
                    FormNote("A soft tap and a light buzz when you switch tabs. The ring/silent switch mutes the sound.")
                }
            }
            .listRowBackground(Tokens.card)
        }
        .recallScreen()
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

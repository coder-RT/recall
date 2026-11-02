import RecallDesign
import RecallDomain
import RecallUpload
import SwiftUI
import UIKit

@main
struct RecallApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var container = AppContainer()

    init() {
        TapFeedback.play = { TapSound.shared.play(.press) }  // every shared button style gives the soft tap
    }

    var body: some Scene {
        WindowGroup {
            ThemedRoot()
                .environment(container.router)
                .environment(container.settings)
                .environment(container.things)
                .environment(container.scans)
                .environment(container.roomMaps)
                .environment(container.trust)
                .environment(\.container, container)
        }
    }
}

extension EnvironmentValues {
    /// The composition root, for screens that build their own feature model (Find, Guide, Scan).
    @Entry var container: AppContainer? = nil
}

/// The tabs, with the user's theme applied: light, dark or automatic, and high contrast (the Settings switch or
/// iOS's Increase Contrast).
private struct ThemedRoot: View {
    @Environment(Router.self) private var router
    @Environment(SettingsModel.self) private var settings
    @Environment(ScansModel.self) private var scans
    @Environment(\.container) private var container
    @Environment(\.colorSchemeContrast) private var systemContrast
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(Theme.appearanceKey) private var appearance = Appearance.system
    @AppStorage(Theme.highContrastKey) private var highContrast = false

    var body: some View {
        @Bindable var router = router
        // a tap on the bar plays the tap sound; switching tabs in code ("Open Settings") stays quiet
        let tabs = Binding(get: { router.tab }, set: { tab in
            if tab != router.tab { TapSound.shared.play() }
            router.tab = tab
        })
        TabView(selection: tabs) {
            // first in the bar, but the app opens on Find: asking stays one step away
            Tab("Devices", systemImage: "apps.iphone", value: AppTab.devices) { DevicesView() }
            Tab("Find", systemImage: "location.magnifyingglass", value: AppTab.find) { FindView() }
            Tab("Scans", systemImage: "viewfinder", value: AppTab.scans) { HomeView() }
            Tab("Found", systemImage: "checklist", value: AppTab.found) { FoundView() }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) { SettingsView() }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .overlay(alignment: .topLeading) { if UITestSamples.logSpeech { SpokenLogElement() } }
        .tint(Tokens.accent)
        .fullScreenCover(item: $router.guiding) { thing in
            if let container {
                GuideView(model: container.guideModel(for: thing)) { router.guiding = nil }
            }
        }
        .environment(\.highContrast, highContrast || systemContrast == .increased)
        .preferredColorScheme(appearance.scheme)
        // dynamic colours read the switch when they resolve; a new identity redraws them all
        .id(highContrast)
        .onChange(of: highContrast, initial: true) { Theme.highContrast = highContrast }
        .task { await scans.start() }
        // back from the background: what finished meanwhile updates the cards without talking
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { scans.becameActive(); KeyboardDismissal.shared.install() }
        }
        .task { KeyboardDismissal.shared.install() }  // a tap outside a text field hides the keyboard, everywhere
        .onOpenURL { settings.pair(with: $0) }
        .alert("Pair with this Mac?", isPresented: Binding(get: { settings.pendingPairing != nil },
                                                           set: { if !$0 { settings.cancelPairing() } }),
               presenting: settings.pendingPairing) { _ in
            Button("Pair") { settings.confirmPairing() }
                .accessibilityIdentifier("pairing.confirm")
            Button("Cancel", role: .cancel) { settings.cancelPairing() }
        } message: { pairing in
            Text(pairing.summary + " Only pair with your own Mac.")
        }
    }
}

/// Hands the system's completion handler to the uploader when iOS relaunches the app for background upload events.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        guard identifier == Uploader.sessionIdentifier else { return completionHandler() }
        nonisolated(unsafe) let done = completionHandler
        AppContainer.uploader.setBackgroundCompletion { done() }
    }
}

/// The usability tests' view of what was spoken: one invisible element, only with -UITestSpokenLog.
private struct SpokenLogElement: View {
    @State private var log = UITestSamples.SpokenLog.shared
    var body: some View {
        Color.clear.frame(width: 1, height: 1)
            .accessibilityElement()
            .accessibilityLabel(log.lines.joined(separator: " | "))
            .accessibilityIdentifier("spoken-log")
    }
}

import RecallDesign
import RecallUpload
import SwiftUI
import UIKit

@main
struct RecallApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ThemedRoot().environment(model)
        }
    }
}

/// The tabs, with the user's theme applied: light, dark or automatic, and high contrast (the Settings switch or
/// iOS's Increase Contrast).
private struct ThemedRoot: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorSchemeContrast) private var systemContrast
    @AppStorage(Theme.appearanceKey) private var appearance = Appearance.system
    @AppStorage(Theme.highContrastKey) private var highContrast = false

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.tab) {
            Tab("Find", systemImage: "location.magnifyingglass", value: AppTab.find) { FindView() }
            Tab("Scans", systemImage: "viewfinder", value: AppTab.scans) { HomeView() }
            Tab("Found", systemImage: "checklist", value: AppTab.found) { ReviewView() }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) { SettingsView() }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(Tokens.accent)
        .fullScreenCover(item: $model.guiding) { target in
            GuideView(target: target) { model.guiding = nil }
        }
        .environment(\.highContrast, highContrast || systemContrast == .increased)
        .preferredColorScheme(appearance.scheme)
        // dynamic colours read the switch when they resolve; a new identity redraws them all
        .id(highContrast)
        .onChange(of: highContrast, initial: true) { Theme.highContrast = highContrast }
        .task { await model.start() }
        .onOpenURL { model.pair(with: $0) }
    }
}

/// Hands the system's completion handler to the uploader when iOS relaunches the app for background upload events.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        guard identifier == Uploader.sessionIdentifier else { return completionHandler() }
        nonisolated(unsafe) let done = completionHandler
        AppModel.sharedUploader.setBackgroundCompletion { done() }
    }
}

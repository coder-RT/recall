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
            @Bindable var model = model
            TabView(selection: $model.tab) {
                Tab("Scans", systemImage: "viewfinder", value: AppTab.scans) { HomeView() }
                Tab("Found", systemImage: "checklist", value: AppTab.found) { ReviewView() }
                Tab("Settings", systemImage: "gearshape", value: AppTab.settings) { SettingsView() }
            }
            .tabBarMinimizeBehavior(.onScrollDown)
            .environment(model)
            .tint(Tokens.blueDark)
            .task { await model.start() }
            .onOpenURL { model.pair(with: $0) }
        }
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

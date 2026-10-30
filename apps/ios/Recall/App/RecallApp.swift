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
            HomeView()
                .environment(model)
                .tint(Tokens.blueDark)
                .task { await model.start() }
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

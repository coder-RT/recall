import SwiftUI

/// Recall on the wrist: "Hi, I'm Recall. What should I find?" Say it, or turn the Digital Crown to pick a thing; then
/// walk there by compass, led by taps on the wrist. The iPhone (in a pocket) talks to the Mac.
@main
struct RecallWatchApp: App {
    @State private var model = WatchModel()

    var body: some Scene {
        WindowGroup {
            WatchView(model: model)
        }
    }
}

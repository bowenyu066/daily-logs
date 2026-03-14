import SwiftUI

@main
struct DailyLogsApp: App {
    @UIApplicationDelegateAdaptor(FirebaseAppDelegate.self) private var appDelegate
    @StateObject private var appViewModel = AppViewModel.live()

    init() {
        FirebaseBootstrap.configureIfPossible()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appViewModel)
                .preferredColorScheme(appViewModel.preferredColorScheme)
        }
    }
}

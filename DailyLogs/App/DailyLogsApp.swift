import SwiftUI

@main
struct DailyLogsApp: App {
    @UIApplicationDelegateAdaptor(FirebaseAppDelegate.self) private var appDelegate
    @StateObject private var appViewModel: AppViewModel

    init() {
        FirebaseBootstrap.configureIfPossible()
        _appViewModel = StateObject(wrappedValue: AppViewModel.live())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appViewModel)
                .preferredColorScheme(appViewModel.preferredColorScheme)
        }
    }
}

import SwiftUI

@main
struct DailyLogsApp: App {
    @StateObject private var appViewModel = AppViewModel.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appViewModel)
        }
    }
}

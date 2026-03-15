import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appViewModel: AppViewModel

    private var resolvedLocale: Locale {
        appViewModel.preferences.appLanguage.locale ?? Locale.autoupdatingCurrent
    }

    var body: some View {
        Group {
            if appViewModel.isAuthenticated {
                MainTabView()
            } else {
                AuthGateView()
            }
        }
        .environment(\.locale, resolvedLocale)
        .task {
            await appViewModel.bootstrap()
        }
    }
}

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
        .id(appViewModel.languageRefreshID)
        .sheet(isPresented: $appViewModel.shouldPresentCloudMigration) {
            CloudEncryptionPassphraseSheet(mode: .migration, isDismissable: false)
                .environmentObject(appViewModel)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .task {
            await appViewModel.bootstrap()
        }
    }
}

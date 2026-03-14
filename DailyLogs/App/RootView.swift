import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appViewModel: AppViewModel

    var body: some View {
        Group {
            if appViewModel.isAuthenticated {
                MainTabView()
            } else {
                AuthGateView()
            }
        }
        .task {
            await appViewModel.bootstrap()
        }
    }
}

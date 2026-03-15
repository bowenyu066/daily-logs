import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label(String(localized: "主页"), systemImage: "house")
                }

            AnalyticsView()
                .tabItem {
                    Label(String(localized: "数据"), systemImage: "chart.line.uptrend.xyaxis")
                }

            SettingsView()
                .tabItem {
                    Label(String(localized: "设置"), systemImage: "slider.horizontal.3")
                }
        }
        .tint(AppTheme.accent)
    }
}

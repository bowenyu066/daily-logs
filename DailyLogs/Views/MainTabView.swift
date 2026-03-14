import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("主页", systemImage: "house")
                }

            AnalyticsView()
                .tabItem {
                    Label("数据", systemImage: "chart.line.uptrend.xyaxis")
                }

            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "slider.horizontal.3")
                }
        }
        .tint(AppTheme.accent)
    }
}


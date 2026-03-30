import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label(NSLocalizedString("主页", comment: ""), systemImage: "house")
                }

            AnalyticsView()
                .tabItem {
                    Label(NSLocalizedString("数据", comment: ""), systemImage: "chart.line.uptrend.xyaxis")
                }

            AIInsightsView()
                .tabItem {
                    Label(NSLocalizedString("AI", comment: ""), systemImage: "sparkles.rectangle.stack")
                }

            SettingsView()
                .tabItem {
                    Label(NSLocalizedString("设置", comment: ""), systemImage: "slider.horizontal.3")
                }
        }
        .tint(AppTheme.accent)
    }
}

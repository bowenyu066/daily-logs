import Charts
import SwiftUI

struct AnalyticsView: View {
    @EnvironmentObject private var appViewModel: AppViewModel

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        summaryGrid
                        sleepChart
                        mealChart
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("数据")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var summary: AnalyticsSummary {
        appViewModel.analyticsSummary
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("规律不是为了控制你，而是为了更轻松地生活。")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.primaryText)

            Picker("范围", selection: $appViewModel.analyticsRange) {
                ForEach(AnalyticsRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(22)
        .appCardStyle()
    }

    private var summaryGrid: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 14) {
            SummaryCard(title: "平均睡眠", value: summary.averageSleepHours > 0 ? String(format: "%.1f 小时", summary.averageSleepHours) : "--", tone: AppTheme.accent)
            SummaryCard(title: "平均起床", value: formattedWake(summary.averageWakeMinutes), tone: .purple)
            SummaryCard(title: "进食完成率", value: String(format: "%.0f%%", summary.mealCompletionRate * 100), tone: .green)
            SummaryCard(title: "平均洗澡", value: String(format: "%.1f 次/天", summary.averageShowers), tone: .orange)
        }
    }

    private var sleepChart: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "睡眠趋势", subtitle: "每日睡眠时长")
            if summary.points.isEmpty {
                PlaceholderCard(text: "记录开始后，这里会自动生成趋势图。")
            } else {
                Chart(summary.points) { point in
                    LineMark(
                        x: .value("日期", point.date),
                        y: .value("睡眠", point.sleepHours)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(AppTheme.accent)

                    AreaMark(
                        x: .value("日期", point.date),
                        y: .value("睡眠", point.sleepHours)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppTheme.accent.opacity(0.28), AppTheme.accent.opacity(0.03)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                .frame(height: 220)
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .padding(.top, 8)
                .padding(.horizontal, 6)
            }
        }
        .padding(22)
        .appCardStyle()
    }

    private var mealChart: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "饮食与清洁", subtitle: "餐食完成和洗澡次数")
            if summary.points.isEmpty {
                PlaceholderCard(text: "等你记录几天之后，这里会显示完成度和频率。")
            } else {
                Chart(summary.points) { point in
                    BarMark(
                        x: .value("日期", point.date),
                        y: .value("已记录餐次", point.loggedMeals)
                    )
                    .foregroundStyle(AppTheme.accent)

                    BarMark(
                        x: .value("日期", point.date),
                        y: .value("洗澡次数", point.showers)
                    )
                    .foregroundStyle(.orange.opacity(0.75))
                }
                .frame(height: 220)
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .padding(.top, 8)
                .padding(.horizontal, 6)
            }
        }
        .padding(22)
        .appCardStyle()
    }

    private func formattedWake(_ minutes: Double?) -> String {
        guard let minutes else { return "--" }
        let hour = Int(minutes) / 60
        let minute = Int(minutes) % 60
        return String(format: "%02d:%02d", hour, minute)
    }
}

private struct SummaryCard: View {
    let title: String
    let value: String
    let tone: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.secondaryText)
            Text(value)
                .font(.system(size: 23, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.primaryText)
            RoundedRectangle(cornerRadius: 999)
                .fill(tone.opacity(0.18))
                .frame(width: 56, height: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .appCardStyle()
    }
}

private struct PlaceholderCard: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 15, weight: .medium, design: .rounded))
            .foregroundStyle(AppTheme.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(AppTheme.elevatedSurface)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

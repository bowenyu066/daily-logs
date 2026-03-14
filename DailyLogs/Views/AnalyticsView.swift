import Charts
import SwiftUI

struct AnalyticsView: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @State private var route: AnalyticsRoute?
    @State private var isShowingCustomization = false
    @State private var highlightedSleepDate: Date?

    private let summaryColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        summaryGrid
                        sleepTrendCard
                        customizationCard
                        visibleWidgetCards
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("数据")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $route) { route in
                AnalyticsDetailView(route: route, summary: summary, range: $appViewModel.analyticsRange)
            }
            .sheet(isPresented: $isShowingCustomization) {
                AnalyticsCustomizationSheet(
                    customization: appViewModel.preferences.analyticsCustomization,
                    onSave: { customization in
                        Task {
                            await appViewModel.updateAnalyticsCustomization(customization)
                        }
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private var summary: AnalyticsSummary {
        appViewModel.analyticsSummary
    }

    private var visibleMetrics: [AnalyticsMetricKind] {
        let selected = appViewModel.preferences.analyticsCustomization.visibleMetrics
        return selected.isEmpty ? AnalyticsCustomization.default.visibleMetrics : selected
    }

    private var visibleWidgets: [AnalyticsWidgetKind] {
        appViewModel.preferences.analyticsCustomization.visibleWidgets
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
        LazyVGrid(columns: summaryColumns, spacing: 12) {
            ForEach(visibleMetrics, id: \.self) { metric in
                Button {
                    route = metric.route
                } label: {
                    SummaryCard(
                        title: metric.title,
                        value: metricValue(metric),
                        tone: metricColor(metric)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var sleepTrendCard: some View {
        AnalyticsCard(title: "睡眠趋势") {
            if summary.days.compactMap(\.sleepHours).isEmpty {
                PlaceholderCard(text: "记录几天之后，这里会出现睡眠曲线。")
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    if let highlightedSleepDate,
                       let point = summary.days.first(where: { Calendar.current.isDate($0.date, inSameDayAs: highlightedSleepDate) }),
                       let sleepHours = point.sleepHours {
                        HStack {
                            Text(highlightedSleepDate, format: .dateTime.month().day())
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.secondaryText)
                            Spacer()
                            Text(String(format: "%.1f 小时", sleepHours))
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppTheme.primaryText)
                        }
                    }

                    Chart {
                        ForEach(summary.days) { point in
                            if let sleepHours = point.sleepHours {
                                LineMark(
                                    x: .value("日期", point.date),
                                    y: .value("睡眠", sleepHours)
                                )
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(AppTheme.accent)

                                AreaMark(
                                    x: .value("日期", point.date),
                                    y: .value("睡眠", sleepHours)
                                )
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [AppTheme.accent.opacity(0.24), AppTheme.accent.opacity(0.04)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )

                                if highlightedSleepDate.flatMap({ Calendar.current.isDate($0, inSameDayAs: point.date) ? point : nil }) != nil {
                                    PointMark(
                                        x: .value("日期", point.date),
                                        y: .value("睡眠", sleepHours)
                                    )
                                    .symbolSize(70)
                                    .foregroundStyle(AppTheme.accent)
                                }
                            }
                        }
                    }
                    .frame(height: 240)
                    .chartYAxis {
                        AxisMarks(position: .leading)
                    }
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            Rectangle()
                                .fill(.clear)
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            guard let plotFrame = proxy.plotFrame else { return }
                                            let origin = geometry[plotFrame].origin
                                            let xPosition = value.location.x - origin.x
                                            if let date: Date = proxy.value(atX: xPosition) {
                                                highlightedSleepDate = nearestDate(to: date, in: summary.days.map(\.date))
                                            }
                                        }
                                        .onEnded { _ in
                                            highlightedSleepDate = nil
                                        }
                                )
                        }
                    }
                }
            }
        }
    }

    private var customizationCard: some View {
        Button {
            isShowingCustomization = true
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("自定义")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.primaryText)
                    Spacer()
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                }

                if visibleWidgets.isEmpty {
                    Text("选择要摆在这里的图")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)
                } else {
                    FlowLayout(spacing: 10) {
                        ForEach(visibleWidgets) { widget in
                            Text(widget.title)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppTheme.primaryText)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(AppTheme.elevatedSurface)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            .padding(22)
            .appCardStyle()
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var visibleWidgetCards: some View {
        ForEach(visibleWidgets) { widget in
            Button {
                route = widget.route
            } label: {
                widgetPreview(widget)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func widgetPreview(_ widget: AnalyticsWidgetKind) -> some View {
        switch widget {
        case .sleepTrend:
            EmptyView()
        case .sleepDuration:
            AnalyticsCard(title: "睡眠时段") {
                SleepIntervalChart(days: summary.days, selectedDate: .constant(nil), compact: true)
            }
        case .wakeTrend:
            AnalyticsCard(title: "起床变化") {
                TimeLineChart(
                    points: summary.days.compactMap { point in
                        point.wakeMinutes.map { ChartTimeValue(date: point.date, minutes: $0) }
                    },
                    averageMinutes: summary.averageWakeMinutes,
                    tone: .orange
                )
            }
        case .bedtimeTrend:
            AnalyticsCard(title: "入睡变化") {
                TimeLineChart(
                    points: summary.days.compactMap { point in
                        point.bedtimeMinutes.map { ChartTimeValue(date: point.date, minutes: wrapForNight($0)) }
                    },
                    averageMinutes: summary.averageBedtimeMinutes.map(wrapForNight),
                    tone: .indigo
                )
            }
        case .mealCompletion:
            AnalyticsCard(title: "三餐完成率") {
                MealCompletionBreakdown(series: summary.mealSeries)
            }
        case .mealTiming:
            AnalyticsCard(title: "进餐时间") {
                MealTimingScatterChart(series: summary.mealSeries, selectedDate: .constant(nil), compact: true)
            }
        case .showerTiming:
            AnalyticsCard(title: "洗澡时间") {
                ShowerScatterChart(points: summary.showerPoints, selectedDate: .constant(nil), compact: true)
            }
        }
    }

    private func metricValue(_ metric: AnalyticsMetricKind) -> String {
        switch metric {
        case .averageSleep:
            return summary.averageSleepHours > 0 ? String(format: "%.1f 小时", summary.averageSleepHours) : "--"
        case .averageWake:
            return formatClock(summary.averageWakeMinutes)
        case .averageBedtime:
            return formatClock(summary.averageBedtimeMinutes)
        case .mealCompletion:
            return String(format: "%.0f%%", summary.defaultMealCompletionRate * 100)
        case .averageShowers:
            return String(format: "%.1f 次/天", summary.averageShowers)
        }
    }

    private func metricColor(_ metric: AnalyticsMetricKind) -> Color {
        switch metric {
        case .averageSleep: AppTheme.accent
        case .averageWake: .orange
        case .averageBedtime: .indigo
        case .mealCompletion: .green
        case .averageShowers: .teal
        }
    }

    private func formatClock(_ minutes: Double?) -> String {
        guard let minutes else { return "--" }
        let total = Int(minutes.rounded()) % (24 * 60)
        let hour = total / 60
        let minute = total % 60
        return String(format: "%02d:%02d", hour, minute)
    }

    private func wrapForNight(_ minutes: Double) -> Double {
        minutes < 18 * 60 ? minutes + 24 * 60 : minutes
    }
}

private enum AnalyticsRoute: Identifiable, Hashable {
    case widget(AnalyticsWidgetKind)

    var id: String {
        switch self {
        case let .widget(widget):
            return widget.rawValue
        }
    }
}

private extension AnalyticsMetricKind {
    var route: AnalyticsRoute {
        switch self {
        case .averageSleep:
            .widget(.sleepDuration)
        case .averageWake:
            .widget(.wakeTrend)
        case .averageBedtime:
            .widget(.bedtimeTrend)
        case .mealCompletion:
            .widget(.mealCompletion)
        case .averageShowers:
            .widget(.showerTiming)
        }
    }
}

private extension AnalyticsWidgetKind {
    var route: AnalyticsRoute { .widget(self) }
}

private struct AnalyticsDetailView: View {
    let route: AnalyticsRoute
    let summary: AnalyticsSummary
    @Binding var range: AnalyticsRange
    @State private var selectedDate: Date?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                Picker("范围", selection: $range) {
                    ForEach(AnalyticsRange.allCases) { range in
                        Text(range.title).tag(range)
                    }
                }
                .pickerStyle(.segmented)

                content
            }
            .padding(18)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var content: some View {
        switch route {
        case let .widget(widget):
            switch widget {
            case .sleepTrend:
                AnalyticsCard(title: "睡眠趋势") {
                    EmptyView()
                }
            case .sleepDuration:
                AnalyticsCard(title: "睡眠时段") {
                    SleepIntervalChart(days: summary.days, selectedDate: $selectedDate, compact: false)
                }
            case .wakeTrend:
                AnalyticsCard(title: "起床变化") {
                    TimeLineChart(
                        points: summary.days.compactMap { point in
                            point.wakeMinutes.map { ChartTimeValue(date: point.date, minutes: $0) }
                        },
                        averageMinutes: summary.averageWakeMinutes,
                        tone: .orange,
                        selectedDate: $selectedDate
                    )
                }
            case .bedtimeTrend:
                AnalyticsCard(title: "入睡变化") {
                    TimeLineChart(
                        points: summary.days.compactMap { point in
                            point.bedtimeMinutes.map { ChartTimeValue(date: point.date, minutes: wrapNight($0)) }
                        },
                        averageMinutes: summary.averageBedtimeMinutes.map(wrapNight),
                        tone: .indigo,
                        selectedDate: $selectedDate
                    )
                }
            case .mealCompletion:
                AnalyticsCard(title: "三餐完成率") {
                    VStack(alignment: .leading, spacing: 18) {
                        MealCompletionBreakdown(series: summary.mealSeries)
                        Divider()
                            .overlay(AppTheme.border)
                        MealTimingScatterChart(series: summary.mealSeries, selectedDate: $selectedDate, compact: false)
                    }
                }
            case .mealTiming:
                AnalyticsCard(title: "进餐时间") {
                    MealTimingScatterChart(series: summary.mealSeries, selectedDate: $selectedDate, compact: false)
                }
            case .showerTiming:
                AnalyticsCard(title: "洗澡时间") {
                    ShowerScatterChart(points: summary.showerPoints, selectedDate: $selectedDate, compact: false)
                }
            }
        }
    }

    private var title: String {
        switch route {
        case let .widget(widget):
            widget.title
        }
    }

    private func wrapNight(_ minutes: Double) -> Double {
        minutes < 18 * 60 ? minutes + 24 * 60 : minutes
    }
}

private struct SummaryCard: View {
    let title: String
    let value: String
    let tone: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(value)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(tone)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .padding(16)
        .appCardStyle()
    }
}

private struct AnalyticsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.primaryText)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
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
            .padding(18)
            .background(AppTheme.elevatedSurface)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct ChartTimeValue: Identifiable {
    var id: Date { date }
    var date: Date
    var minutes: Double
}

private struct TimeLineChart: View {
    let points: [ChartTimeValue]
    let averageMinutes: Double?
    let tone: Color
    @Binding var selectedDate: Date?
    var compact: Bool = false

    init(points: [ChartTimeValue], averageMinutes: Double?, tone: Color, selectedDate: Binding<Date?> = .constant(nil), compact: Bool = false) {
        self.points = points
        self.averageMinutes = averageMinutes
        self.tone = tone
        self._selectedDate = selectedDate
        self.compact = compact
    }

    var body: some View {
        if points.isEmpty {
            PlaceholderCard(text: "再多记录几天，这里会更有参考价值。")
        } else {
            VStack(alignment: .leading, spacing: 10) {
                if !compact {
                    HStack {
                        if let selectedDate,
                           let point = points.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }) {
                            Text(selectedDate, format: .dateTime.month().day())
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.secondaryText)
                            Spacer()
                            Text(formatClock(point.minutes))
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppTheme.primaryText)
                        } else if let averageMinutes {
                            Spacer()
                            Text(formatClock(averageMinutes))
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                }

                Chart {
                    if let averageMinutes {
                        RuleMark(y: .value("平均", averageMinutes))
                            .foregroundStyle(AppTheme.secondaryText.opacity(0.35))
                            .lineStyle(.init(lineWidth: 1, dash: [5, 4]))
                    }

                    ForEach(points) { point in
                        LineMark(x: .value("日期", point.date), y: .value("时间", point.minutes))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(tone)

                        PointMark(x: .value("日期", point.date), y: .value("时间", point.minutes))
                            .foregroundStyle(
                                selectedDate.flatMap { Calendar.current.isDate($0, inSameDayAs: point.date) ? tone : nil } ?? tone.opacity(compact ? 0.65 : 0.9)
                            )
                            .symbolSize(compact ? 30 : 42)
                    }
                }
                .frame(height: compact ? 190 : 260)
                .chartYScale(domain: 0...(24 * 60))
                .chartYAxis {
                    AxisMarks(position: .leading, values: stride(from: 0, through: 24 * 60, by: 240).map(Double.init)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let minutes = value.as(Double.self) {
                                Text(formatClock(minutes))
                            }
                        }
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        guard let plotFrame = proxy.plotFrame else { return }
                                        let origin = geometry[plotFrame].origin
                                        let xPosition = value.location.x - origin.x
                                        if let date: Date = proxy.value(atX: xPosition) {
                                            selectedDate = nearestDate(to: date, in: points.map(\.date))
                                        }
                                    }
                                    .onEnded { _ in
                                        if compact {
                                            selectedDate = nil
                                        }
                                    }
                            )
                    }
                }
            }
        }
    }

    private func formatClock(_ minutes: Double) -> String {
        let total = Int(minutes.rounded()) % (24 * 60)
        let hour = total / 60
        let minute = total % 60
        return String(format: "%02d:%02d", hour, minute)
    }
}

private struct SleepIntervalChart: View {
    let days: [AnalyticsDayPoint]
    @Binding var selectedDate: Date?
    var compact: Bool

    var body: some View {
        if days.compactMap(\.sleepStartMinutes).isEmpty {
            PlaceholderCard(text: "睡眠记录还不够。")
        } else {
            VStack(alignment: .leading, spacing: 10) {
                if !compact, let selected = selectedPoint {
                    HStack {
                        Text(selected.date, format: .dateTime.month().day())
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.secondaryText)
                        Spacer()
                        Text(durationText(selected.sleepHours))
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.primaryText)
                    }
                }

                Chart {
                    ForEach(days) { point in
                        if let start = point.sleepStartMinutes, let end = point.sleepEndMinutes {
                            BarMark(
                                x: .value("日期", point.date),
                                yStart: .value("入睡", start),
                                yEnd: .value("起床", end)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.indigo.opacity(0.92), AppTheme.accent.opacity(0.82)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )

                            if selectedDate.flatMap({ Calendar.current.isDate($0, inSameDayAs: point.date) ? point : nil }) != nil {
                                RuleMark(x: .value("选中", point.date))
                                    .foregroundStyle(AppTheme.primaryText.opacity(0.2))
                                    .lineStyle(.init(lineWidth: 1, dash: [4, 4]))
                            }
                        }
                    }
                }
                .frame(height: compact ? 210 : 330)
                .chartYScale(domain: (42 * 60)...(18 * 60))
                .chartYAxis {
                    AxisMarks(position: .leading, values: stride(from: 18 * 60, through: 42 * 60, by: 240).map(Double.init)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let minutes = value.as(Double.self) {
                                Text(labelForSleepClock(minutes))
                            }
                        }
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        guard let plotFrame = proxy.plotFrame else { return }
                                        let origin = geometry[plotFrame].origin
                                        let xPosition = value.location.x - origin.x
                                        if let date: Date = proxy.value(atX: xPosition) {
                                            selectedDate = nearestDate(to: date, in: days.map(\.date))
                                        }
                                    }
                                    .onEnded { _ in
                                        if compact {
                                            selectedDate = nil
                                        }
                                    }
                            )
                    }
                }
            }
        }
    }

    private var selectedPoint: AnalyticsDayPoint? {
        guard let selectedDate else { return nil }
        return days.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) })
    }

    private func durationText(_ sleepHours: Double?) -> String {
        guard let sleepHours else { return "--" }
        let minutes = Int((sleepHours * 60).rounded())
        return "\(minutes / 60)小时\(minutes % 60)分"
    }

    private func labelForSleepClock(_ minutes: Double) -> String {
        let wrapped = Int(minutes.rounded()) % (24 * 60)
        return String(format: "%02d:%02d", wrapped / 60, wrapped % 60)
    }
}

private struct MealCompletionBreakdown: View {
    let series: [MealAnalyticsSeries]

    var body: some View {
        VStack(spacing: 14) {
            ForEach(series) { item in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(item.title)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.primaryText)
                        Spacer()
                        Text(String(format: "%.0f%%", item.completionRate * 100))
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(color(for: item.key))
                    }

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(AppTheme.elevatedSurface)
                            Capsule()
                                .fill(color(for: item.key))
                                .frame(width: geometry.size.width * item.completionRate)
                        }
                    }
                    .frame(height: 10)
                }
            }
        }
    }

    private func color(for key: String) -> Color {
        chartColor(for: key)
    }
}

private struct MealTimingScatterChart: View {
    let series: [MealAnalyticsSeries]
    @Binding var selectedDate: Date?
    var compact: Bool

    var body: some View {
        if series.flatMap(\.points).isEmpty {
            PlaceholderCard(text: "再记录几餐，这里会看到你的进餐时间分布。")
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if !compact {
                    if let selectedDate {
                        selectedDateSummary(selectedDate)
                    } else {
                        averageLegend
                    }
                }

                Chart {
                    ForEach(series) { item in
                        ForEach(item.points) { point in
                            PointMark(
                                x: .value("日期", point.date),
                                y: .value("时间", point.minutes)
                            )
                            .foregroundStyle(chartColor(for: item.key))
                            .symbolSize(compact ? 28 : 44)
                        }

                        if let averageMinutes = item.averageMinutes, !compact {
                            RuleMark(y: .value(item.title, averageMinutes))
                                .foregroundStyle(chartColor(for: item.key).opacity(0.35))
                                .lineStyle(.init(lineWidth: 1, dash: [4, 4]))
                        }
                    }
                }
                .frame(height: compact ? 200 : 290)
                .chartYAxis {
                    AxisMarks(position: .leading, values: stride(from: 0, through: 24 * 60, by: 240).map(Double.init)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let minutes = value.as(Double.self) {
                                Text(clockText(minutes))
                            }
                        }
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        guard let plotFrame = proxy.plotFrame else { return }
                                        let origin = geometry[plotFrame].origin
                                        let xPosition = value.location.x - origin.x
                                        if let date: Date = proxy.value(atX: xPosition) {
                                            selectedDate = nearestDate(to: date, in: series.flatMap { $0.points.map(\.date) })
                                        }
                                    }
                                    .onEnded { _ in
                                        if compact {
                                            selectedDate = nil
                                        }
                                    }
                            )
                    }
                }
            }
        }
    }

    private var averageLegend: some View {
        FlowLayout(spacing: 10) {
            ForEach(series) { item in
                HStack(spacing: 8) {
                    Circle()
                        .fill(chartColor(for: item.key))
                        .frame(width: 8, height: 8)
                    Text(item.title)
                        .foregroundStyle(AppTheme.secondaryText)
                    if let averageMinutes = item.averageMinutes {
                        Text(clockText(averageMinutes))
                            .foregroundStyle(AppTheme.primaryText)
                    }
                }
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppTheme.elevatedSurface)
                .clipShape(Capsule())
            }
        }
    }

    @ViewBuilder
    private func selectedDateSummary(_ date: Date) -> some View {
        let items = series.compactMap { item -> (String, Double, Color)? in
            guard let point = item.points.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }) else { return nil }
            return (item.title, point.minutes, chartColor(for: item.key))
        }

        if items.isEmpty {
            Text(date, format: .dateTime.month().day())
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.secondaryText)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(date, format: .dateTime.month().day())
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)
                FlowLayout(spacing: 10) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(item.2)
                                .frame(width: 8, height: 8)
                            Text(item.0)
                                .foregroundStyle(AppTheme.secondaryText)
                            Text(clockText(item.1))
                                .foregroundStyle(AppTheme.primaryText)
                        }
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(AppTheme.elevatedSurface)
                        .clipShape(Capsule())
                    }
                }
            }
        }
    }

    private func clockText(_ minutes: Double) -> String {
        let total = Int(minutes.rounded()) % (24 * 60)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

private struct ShowerScatterChart: View {
    let points: [AnalyticsScatterPoint]
    @Binding var selectedDate: Date?
    var compact: Bool

    var body: some View {
        if points.isEmpty {
            PlaceholderCard(text: "还没有洗澡时间数据。")
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if !compact {
                    selectedHeader
                }

                Chart(points) { point in
                    PointMark(
                        x: .value("日期", point.date),
                        y: .value("时间", point.minutes)
                    )
                    .foregroundStyle(.teal)
                    .symbolSize(compact ? 28 : 44)
                }
                .frame(height: compact ? 200 : 290)
                .chartYAxis {
                    AxisMarks(position: .leading, values: stride(from: 0, through: 24 * 60, by: 240).map(Double.init)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let minutes = value.as(Double.self) {
                                Text(clockText(minutes))
                            }
                        }
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        guard let plotFrame = proxy.plotFrame else { return }
                                        let origin = geometry[plotFrame].origin
                                        let xPosition = value.location.x - origin.x
                                        if let date: Date = proxy.value(atX: xPosition) {
                                            selectedDate = nearestDate(to: date, in: points.map(\.date))
                                        }
                                    }
                                    .onEnded { _ in
                                        if compact {
                                            selectedDate = nil
                                        }
                                    }
                            )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var selectedHeader: some View {
        if let selectedDate {
            let items = points.filter { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
            if items.isEmpty {
                Text(selectedDate, format: .dateTime.month().day())
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(selectedDate, format: .dateTime.month().day())
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)
                    FlowLayout(spacing: 10) {
                        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                            Text(index == 0 ? clockText(item.minutes) : "第\(index + 1)次 \(clockText(item.minutes))")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppTheme.primaryText)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(AppTheme.elevatedSurface)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
    }

    private func clockText(_ minutes: Double) -> String {
        let total = Int(minutes.rounded()) % (24 * 60)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

private struct AnalyticsCustomizationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var customization: AnalyticsCustomization
    let onSave: (AnalyticsCustomization) -> Void

    init(customization: AnalyticsCustomization, onSave: @escaping (AnalyticsCustomization) -> Void) {
        _customization = State(initialValue: customization)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            List {
                Section("卡片") {
                    ForEach(AnalyticsMetricKind.allCases) { metric in
                        ToggleRow(
                            title: metric.title,
                            isOn: customization.visibleMetrics.contains(metric)
                        ) {
                            toggleMetric(metric)
                        }
                    }
                }

                Section("图表") {
                    ForEach(customization.visibleWidgets) { widget in
                        HStack {
                            Image(systemName: "checkmark.square.fill")
                                .foregroundStyle(AppTheme.accent)
                            Text(widget.title)
                                .foregroundStyle(AppTheme.primaryText)
                        }
                    }
                    .onMove { source, destination in
                        customization.visibleWidgets.move(fromOffsets: source, toOffset: destination)
                    }

                    ForEach(availableWidgets) { widget in
                        ToggleRow(title: widget.title, isOn: false) {
                            customization.visibleWidgets.append(widget)
                        }
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden)
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("自定义")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(AppTheme.secondaryText)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        onSave(customization)
                        dismiss()
                    }
                    .foregroundStyle(AppTheme.accent)
                }
            }
        }
        .presentationBackground(AppTheme.background)
    }

    private var availableWidgets: [AnalyticsWidgetKind] {
        AnalyticsWidgetKind.allCases.filter { !customization.visibleWidgets.contains($0) && $0 != .sleepTrend }
    }

    private func toggleMetric(_ metric: AnalyticsMetricKind) {
        if let index = customization.visibleMetrics.firstIndex(of: metric) {
            customization.visibleMetrics.remove(at: index)
        } else {
            customization.visibleMetrics.append(metric)
        }
    }
}

private struct ToggleRow: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isOn ? AppTheme.accent : AppTheme.secondaryText)
                Text(title)
                    .foregroundStyle(AppTheme.primaryText)
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .listRowBackground(AppTheme.surface)
    }
}

private struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    init(spacing: CGFloat = 8, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content
        }
    }
}

private func nearestDate(to date: Date, in candidates: [Date]) -> Date? {
    candidates.min(by: { abs($0.timeIntervalSince(date)) < abs($1.timeIntervalSince(date)) })
}

private func chartColor(for key: String) -> Color {
    switch key {
    case MealKind.breakfast.rawValue:
        return .orange
    case MealKind.lunch.rawValue:
        return .green
    case MealKind.dinner.rawValue:
        return .blue
    default:
        let palette: [Color] = [.pink, .mint, .teal, .purple, .cyan]
        return palette[abs(key.hashValue) % palette.count]
    }
}

import Charts
import SwiftUI

struct AnalyticsView: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @State private var route: AnalyticsRoute?
    @State private var isShowingCustomization = false
    @State private var isShowingCustomRange = false
    @State private var highlightedSleepDate: Date?
    @State private var highlightedSleepIntervalDate: Date?
    @State private var highlightedWakeDate: Date?
    @State private var highlightedBedtimeDate: Date?
    @State private var highlightedMealDate: Date?
    @State private var highlightedShowerDate: Date?

    private let summaryColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        summaryGrid
                        visibleWidgetCards
                        customizationCard
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("数据")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $route) { route in
                AnalyticsDetailView(
                    route: route,
                    summary: summary,
                    range: $appViewModel.analyticsRange,
                    customRange: $appViewModel.analyticsCustomDateRange,
                    allowedRange: appViewModel.availableDateRange
                )
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
            .sheet(isPresented: $isShowingCustomRange) {
                AnalyticsDateRangeSheet(
                    dateRange: appViewModel.analyticsCustomDateRange,
                    allowedRange: appViewModel.availableDateRange
                ) { range in
                    appViewModel.updateAnalyticsCustomDateRange(range)
                }
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
        let selected = appViewModel.preferences.analyticsCustomization.visibleWidgets
        return selected.isEmpty ? AnalyticsCustomization.default.visibleWidgets : selected
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
            .onChange(of: appViewModel.analyticsRange) { _, newValue in
                if newValue == .custom {
                    isShowingCustomRange = true
                }
            }
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
            SleepTrendChart(days: summary.days, selectedDate: $highlightedSleepDate, compact: true)
        }
    }

    private var customizationCard: some View {
        Button {
            isShowingCustomization = true
        } label: {
            HStack(spacing: 10) {
                Text("自定义")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
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
            sleepTrendCard
        case .sleepDuration:
            AnalyticsCard(title: "睡眠时段") {
                SleepIntervalChart(days: summary.days, selectedDate: $highlightedSleepIntervalDate, compact: true)
            }
        case .wakeTrend:
            AnalyticsCard(title: "起床变化") {
                TimeLineChart(
                    points: summary.days.compactMap { point in
                        point.wakeMinutes.map { ChartTimeValue(date: point.date, minutes: $0) }
                    },
                    averageMinutes: summary.averageWakeMinutes,
                    tone: .orange,
                    selectedDate: $highlightedWakeDate,
                    compact: true
                )
            }
        case .bedtimeTrend:
            AnalyticsCard(title: "入睡变化") {
                TimeLineChart(
                    points: summary.days.compactMap { point in
                        point.bedtimeMinutes.map { ChartTimeValue(date: point.date, minutes: wrapForNight($0)) }
                    },
                    averageMinutes: summary.averageBedtimeMinutes.map(wrapForNight),
                    tone: .indigo,
                    selectedDate: $highlightedBedtimeDate,
                    compact: true,
                    usesWrappedClock: true
                )
            }
        case .mealCompletion:
            AnalyticsCard(title: "三餐完成率") {
                MealCompletionBreakdown(series: summary.mealSeries)
            }
        case .mealTiming:
            AnalyticsCard(title: "进餐时间") {
                MealTimingScatterChart(series: summary.mealSeries, selectedDate: $highlightedMealDate, compact: true)
            }
        case .showerTiming:
            AnalyticsCard(title: "洗澡时间") {
                ShowerScatterChart(points: summary.showerPoints, selectedDate: $highlightedShowerDate, compact: true)
            }
        }
    }

    private func metricValue(_ metric: AnalyticsMetricKind) -> String {
        switch metric {
        case .averageSleep:
            return formattedDuration(hours: summary.averageSleepHours)
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

    private func formattedDuration(hours: Double) -> String {
        guard hours > 0 else { return "--" }
        let totalMinutes = Int((hours * 60).rounded())
        return "\(totalMinutes / 60)小时\(totalMinutes % 60)分"
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
    @Binding var customRange: ClosedRange<Date>
    let allowedRange: ClosedRange<Date>
    @State private var selectedDate: Date?
    @State private var isShowingCustomRange = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                Picker("范围", selection: $range) {
                    ForEach(AnalyticsRange.allCases) { range in
                        Text(range.title).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: range) { _, newValue in
                    if newValue == .custom {
                        isShowingCustomRange = true
                    }
                }

                content
            }
            .padding(18)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingCustomRange) {
            AnalyticsDateRangeSheet(dateRange: customRange, allowedRange: allowedRange) { range in
                customRange = range
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch route {
        case let .widget(widget):
            switch widget {
            case .sleepTrend:
                AnalyticsCard(title: "睡眠趋势") {
                    SleepTrendChart(days: summary.days, selectedDate: $selectedDate, compact: false)
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
                        selectedDate: $selectedDate,
                        usesWrappedClock: true
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
        VStack(spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.secondaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .multilineTextAlignment(.center)

            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(tone)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .center)
        .padding(.horizontal, 10)
        .padding(.vertical, 18)
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

private struct SleepTrendChart: View {
    let days: [AnalyticsDayPoint]
    @Binding var selectedDate: Date?
    var compact: Bool

    var body: some View {
        if days.compactMap(\.sleepHours).isEmpty {
            PlaceholderCard(text: "记录几天之后，这里会出现睡眠曲线。")
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ChartDisplayZone(
                    ratio: selectedRatio,
                    cardWidth: 148,
                    height: 68,
                    idle: {
                        AverageTextBlock(
                            title: "平均睡眠",
                            value: durationText(averageSleepHours),
                            tone: AppTheme.accent
                        )
                    },
                    selected: {
                        fixedChartCallout {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(selectedPoint?.date ?? .now, format: .dateTime.month().day())
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(AppTheme.secondaryText)
                                Text(durationText(selectedPoint?.sleepHours))
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                    .foregroundStyle(AppTheme.primaryText)
                            }
                        }
                    }
                )

                Chart {
                    if let averageSleepHours {
                        RuleMark(y: .value("平均", averageSleepHours))
                            .foregroundStyle(AppTheme.accent.opacity(0.65))
                            .lineStyle(.init(lineWidth: 1.4, dash: [5, 4]))
                    }

                    ForEach(days) { point in
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

                            if selectedDate.flatMap({ Calendar.current.isDate($0, inSameDayAs: point.date) ? point : nil }) != nil {
                                RuleMark(x: .value("日期", point.date))
                                    .foregroundStyle(AppTheme.primaryText.opacity(0.38))
                                    .lineStyle(.init(lineWidth: 1, dash: [4, 4]))

                                RuleMark(y: .value("睡眠", sleepHours))
                                    .foregroundStyle(AppTheme.primaryText.opacity(0.38))
                                    .lineStyle(.init(lineWidth: 1, dash: [4, 4]))

                                PointMark(
                                    x: .value("日期", point.date),
                                    y: .value("睡眠", sleepHours)
                                )
                                .symbolSize(compact ? 58 : 72)
                                .foregroundStyle(AppTheme.accent)
                            }
                        }
                    }
                }
                .frame(height: compact ? 240 : 300)
                .chartYScale(domain: adaptiveDomain)
                .chartXScale(range: .plotDimension(startPadding: 14, endPadding: 14))
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
                                        updateSelection(at: value.location, proxy: proxy, geometry: geometry)
                                    }
                            )
                            .simultaneousGesture(
                                SpatialTapGesture()
                                    .onEnded { value in
                                        updateSelection(at: value.location, proxy: proxy, geometry: geometry)
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

    private var averageSleepHours: Double? {
        let values = days.compactMap(\.sleepHours)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private var selectedRatio: CGFloat? {
        guard let selectedPoint else { return nil }
        let points = days.filter { $0.sleepHours != nil }
        guard let index = points.firstIndex(where: { Calendar.current.isDate($0.date, inSameDayAs: selectedPoint.date) }) else { return nil }
        return CGFloat(index) / CGFloat(max(points.count - 1, 1))
    }

    private var adaptiveDomain: ClosedRange<Double> {
        let values = days.compactMap(\.sleepHours) + (averageSleepHours.map { [$0] } ?? [])
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 10
        let lower = max(0, floor((minValue - 0.5) * 2) / 2)
        let upper = ceil((maxValue + 0.5) * 2) / 2
        return lower...max(lower + 1, upper)
    }

    private func durationText(_ hours: Double?) -> String {
        guard let hours else { return "--" }
        let totalMinutes = Int((hours * 60).rounded())
        return "\(totalMinutes / 60)小时\(totalMinutes % 60)分"
    }

    private func updateSelection(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else {
            selectedDate = nil
            return
        }
        let plotRect = geometry[plotFrame]
        guard plotRect.contains(location) else {
            selectedDate = nil
            return
        }
        let xPosition = location.x - plotRect.origin.x
        if let date: Date = proxy.value(atX: xPosition) {
            selectedDate = nearestDate(to: date, in: days.compactMap { $0.sleepHours == nil ? nil : $0.date })
        } else {
            selectedDate = nil
        }
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
    var usesWrappedClock: Bool = false

    init(points: [ChartTimeValue], averageMinutes: Double?, tone: Color, selectedDate: Binding<Date?> = .constant(nil), compact: Bool = false, usesWrappedClock: Bool = false) {
        self.points = points
        self.averageMinutes = averageMinutes
        self.tone = tone
        self._selectedDate = selectedDate
        self.compact = compact
        self.usesWrappedClock = usesWrappedClock
    }

    var body: some View {
        if points.isEmpty {
            PlaceholderCard(text: "再多记录几天，这里会更有参考价值。")
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ChartDisplayZone(
                    ratio: selectedRatio,
                    cardWidth: 136,
                    height: 68,
                    idle: {
                        AverageTextBlock(
                            title: averageTitle,
                            value: averageMinutes.map(formatClock) ?? "--",
                            tone: tone
                        )
                    },
                    selected: {
                        fixedChartCallout {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(selectedPoint?.date ?? .now, format: .dateTime.month().day())
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(AppTheme.secondaryText)
                                Text(selectedPoint.map { formatClock($0.minutes) } ?? "--")
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                    .foregroundStyle(AppTheme.primaryText)
                            }
                        }
                    }
                )

                Chart {
                    if let averageMinutes {
                        RuleMark(y: .value("平均", averageMinutes))
                            .foregroundStyle(tone.opacity(0.65))
                            .lineStyle(.init(lineWidth: 1.4, dash: [5, 4]))
                    }

                    ForEach(points) { point in
                        LineMark(x: .value("日期", point.date), y: .value("时间", point.minutes))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(tone)

                        PointMark(x: .value("日期", point.date), y: .value("时间", point.minutes))
                            .foregroundStyle(tone.opacity(compact ? 0.65 : 0.9))
                            .symbolSize(compact ? 30 : 42)

                        if selectedDate.flatMap({ Calendar.current.isDate($0, inSameDayAs: point.date) ? point : nil }) != nil {
                            RuleMark(x: .value("日期", point.date))
                                .foregroundStyle(AppTheme.primaryText.opacity(0.38))
                                .lineStyle(.init(lineWidth: 1, dash: [4, 4]))

                            RuleMark(y: .value("时间", point.minutes))
                                .foregroundStyle(AppTheme.primaryText.opacity(0.38))
                                .lineStyle(.init(lineWidth: 1, dash: [4, 4]))

                            PointMark(x: .value("日期", point.date), y: .value("时间", point.minutes))
                                .foregroundStyle(tone)
                                .symbolSize(compact ? 54 : 70)
                        }
                    }
                }
                .frame(height: compact ? 190 : 260)
                .chartYScale(domain: adaptiveDomain)
                .chartXScale(range: .plotDimension(startPadding: 14, endPadding: 14))
                .chartYAxis {
                    AxisMarks(position: .leading, values: axisValues) { value in
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
                                        updateSelection(at: value.location, proxy: proxy, geometry: geometry)
                                    }
                            )
                            .simultaneousGesture(
                                SpatialTapGesture()
                                    .onEnded { value in
                                        updateSelection(at: value.location, proxy: proxy, geometry: geometry)
                                    }
                            )
                    }
                }
            }
        }
    }

    private var selectedPoint: ChartTimeValue? {
        guard let selectedDate else { return nil }
        return points.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) })
    }

    private var selectedRatio: CGFloat? {
        guard let selectedPoint, let index = points.firstIndex(where: { Calendar.current.isDate($0.date, inSameDayAs: selectedPoint.date) }) else { return nil }
        return CGFloat(index) / CGFloat(max(points.count - 1, 1))
    }

    private var averageTitle: String {
        usesWrappedClock ? "平均入睡" : "平均起床"
    }

    private var adaptiveDomain: ClosedRange<Double> {
        let values = points.map(\.minutes) + (averageMinutes.map { [$0] } ?? [])
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 24 * 60
        let padding = usesWrappedClock ? 45.0 : 30.0
        let lower = max(0, floor((minValue - padding) / 15) * 15)
        let upper = min(usesWrappedClock ? 36 * 60 : 24 * 60, ceil((maxValue + padding) / 15) * 15)
        return lower...max(lower + 30, upper)
    }

    private var axisValues: [Double] {
        let lower = adaptiveDomain.lowerBound
        let upper = adaptiveDomain.upperBound
        let step = max(30.0, ceil((upper - lower) / 4 / 15) * 15)
        return stride(from: lower, through: upper, by: step).map { $0 }
    }

    private func formatClock(_ minutes: Double) -> String {
        let total = Int(minutes.rounded()) % (24 * 60)
        let hour = total / 60
        let minute = total % 60
        return String(format: "%02d:%02d", hour, minute)
    }

    private func updateSelection(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else {
            selectedDate = nil
            return
        }
        let plotRect = geometry[plotFrame]
        guard plotRect.contains(location) else {
            selectedDate = nil
            return
        }
        let xPosition = location.x - plotRect.origin.x
        if let date: Date = proxy.value(atX: xPosition) {
            selectedDate = nearestDate(to: date, in: points.map(\.date))
        } else {
            selectedDate = nil
        }
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
                ChartDisplayZone(
                    ratio: selectedRatio,
                    cardWidth: 220,
                    height: 88,
                    idle: {
                        Color.clear
                    },
                    selected: {
                        fixedChartCallout {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(selectedPoint?.date ?? .now, format: .dateTime.month().day())
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(AppTheme.secondaryText)
                                Text(durationText(selectedPoint?.sleepHours))
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundStyle(AppTheme.primaryText)
                                HStack(spacing: 18) {
                                    calloutMetric(label: "入睡", value: labelForSleepClock(selectedPoint?.sleepStartMinutes))
                                    calloutMetric(label: "起床", value: labelForSleepClock(selectedPoint?.sleepEndMinutes))
                                }
                            }
                        }
                    }
                )

                Chart {
                    ForEach(days) { point in
                        if let start = point.sleepStartMinutes, let end = point.sleepEndMinutes {
                            let plottedStart = plotValue(for: start)
                            let plottedEnd = plotValue(for: end)
                            BarMark(
                                x: .value("日期", point.date),
                                yStart: .value("入睡", plottedStart),
                                yEnd: .value("起床", plottedEnd)
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
                                    .foregroundStyle(AppTheme.primaryText.opacity(0.38))
                                    .lineStyle(.init(lineWidth: 1, dash: [4, 4]))

                                RuleMark(y: .value("时刻", plotValue(for: midPoint(start: start, end: end))))
                                    .foregroundStyle(AppTheme.primaryText.opacity(0.38))
                                    .lineStyle(.init(lineWidth: 1, dash: [4, 4]))

                                PointMark(
                                    x: .value("日期", point.date),
                                    y: .value("时刻", plotValue(for: midPoint(start: start, end: end)))
                                )
                                .foregroundStyle(AppTheme.accent)
                                .symbolSize(compact ? 50 : 70)
                            }
                        }
                    }
                }
                .frame(height: compact ? 210 : 330)
                .chartPlotStyle { plotArea in
                    plotArea.padding(.top, compact ? 8 : 12)
                }
                .chartYScale(domain: adaptivePlotDomain)
                .chartXScale(range: .plotDimension(startPadding: 14, endPadding: 14))
                .chartYAxis {
                    AxisMarks(position: .leading, values: axisValues) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let minutes = value.as(Double.self) {
                                Text(labelForSleepClock(unplotValue(minutes)))
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
                                        updateSelection(at: value.location, proxy: proxy, geometry: geometry)
                                    }
                            )
                            .simultaneousGesture(
                                SpatialTapGesture()
                                    .onEnded { value in
                                        updateSelection(at: value.location, proxy: proxy, geometry: geometry)
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

    private var selectedRatio: CGFloat? {
        guard let selectedPoint else { return nil }
        let points = days.filter { $0.sleepStartMinutes != nil && $0.sleepEndMinutes != nil }
        guard let index = points.firstIndex(where: { Calendar.current.isDate($0.date, inSameDayAs: selectedPoint.date) }) else { return nil }
        return CGFloat(index) / CGFloat(max(points.count - 1, 1))
    }

    private var sleepValues: [Double] {
        days.flatMap { point in
            [point.sleepStartMinutes, point.sleepEndMinutes].compactMap { $0 }
        }
    }

    private var adaptivePlotDomain: ClosedRange<Double> {
        let minValue = sleepValues.min() ?? 18 * 60
        let maxValue = sleepValues.max() ?? 32 * 60
        let lower = max(18 * 60, floor((minValue - 30) / 15) * 15)
        let upper = min(42 * 60, ceil((maxValue + 45) / 15) * 15)
        return plotValue(for: upper)...plotValue(for: lower)
    }

    private var axisValues: [Double] {
        let lower = sleepValues.min() ?? 18 * 60
        let upper = sleepValues.max() ?? 32 * 60
        let start = max(18 * 60, floor((lower - 30) / 60) * 60)
        let end = min(42 * 60, ceil((upper + 45) / 60) * 60)
        return stride(from: start, through: end, by: 120).map(plotValue(for:))
    }

    private func plotValue(for minutes: Double) -> Double {
        42 * 60 - minutes
    }

    private func unplotValue(_ plotted: Double) -> Double {
        42 * 60 - plotted
    }

    private func midPoint(start: Double, end: Double) -> Double {
        (start + end) / 2
    }

    private func labelForSleepClock(_ minutes: Double?) -> String {
        guard let minutes, minutes.isFinite else { return "--" }
        let wrapped = Int(minutes.rounded()) % (24 * 60)
        return String(format: "%02d:%02d", wrapped / 60, wrapped % 60)
    }

    private func updateSelection(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else {
            selectedDate = nil
            return
        }
        let plotRect = geometry[plotFrame]
        guard plotRect.contains(location) else {
            selectedDate = nil
            return
        }
        let xPosition = location.x - plotRect.origin.x
        if let date: Date = proxy.value(atX: xPosition) {
            selectedDate = nearestDate(to: date, in: days.compactMap { ($0.sleepStartMinutes != nil && $0.sleepEndMinutes != nil) ? $0.date : nil })
        } else {
            selectedDate = nil
        }
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
                ChartDisplayZone(
                    ratio: selectedRatio,
                    cardWidth: 190,
                    height: 92,
                    idle: {
                        averageMealSummary
                    },
                    selected: {
                        fixedChartCallout {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(selectedDate ?? .now, format: .dateTime.month().day())
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(AppTheme.secondaryText)
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(Array((selectedItems ?? []).enumerated()), id: \.offset) { _, item in
                                        HStack(spacing: 8) {
                                            Circle()
                                                .fill(item.2)
                                                .frame(width: 8, height: 8)
                                            Text(item.0)
                                                .foregroundStyle(AppTheme.secondaryText)
                                            Spacer(minLength: 8)
                                            Text(clockText(item.1))
                                                .foregroundStyle(AppTheme.primaryText)
                                        }
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    }
                                }
                            }
                        }
                    }
                )

                Chart {
                    ForEach(series) { item in
                        ForEach(item.points) { point in
                            PointMark(
                                x: .value("日期", point.date),
                                y: .value("时间", point.minutes)
                            )
                            .foregroundStyle(chartColor(for: item.key))
                            .symbolSize(compact ? 28 : 44)

                            if selectedDate.flatMap({ Calendar.current.isDate($0, inSameDayAs: point.date) ? point : nil }) != nil {
                                RuleMark(x: .value("日期", point.date))
                                    .foregroundStyle(AppTheme.primaryText.opacity(0.18))
                                    .lineStyle(.init(lineWidth: 1, dash: [4, 4]))

                                RuleMark(y: .value("时间", point.minutes))
                                    .foregroundStyle(AppTheme.primaryText.opacity(0.18))
                                    .lineStyle(.init(lineWidth: 1, dash: [4, 4]))

                                PointMark(
                                    x: .value("日期", point.date),
                                    y: .value("时间", point.minutes)
                                )
                                .foregroundStyle(chartColor(for: item.key))
                                .symbolSize(compact ? 52 : 64)
                            }
                        }

                        if let averageMinutes = item.averageMinutes {
                            RuleMark(y: .value(item.title, averageMinutes))
                                .foregroundStyle(chartColor(for: item.key).opacity(0.65))
                                .lineStyle(.init(lineWidth: 1.4, dash: [4, 4]))
                        }
                    }
                }
                .frame(height: compact ? 200 : 290)
                .chartYScale(domain: adaptiveDomain)
                .chartXScale(range: .plotDimension(startPadding: 14, endPadding: 14))
                .chartYAxis {
                    AxisMarks(position: .leading, values: axisValues) { value in
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
                                        updateSelection(at: value.location, proxy: proxy, geometry: geometry)
                                    }
                            )
                            .simultaneousGesture(
                                SpatialTapGesture()
                                    .onEnded { value in
                                        updateSelection(at: value.location, proxy: proxy, geometry: geometry)
                                    }
                            )
                    }
                }
            }
        }
    }

    private var selectedItems: [(String, Double, Color)]? {
        guard let selectedDate else { return nil }
        let items = series.compactMap { item -> (String, Double, Color)? in
            guard let point = item.points.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }) else { return nil }
            return (item.title, point.minutes, chartColor(for: item.key))
        }
        return items.isEmpty ? nil : items
    }

    private var selectedRatio: CGFloat? {
        guard let selectedDate else { return nil }
        let allDates = series.flatMap { $0.points.map(\.date) }.sorted()
        guard let index = allDates.firstIndex(where: { Calendar.current.isDate($0, inSameDayAs: selectedDate) }) else { return nil }
        return CGFloat(index) / CGFloat(max(allDates.count - 1, 1))
    }

    private var averageMealSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(series.filter { $0.averageMinutes != nil }) { item in
                HStack(spacing: 8) {
                    Circle()
                        .fill(chartColor(for: item.key))
                        .frame(width: 8, height: 8)
                    Text(item.title)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)
                    Text(clockText(item.averageMinutes ?? 0))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(chartColor(for: item.key))
                }
            }
        }
    }

    private func clockText(_ minutes: Double) -> String {
        let total = Int(minutes.rounded()) % (24 * 60)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private var adaptiveDomain: ClosedRange<Double> {
        let values = series.flatMap { $0.points.map(\.minutes) } + series.compactMap(\.averageMinutes)
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 24 * 60
        let lower = max(0, floor((minValue - 30) / 15) * 15)
        let upper = min(24 * 60, ceil((maxValue + 30) / 15) * 15)
        return lower...max(lower + 30, upper)
    }

    private var axisValues: [Double] {
        let lower = adaptiveDomain.lowerBound
        let upper = adaptiveDomain.upperBound
        let step = max(30.0, ceil((upper - lower) / 4 / 15) * 15)
        return stride(from: lower, through: upper, by: step).map { $0 }
    }

    private func updateSelection(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else {
            selectedDate = nil
            return
        }
        let plotRect = geometry[plotFrame]
        guard plotRect.contains(location) else {
            selectedDate = nil
            return
        }
        let xPosition = location.x - plotRect.origin.x
        if let date: Date = proxy.value(atX: xPosition) {
            selectedDate = nearestDate(to: date, in: series.flatMap { $0.points.map(\.date) })
        } else {
            selectedDate = nil
        }
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
                ChartDisplayZone(
                    ratio: selectedRatio,
                    cardWidth: 180,
                    height: 84,
                    idle: {
                        AverageTextBlock(
                            title: "平均洗澡时间",
                            value: averageMinutes.map(clockText) ?? "--",
                            tone: .teal
                        )
                    },
                    selected: {
                        fixedChartCallout {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(selectedDate ?? .now, format: .dateTime.month().day())
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(AppTheme.secondaryText)
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(Array((selectedItems ?? []).enumerated()), id: \.offset) { index, item in
                                        HStack(spacing: 8) {
                                            Circle()
                                                .fill(Color.teal)
                                                .frame(width: 8, height: 8)
                                            Text(index == 0 ? "第1次" : "第\(index + 1)次")
                                                .foregroundStyle(AppTheme.secondaryText)
                                            Spacer(minLength: 8)
                                            Text(clockText(item.minutes))
                                                .foregroundStyle(AppTheme.primaryText)
                                        }
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    }
                                }
                            }
                        }
                    }
                )

                Chart {
                    if let averageMinutes {
                        RuleMark(y: .value("平均", averageMinutes))
                            .foregroundStyle(Color.teal.opacity(0.65))
                            .lineStyle(.init(lineWidth: 1.4, dash: [4, 4]))
                    }

                    ForEach(points) { point in
                        PointMark(
                            x: .value("日期", point.date),
                            y: .value("时间", point.minutes)
                        )
                        .foregroundStyle(.teal)
                        .symbolSize(compact ? 28 : 44)

                        if selectedDate.flatMap({ Calendar.current.isDate($0, inSameDayAs: point.date) ? point : nil }) != nil {
                            RuleMark(x: .value("日期", point.date))
                                .foregroundStyle(AppTheme.primaryText.opacity(0.18))
                                .lineStyle(.init(lineWidth: 1, dash: [4, 4]))

                            RuleMark(y: .value("时间", point.minutes))
                                .foregroundStyle(AppTheme.primaryText.opacity(0.18))
                                .lineStyle(.init(lineWidth: 1, dash: [4, 4]))

                            PointMark(
                                x: .value("日期", point.date),
                                y: .value("时间", point.minutes)
                            )
                            .foregroundStyle(.teal)
                            .symbolSize(compact ? 52 : 64)
                        }
                    }
                }
                .frame(height: compact ? 200 : 290)
                .chartYScale(domain: adaptiveDomain)
                .chartXScale(range: .plotDimension(startPadding: 14, endPadding: 14))
                .chartYAxis {
                    AxisMarks(position: .leading, values: axisValues) { value in
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
                                        updateSelection(at: value.location, proxy: proxy, geometry: geometry)
                                    }
                            )
                            .simultaneousGesture(
                                SpatialTapGesture()
                                    .onEnded { value in
                                        updateSelection(at: value.location, proxy: proxy, geometry: geometry)
                                    }
                            )
                    }
                }
            }
        }
    }

    private var selectedItems: [AnalyticsScatterPoint]? {
        guard let selectedDate else { return nil }
        let items = points.filter { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
        return items.isEmpty ? nil : items
    }

    private var selectedRatio: CGFloat? {
        guard let selectedDate, let index = points.map(\.date).sorted().firstIndex(where: { Calendar.current.isDate($0, inSameDayAs: selectedDate) }) else { return nil }
        return CGFloat(index) / CGFloat(max(points.count - 1, 1))
    }

    private func clockText(_ minutes: Double) -> String {
        let total = Int(minutes.rounded()) % (24 * 60)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private var adaptiveDomain: ClosedRange<Double> {
        let minValue = points.map(\.minutes).min() ?? 0
        let maxValue = points.map(\.minutes).max() ?? 24 * 60
        let lower = max(0, floor((minValue - 30) / 15) * 15)
        let upper = min(24 * 60, ceil((maxValue + 30) / 15) * 15)
        return lower...max(lower + 30, upper)
    }

    private var averageMinutes: Double? {
        guard !points.isEmpty else { return nil }
        return points.map(\.minutes).reduce(0, +) / Double(points.count)
    }

    private var axisValues: [Double] {
        let lower = adaptiveDomain.lowerBound
        let upper = adaptiveDomain.upperBound
        let step = max(30.0, ceil((upper - lower) / 4 / 15) * 15)
        return stride(from: lower, through: upper, by: step).map { $0 }
    }

    private func updateSelection(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else {
            selectedDate = nil
            return
        }
        let plotRect = geometry[plotFrame]
        guard plotRect.contains(location) else {
            selectedDate = nil
            return
        }
        let xPosition = location.x - plotRect.origin.x
        if let date: Date = proxy.value(atX: xPosition) {
            selectedDate = nearestDate(to: date, in: points.map(\.date))
        } else {
            selectedDate = nil
        }
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
                        ToggleRow(title: widget.title, isOn: true) {
                            customization.visibleWidgets.removeAll { $0 == widget }
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
        AnalyticsWidgetKind.allCases.filter { !customization.visibleWidgets.contains($0) }
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

private struct AnalyticsDateRangeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var startDate: Date
    @State private var endDate: Date
    let allowedRange: ClosedRange<Date>
    let onSave: (ClosedRange<Date>) -> Void

    init(dateRange: ClosedRange<Date>, allowedRange: ClosedRange<Date>, onSave: @escaping (ClosedRange<Date>) -> Void) {
        _startDate = State(initialValue: dateRange.lowerBound)
        _endDate = State(initialValue: dateRange.upperBound)
        self.allowedRange = allowedRange
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            List {
                DatePicker("开始", selection: $startDate, in: allowedRange, displayedComponents: .date)
                    .listRowBackground(AppTheme.surface)
                DatePicker("结束", selection: $endDate, in: allowedRange, displayedComponents: .date)
                    .listRowBackground(AppTheme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("时间范围")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(AppTheme.secondaryText)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        onSave(min(startDate, endDate).startOfDay...max(startDate, endDate).startOfDay)
                        dismiss()
                    }
                    .foregroundStyle(AppTheme.accent)
                }
            }
        }
        .presentationBackground(AppTheme.background)
    }
}

private struct ChartDisplayZone<Idle: View, Selected: View>: View {
    let ratio: CGFloat?
    let cardWidth: CGFloat
    let height: CGFloat
    let idle: () -> Idle
    let selected: () -> Selected

    init(
        ratio: CGFloat?,
        cardWidth: CGFloat,
        height: CGFloat,
        @ViewBuilder idle: @escaping () -> Idle,
        @ViewBuilder selected: @escaping () -> Selected
    ) {
        self.ratio = ratio
        self.cardWidth = cardWidth
        self.height = height
        self.idle = idle
        self.selected = selected
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                if let ratio {
                    let width = min(cardWidth, geometry.size.width)
                    selected()
                        .frame(width: width)
                        .offset(x: clampedOffset(width: width, in: geometry.size.width, ratio: ratio))
                } else {
                    idle()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
            }
        }
        .frame(height: height)
    }

    private func clampedOffset(width: CGFloat, in containerWidth: CGFloat, ratio: CGFloat) -> CGFloat {
        let proposed = containerWidth * ratio - width / 2
        return min(max(0, proposed), max(0, containerWidth - width))
    }
}

private struct AverageTextBlock: View {
    let title: String
    let value: String
    let tone: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.secondaryText)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(tone)
        }
    }
}

private func fixedChartCallout<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    content()
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
        .frame(maxWidth: .infinity, alignment: .center)
}

private func averageTag(_ value: String, tone: Color) -> some View {
    Text(value)
        .font(.system(size: 11, weight: .bold, design: .rounded))
        .foregroundStyle(tone)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tone.opacity(0.12))
        .clipShape(Capsule())
}

private func calloutMetric(label: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        Text(label)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(AppTheme.secondaryText)
        Text(value)
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(AppTheme.primaryText)
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

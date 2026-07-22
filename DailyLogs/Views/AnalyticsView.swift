import Charts
import MapKit
import SwiftUI

struct MemoryView: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @State private var isShowingCustomRange = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                if appViewModel.canDisplayAnalytics {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 24) {
                            header
                            MealMemoriesSection(items: mealMemoryItems)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                        .padding(.bottom, 96)
                    }
                } else {
                    VStack {
                        PlaceholderCard(
                            text: NSLocalizedString("满7天后解锁记忆页", comment: "")
                        )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .padding(.horizontal, 18)
                }
            }
            .navigationTitle(NSLocalizedString("记忆", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
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

    private var analyticsDateBounds: ClosedRange<Date> {
        AnalyticsCalculator.visibleDateBounds(
            range: appViewModel.analyticsRange,
            customRange: appViewModel.analyticsRange == .custom ? appViewModel.analyticsCustomDateRange : nil,
            today: appViewModel.logicalToday
        )
    }

    private var mealMemoryItems: [MealMemoryItem] {
        appViewModel.allRecords
            .filter { record in
                record.date >= analyticsDateBounds.lowerBound && record.date <= analyticsDateBounds.upperBound
            }
            .flatMap { record in
                record.meals.compactMap { meal -> MealMemoryItem? in
                    guard meal.effectiveStatus(on: record.date) == .logged else { return nil }
                    return MealMemoryItem(recordDate: record.date, meal: meal)
                }
            }
            .sorted { $0.sortDate > $1.sortDate }
    }

    private var header: some View {
        Picker(NSLocalizedString("范围", comment: ""), selection: $appViewModel.analyticsRange) {
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
        .sectionStyle()
    }
}

struct AnalyticsView: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @State private var route: AnalyticsRoute?
    @State private var isShowingCustomization = false
    @State private var isShowingCustomRange = false
    @State private var highlightedSleepDate: Date?
    @State private var highlightedSleepIntervalDate: Date?
    @State private var highlightedWakeDate: Date?
    @State private var highlightedBedtimeDate: Date?
    @State private var highlightedLightSleepDate: Date?
    @State private var highlightedDeepSleepDate: Date?
    @State private var highlightedREMSleepDate: Date?
    @State private var highlightedMealDate: Date?
    @State private var highlightedShowerDate: Date?
    @State private var highlightedBowelMovementDate: Date?

    private let summaryColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                if appViewModel.canDisplayAnalytics {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 24) {
                            header
                            summaryGrid
                            Divider()
                            visibleWidgetCards
                            customizationCard
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                    }
                } else {
                    VStack {
                        PlaceholderCard(
                            text: NSLocalizedString("满7天后解锁数据趋势", comment: "")
                        )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .padding(.horizontal, 18)
                }
            }
            .navigationTitle(NSLocalizedString("数据", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $route) { route in
                switch route {
                case .frequencyCalendar:
                    HabitFrequencyCalendarDetailView(
                        records: appViewModel.allRecords,
                        preferences: appViewModel.preferences,
                        allowedRange: appViewModel.availableDateRange,
                        initialMonth: appViewModel.selectedDate,
                        visibleHomeSections: appViewModel.preferences.visibleHomeSections
                    )
                case .widget:
                    AnalyticsDetailView(
                        route: route,
                        summary: summary,
                        range: $appViewModel.analyticsRange,
                        customRange: $appViewModel.analyticsCustomDateRange,
                        allowedRange: appViewModel.availableDateRange
                    )
                }
            }
            .sheet(isPresented: $isShowingCustomization) {
                AnalyticsCustomizationSheet(
                    customization: appViewModel.preferences.analyticsCustomization,
                    visibleHomeSections: appViewModel.preferences.visibleHomeSections,
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
        let base = selected.isEmpty ? AnalyticsCustomization.default.visibleMetrics : selected
        let sections = appViewModel.preferences.visibleHomeSections
        return base.filter { metric in
            guard let required = metric.requiredSection else { return true }
            return sections.contains(required)
        }
    }

    private var visibleWidgets: [AnalyticsWidgetKind] {
        let selected = appViewModel.preferences.analyticsCustomization.visibleWidgets
        let base = selected.isEmpty ? AnalyticsCustomization.default.visibleWidgets : selected
        let sections = appViewModel.preferences.visibleHomeSections
        return base.filter { widget in
            guard let required = widget.requiredSection else { return true }
            return sections.contains(required)
        }
    }

    private var visibleFrequencyMetrics: [HabitFrequencyMetric] {
        let sections = appViewModel.preferences.visibleHomeSections
        return HabitFrequencyMetric.allCases.filter { sections.contains($0.requiredSection) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(NSLocalizedString("规律不是为了控制你，而是为了更轻松地生活。", comment: ""))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.primaryText)

            Picker(NSLocalizedString("范围", comment: ""), selection: $appViewModel.analyticsRange) {
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

            if !visibleFrequencyMetrics.isEmpty {
                Button {
                    route = .frequencyCalendar
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar")
                            .font(.system(size: 15, weight: .semibold))
                        Text(NSLocalizedString("频率月历", comment: ""))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(AppTheme.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .sectionStyle()
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
                        detail: nil,
                        tone: metricColor(metric)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var sleepTrendCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: NSLocalizedString("睡眠总时长", comment: ""), subtitle: nil)
            SleepTrendChart(
                days: summary.days,
                averageSleepHours: summary.averageSleepHours,
                previousAverageSleepHours: summary.previousAverageSleepHours,
                selectedDate: $highlightedSleepDate,
                compact: true
            )
        }
        .sectionStyle()
    }

    private var customizationCard: some View {
        Button {
            isShowingCustomization = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                Text(NSLocalizedString("自定义", comment: ""))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.accent)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var visibleWidgetCards: some View {
        ForEach(visibleWidgets.filter { $0 != .habitFrequencyCalendar }) { widget in
            Button {
                route = widget.route
            } label: {
                widgetPreview(widget)
            }
            .buttonStyle(.plain)

            Divider()
        }
    }

    @ViewBuilder
    private func widgetPreview(_ widget: AnalyticsWidgetKind) -> some View {
        switch widget {
        case .sleepTrend:
            sleepTrendCard
        case .sleepDuration:
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: NSLocalizedString("睡眠时段", comment: ""), subtitle: nil)
                SleepIntervalChart(days: summary.days, selectedDate: $highlightedSleepIntervalDate, compact: true)
            }
            .sectionStyle()
        case .wakeTrend:
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: NSLocalizedString("起床时间", comment: ""), subtitle: nil)
                TimeLineChart(
                    points: summary.days.compactMap { point in
                        point.wakeMinutes.map { ChartTimeValue(date: point.date, minutes: $0) }
                    },
                    domainDates: summary.days.map(\.date),
                    averageMinutes: summary.averageWakeMinutes,
                    previousAverageMinutes: summary.previousAverageWakeMinutes,
                    tone: .orange,
                    selectedDate: $highlightedWakeDate,
                    compact: true
                )
            }
            .sectionStyle()
        case .bedtimeTrend:
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: NSLocalizedString("入睡时间", comment: ""), subtitle: nil)
                TimeLineChart(
                    points: summary.days.compactMap { point in
                        point.bedtimeMinutes.map { ChartTimeValue(date: point.date, minutes: wrapForNight($0)) }
                    },
                    domainDates: summary.days.map(\.date),
                    averageMinutes: summary.averageBedtimeMinutes.map(wrapForNight),
                    previousAverageMinutes: summary.previousAverageBedtimeMinutes.map(wrapForNight),
                    tone: .indigo,
                    selectedDate: $highlightedBedtimeDate,
                    compact: true,
                    usesWrappedClock: true
                )
            }
            .sectionStyle()
        case .lightSleepTrend:
            sleepStageCard(title: NSLocalizedString("浅睡时长", comment: ""), keyPath: \.lightSleepHours, average: summary.averageLightSleepHours, previousAverage: summary.previousAverageLightSleepHours, tone: SleepStage.light.color, selectedDate: $highlightedLightSleepDate, compact: true)
        case .deepSleepTrend:
            sleepStageCard(title: NSLocalizedString("深睡时长", comment: ""), keyPath: \.deepSleepHours, average: summary.averageDeepSleepHours, previousAverage: summary.previousAverageDeepSleepHours, tone: SleepStage.deep.color, selectedDate: $highlightedDeepSleepDate, compact: true)
        case .remSleepTrend:
            sleepStageCard(title: NSLocalizedString("REM 时长", comment: ""), keyPath: \.remSleepHours, average: summary.averageREMSleepHours, previousAverage: summary.previousAverageREMSleepHours, tone: SleepStage.rem.color, selectedDate: $highlightedREMSleepDate, compact: true)
        case .mealCompletion:
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: NSLocalizedString("三餐完成率", comment: ""), subtitle: nil)
                MealCompletionBreakdown(series: summary.mealSeries)
            }
            .sectionStyle()
        case .mealTiming:
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: NSLocalizedString("进餐时间", comment: ""), subtitle: nil)
                MealTimingScatterChart(series: summary.mealSeries, domainDates: summary.days.map(\.date), selectedDate: $highlightedMealDate, compact: true)
            }
            .sectionStyle()
        case .showerTiming:
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: NSLocalizedString("洗澡时间", comment: ""), subtitle: nil)
                ShowerScatterChart(
                    points: summary.showerPoints,
                    domainDates: summary.days.map(\.date),
                    averageMinutes: summary.averageShowerMinutes,
                    selectedDate: $highlightedShowerDate,
                    compact: true
                )
            }
            .sectionStyle()
        case .bowelMovementTiming:
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: NSLocalizedString("排便时间", comment: ""), subtitle: nil)
                BowelMovementScatterChart(
                    points: summary.bowelMovementPoints,
                    domainDates: summary.days.map(\.date),
                    averageMinutes: summary.averageBowelMovementMinutes,
                    selectedDate: $highlightedBowelMovementDate,
                    compact: true
                )
            }
            .sectionStyle()
        case .sexualActivityFrequency:
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: NSLocalizedString("性生活频率", comment: ""), subtitle: nil)
                SexualActivityBarChart(
                    weeklyData: summary.sexualActivityWeeklyData,
                    averagePerWeek: summary.averageSexualActivity,
                    compact: true
                )
            }
            .sectionStyle()
        case .habitFrequencyCalendar:
            EmptyView()
        }
    }

    private func sleepStageCard(title: String, keyPath: KeyPath<AnalyticsDayPoint, Double?>, average: Double?, previousAverage: Double?, tone: Color, selectedDate: Binding<Date?>, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: title, subtitle: nil)
            DurationLineChart(
                points: summary.days.compactMap { point in
                    point[keyPath: keyPath].map { ChartDurationValue(date: point.date, hours: $0) }
                },
                domainDates: summary.days.map(\.date),
                averageHours: average,
                previousAverageHours: previousAverage,
                tone: tone,
                selectedDate: selectedDate,
                compact: compact
            )
        }
        .sectionStyle()
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
            guard let rate = summary.defaultMealCompletionRate else { return "--" }
            return String(format: "%.0f%%", rate * 100)
        case .averageShowers:
            guard let showers = summary.averageShowers else { return "--" }
            return String(format: NSLocalizedString("%.1f 次/天", comment: ""), showers)
        case .averageBowelMovements:
            guard let bm = summary.averageBowelMovements else { return "--" }
            return String(format: NSLocalizedString("%.1f 次/天", comment: ""), bm)
        case .averageSexualActivity:
            guard let sa = summary.averageSexualActivity else { return "--" }
            return String(format: NSLocalizedString("%.1f 次/周", comment: ""), sa)
        }
    }

    private func metricColor(_ metric: AnalyticsMetricKind) -> Color {
        switch metric {
        case .averageSleep: AppTheme.accent
        case .averageWake: .orange
        case .averageBedtime: .indigo
        case .mealCompletion: .green
        case .averageShowers: .teal
        case .averageBowelMovements: .brown
        case .averageSexualActivity: .pink
        }
    }

    private func formatClock(_ minutes: Double?) -> String {
        guard let minutes else { return "--" }
        let fullDay = 24 * 60
        let total = ((Int(minutes.rounded()) % fullDay) + fullDay) % fullDay
        let hour = total / 60
        let minute = total % 60
        return String(format: "%02d:%02d", hour, minute)
    }

    private func formattedDuration(hours: Double?) -> String {
        guard let hours, hours > 0 else { return "--" }
        let totalMinutes = Int((hours * 60).rounded())
        return String(format: NSLocalizedString("%d小时%d分", comment: ""), totalMinutes / 60, totalMinutes % 60)
    }

    private func wrapForNight(_ minutes: Double) -> Double {
        minutes < 18 * 60 ? minutes + 24 * 60 : minutes
    }
}

private enum AnalyticsRoute: Identifiable, Hashable {
    case frequencyCalendar
    case widget(AnalyticsWidgetKind)

    var id: String {
        switch self {
        case .frequencyCalendar:
            return "frequencyCalendar"
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
        case .averageBowelMovements:
            .widget(.bowelMovementTiming)
        case .averageSexualActivity:
            .widget(.sexualActivityFrequency)
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
                Picker(NSLocalizedString("范围", comment: ""), selection: $range) {
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
            .padding(.bottom, 96)
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
        case .frequencyCalendar:
            EmptyView()
        case let .widget(widget):
            switch widget {
            case .sleepTrend:
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: NSLocalizedString("睡眠总时长", comment: ""), subtitle: nil)
                    SleepTrendChart(
                        days: summary.days,
                        averageSleepHours: summary.averageSleepHours,
                        previousAverageSleepHours: summary.previousAverageSleepHours,
                        selectedDate: $selectedDate,
                        compact: false
                    )
                }
            case .sleepDuration:
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: NSLocalizedString("睡眠时段", comment: ""), subtitle: nil)
                    SleepIntervalChart(days: summary.days, selectedDate: $selectedDate, compact: false)
                }
            case .wakeTrend:
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: NSLocalizedString("起床时间", comment: ""), subtitle: nil)
                    TimeLineChart(
                        points: summary.days.compactMap { point in
                            point.wakeMinutes.map { ChartTimeValue(date: point.date, minutes: $0) }
                        },
                        domainDates: summary.days.map(\.date),
                        averageMinutes: summary.averageWakeMinutes,
                        previousAverageMinutes: summary.previousAverageWakeMinutes,
                        tone: .orange,
                        selectedDate: $selectedDate
                    )
                }
            case .bedtimeTrend:
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: NSLocalizedString("入睡时间", comment: ""), subtitle: nil)
                    TimeLineChart(
                        points: summary.days.compactMap { point in
                            point.bedtimeMinutes.map { ChartTimeValue(date: point.date, minutes: wrapNight($0)) }
                        },
                        domainDates: summary.days.map(\.date),
                        averageMinutes: summary.averageBedtimeMinutes.map(wrapNight),
                        previousAverageMinutes: summary.previousAverageBedtimeMinutes.map(wrapNight),
                        tone: .indigo,
                        selectedDate: $selectedDate,
                        usesWrappedClock: true
                    )
                }
            case .lightSleepTrend:
                sleepStageDetailCard(title: NSLocalizedString("浅睡时长", comment: ""), keyPath: \.lightSleepHours, average: summary.averageLightSleepHours, previousAverage: summary.previousAverageLightSleepHours, tone: SleepStage.light.color)
            case .deepSleepTrend:
                sleepStageDetailCard(title: NSLocalizedString("深睡时长", comment: ""), keyPath: \.deepSleepHours, average: summary.averageDeepSleepHours, previousAverage: summary.previousAverageDeepSleepHours, tone: SleepStage.deep.color)
            case .remSleepTrend:
                sleepStageDetailCard(title: NSLocalizedString("REM 时长", comment: ""), keyPath: \.remSleepHours, average: summary.averageREMSleepHours, previousAverage: summary.previousAverageREMSleepHours, tone: SleepStage.rem.color)
            case .mealCompletion:
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: NSLocalizedString("三餐完成率", comment: ""), subtitle: nil)
                    VStack(alignment: .leading, spacing: 18) {
                        MealCompletionBreakdown(series: summary.mealSeries)
                        Divider()
                            .overlay(AppTheme.border)
                        MealTimingScatterChart(series: summary.mealSeries, domainDates: summary.days.map(\.date), selectedDate: $selectedDate, compact: false)
                    }
                }
            case .mealTiming:
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: NSLocalizedString("进餐时间", comment: ""), subtitle: nil)
                    MealTimingScatterChart(series: summary.mealSeries, domainDates: summary.days.map(\.date), selectedDate: $selectedDate, compact: false)
                }
            case .showerTiming:
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: NSLocalizedString("洗澡时间", comment: ""), subtitle: nil)
                    ShowerScatterChart(
                        points: summary.showerPoints,
                        domainDates: summary.days.map(\.date),
                        averageMinutes: summary.averageShowerMinutes,
                        selectedDate: $selectedDate,
                        compact: false
                    )
                }
            case .bowelMovementTiming:
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: NSLocalizedString("排便时间", comment: ""), subtitle: nil)
                    BowelMovementScatterChart(
                        points: summary.bowelMovementPoints,
                        domainDates: summary.days.map(\.date),
                        averageMinutes: summary.averageBowelMovementMinutes,
                        selectedDate: $selectedDate,
                        compact: false
                    )
                }
            case .sexualActivityFrequency:
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: NSLocalizedString("性生活频率", comment: ""), subtitle: nil)
                    SexualActivityBarChart(
                        weeklyData: summary.sexualActivityWeeklyData,
                        averagePerWeek: summary.averageSexualActivity,
                        compact: false
                    )
                }
            case .habitFrequencyCalendar:
                EmptyView()
            }
        }
    }

    private var title: String {
        switch route {
        case .frequencyCalendar:
            NSLocalizedString("频率月历", comment: "")
        case let .widget(widget):
            widget.title
        }
    }

    private func sleepStageDetailCard(title: String, keyPath: KeyPath<AnalyticsDayPoint, Double?>, average: Double?, previousAverage: Double?, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: title, subtitle: nil)
            DurationLineChart(
                points: summary.days.compactMap { point in
                    point[keyPath: keyPath].map { ChartDurationValue(date: point.date, hours: $0) }
                },
                domainDates: summary.days.map(\.date),
                averageHours: average,
                previousAverageHours: previousAverage,
                tone: tone,
                selectedDate: $selectedDate,
                compact: false
            )
        }
    }

    private func wrapNight(_ minutes: Double) -> Double {
        minutes < 18 * 60 ? minutes + 24 * 60 : minutes
    }
}

private struct SummaryCard: View {
    let title: String
    let value: String
    let detail: String?
    let tone: Color

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.secondaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .multilineTextAlignment(.center)

            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(tone)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .multilineTextAlignment(.center)

            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .center)
        .padding(.horizontal, 10)
        .padding(.vertical, 18)
        .background(AppTheme.mutedFill)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
    let averageSleepHours: Double?
    let previousAverageSleepHours: Double?
    @Binding var selectedDate: Date?
    var compact: Bool

    var body: some View {
        if days.compactMap(\.sleepHours).isEmpty {
            PlaceholderCard(text: NSLocalizedString("记录几天之后，这里会出现睡眠曲线。", comment: ""))
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ChartDisplayZone(
                    ratio: selectedRatio,
                    cardWidth: 148,
                    height: 68,
                    idle: {
                        AverageTextBlock(
                            title: NSLocalizedString("平均睡眠", comment: ""),
                            value: durationText(averageSleepHours),
                            tone: AppTheme.accent,
                            trend: durationTrendDescriptor(current: averageSleepHours, previous: previousAverageSleepHours)
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
                        RuleMark(y: .value(NSLocalizedString("平均", comment: ""), averageSleepHours))
                            .foregroundStyle(AppTheme.accent.opacity(0.72))
                            .lineStyle(.init(lineWidth: 3, dash: [7, 5]))
                    }

                    ForEach(days) { point in
                        if let sleepHours = point.sleepHours {
                            LineMark(
                                x: .value(NSLocalizedString("日期", comment: ""), point.date),
                                y: .value(NSLocalizedString("睡眠", comment: ""), sleepHours)
                            )
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(AppTheme.accent)

                            PointMark(
                                x: .value(NSLocalizedString("日期", comment: ""), point.date),
                                y: .value(NSLocalizedString("睡眠", comment: ""), sleepHours)
                            )
                            .foregroundStyle(AppTheme.accent)
                            .symbolSize(compact ? 34 : 46)

                            PointMark(
                                x: .value(NSLocalizedString("日期", comment: ""), point.date),
                                y: .value(NSLocalizedString("睡眠", comment: ""), sleepHours)
                            )
                            .foregroundStyle(AppTheme.background)
                            .symbolSize(compact ? 12 : 18)

                            if selectedDate.flatMap({ Calendar.current.isDate($0, inSameDayAs: point.date) ? point : nil }) != nil {
                                RuleMark(x: .value(NSLocalizedString("日期", comment: ""), point.date))
                                    .foregroundStyle(AppTheme.primaryText.opacity(0.5))
                                    .lineStyle(.init(lineWidth: 3, dash: [7, 5]))

                                RuleMark(y: .value(NSLocalizedString("睡眠", comment: ""), sleepHours))
                                    .foregroundStyle(AppTheme.primaryText.opacity(0.5))
                                    .lineStyle(.init(lineWidth: 3, dash: [7, 5]))

                                PointMark(
                                    x: .value(NSLocalizedString("日期", comment: ""), point.date),
                                    y: .value(NSLocalizedString("睡眠", comment: ""), sleepHours)
                                )
                                .symbolSize(compact ? 58 : 72)
                                .foregroundStyle(AppTheme.accent)
                            }
                        }
                    }
                }
                .frame(height: compact ? 240 : 300)
                .chartYScale(domain: adaptiveDomain)
                .analyticsChartXScale(domain: chartDateDomain(for: domainDates))
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartOverlay { proxy in
                    chartSelectionOverlay(proxy: proxy) { location, geometry in
                        updateSelection(at: location, proxy: proxy, geometry: geometry)
                    }
                }
            }
        }
    }

    private var selectedPoint: AnalyticsDayPoint? {
        guard let selectedDate else { return nil }
        return days.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) })
    }

    private var selectedRatio: CGFloat? {
        chartSelectionRatio(selectedDate: selectedDate, in: domainDates)
    }

    private var domainDates: [Date] {
        days.map(\.date)
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
        return String(format: NSLocalizedString("%d小时%d分", comment: ""), totalMinutes / 60, totalMinutes % 60)
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
            selectedDate = nearestDate(to: date, in: domainDates)
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
    let domainDates: [Date]
    let averageMinutes: Double?
    let previousAverageMinutes: Double?
    let tone: Color
    @Binding var selectedDate: Date?
    var compact: Bool = false
    var usesWrappedClock: Bool = false

    init(points: [ChartTimeValue], domainDates: [Date], averageMinutes: Double?, previousAverageMinutes: Double? = nil, tone: Color, selectedDate: Binding<Date?> = .constant(nil), compact: Bool = false, usesWrappedClock: Bool = false) {
        self.points = points
        self.domainDates = domainDates
        self.averageMinutes = averageMinutes
        self.previousAverageMinutes = previousAverageMinutes
        self.tone = tone
        self._selectedDate = selectedDate
        self.compact = compact
        self.usesWrappedClock = usesWrappedClock
    }

    var body: some View {
        if points.isEmpty {
            PlaceholderCard(text: NSLocalizedString("再多记录几天，这里会更有参考价值。", comment: ""))
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
                            tone: tone,
                            trend: clockTrendDescriptor(current: averageMinutes, previous: previousAverageMinutes)
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
                        RuleMark(y: .value(NSLocalizedString("平均", comment: ""), plotValue(for: averageMinutes)))
                            .foregroundStyle(tone.opacity(0.72))
                            .lineStyle(.init(lineWidth: 3, dash: [7, 5]))
                    }

                    ForEach(points) { point in
                        LineMark(x: .value(NSLocalizedString("日期", comment: ""), point.date), y: .value(NSLocalizedString("时间", comment: ""), plotValue(for: point.minutes)))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(tone)

                        PointMark(x: .value(NSLocalizedString("日期", comment: ""), point.date), y: .value(NSLocalizedString("时间", comment: ""), plotValue(for: point.minutes)))
                            .foregroundStyle(tone)
                            .symbolSize(compact ? 34 : 46)

                        PointMark(x: .value(NSLocalizedString("日期", comment: ""), point.date), y: .value(NSLocalizedString("时间", comment: ""), plotValue(for: point.minutes)))
                            .foregroundStyle(AppTheme.background)
                            .symbolSize(compact ? 12 : 18)

                        if selectedDate.flatMap({ Calendar.current.isDate($0, inSameDayAs: point.date) ? point : nil }) != nil {
                            RuleMark(x: .value(NSLocalizedString("日期", comment: ""), point.date))
                                .foregroundStyle(AppTheme.primaryText.opacity(0.5))
                                .lineStyle(.init(lineWidth: 3, dash: [7, 5]))

                            RuleMark(y: .value(NSLocalizedString("时间", comment: ""), plotValue(for: point.minutes)))
                                .foregroundStyle(AppTheme.primaryText.opacity(0.5))
                                .lineStyle(.init(lineWidth: 3, dash: [7, 5]))

                            PointMark(x: .value(NSLocalizedString("日期", comment: ""), point.date), y: .value(NSLocalizedString("时间", comment: ""), plotValue(for: point.minutes)))
                                .foregroundStyle(tone)
                                .symbolSize(compact ? 54 : 70)
                        }
                    }
                }
                .frame(height: compact ? (usesWrappedClock ? 214 : 190) : 260)
                .chartPlotStyle { plotArea in
                    plotArea
                        .padding(.top, 18)
                        .padding(.bottom, usesWrappedClock ? 8 : 0)
                }
                .chartYScale(domain: adaptiveDomain)
                .analyticsChartXScale(domain: chartDateDomain(for: selectionDates))
                .chartYAxis {
                    AxisMarks(position: .leading, values: axisValues) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let plotted = value.as(Double.self) {
                                Text(formatClock(unplotValue(plotted)))
                            }
                        }
                    }
                }
                .chartOverlay { proxy in
                    chartSelectionOverlay(proxy: proxy) { location, geometry in
                        updateSelection(at: location, proxy: proxy, geometry: geometry)
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
        chartSelectionRatio(selectedDate: selectedDate, in: selectionDates)
    }

    private var selectionDates: [Date] {
        domainDates.isEmpty ? points.map(\.date) : domainDates
    }

    private var averageTitle: String {
        usesWrappedClock ? NSLocalizedString("平均入睡", comment: "") : NSLocalizedString("平均起床", comment: "")
    }

    private var adaptiveDomain: ClosedRange<Double> {
        let values = points.map(\.minutes) + (averageMinutes.map { [$0] } ?? [])
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 24 * 60
        let padding = usesWrappedClock ? 75.0 : 30.0
        let lower = max(0, floor((minValue - padding) / 15) * 15)
        let upper = min(usesWrappedClock ? 36 * 60 : 24 * 60, ceil((maxValue + padding) / 15) * 15)
        return plotValue(for: upper)...plotValue(for: lower)
    }

    private var axisValues: [Double] {
        let values = points.map(\.minutes) + (averageMinutes.map { [$0] } ?? [])
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? (usesWrappedClock ? 36 * 60 : 24 * 60)
        let padding = usesWrappedClock ? 75.0 : 30.0
        let lower = max(0, floor((minValue - padding) / 60) * 60)
        let upper = min(usesWrappedClock ? 36 * 60 : 24 * 60, ceil((maxValue + padding) / 60) * 60)
        return stride(from: lower, through: upper, by: 120).map(plotValue(for:))
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
            selectedDate = nearestDate(to: date, in: selectionDates)
        } else {
            selectedDate = nil
        }
    }

    private var plotUpperBound: Double {
        usesWrappedClock ? 36 * 60 : 24 * 60
    }

    private func plotValue(for minutes: Double) -> Double {
        plotUpperBound - minutes
    }

    private func unplotValue(_ plotted: Double) -> Double {
        plotUpperBound - plotted
    }
}

private struct SleepIntervalChart: View {
    let days: [AnalyticsDayPoint]
    @Binding var selectedDate: Date?
    var compact: Bool

    var body: some View {
        if days.compactMap(\.sleepStartMinutes).isEmpty {
            PlaceholderCard(text: NSLocalizedString("睡眠记录还不够。", comment: ""))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ChartDisplayZone(
                    ratio: selectedRatio,
                    cardWidth: 188,
                    height: selectedPoint == nil ? (compact ? 24 : 28) : (compact ? 116 : 126),
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
                                    calloutMetric(label: NSLocalizedString("入睡", comment: ""), value: labelForSleepClock(selectedPoint?.sleepStartMinutes))
                                    calloutMetric(label: NSLocalizedString("起床", comment: ""), value: labelForSleepClock(selectedPoint?.sleepEndMinutes))
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
                                x: .value(NSLocalizedString("日期", comment: ""), point.date),
                                yStart: .value(NSLocalizedString("入睡", comment: ""), plottedStart),
                                yEnd: .value(NSLocalizedString("起床", comment: ""), plottedEnd)
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
                                RuleMark(x: .value(NSLocalizedString("选中", comment: ""), point.date))
                                    .foregroundStyle(AppTheme.primaryText.opacity(0.5))
                                    .lineStyle(.init(lineWidth: 3, dash: [7, 5]))

                                PointMark(
                                    x: .value(NSLocalizedString("日期", comment: ""), point.date),
                                    y: .value(NSLocalizedString("时刻", comment: ""), plotValue(for: (start + end) / 2))
                                )
                                .foregroundStyle(AppTheme.accent)
                                .symbolSize(compact ? 50 : 70)
                            }
                        }
                    }
                }
                .frame(height: compact ? 210 : 330)
                .chartPlotStyle { plotArea in
                    plotArea.padding(.top, compact ? 14 : 18)
                }
                .chartYScale(domain: adaptivePlotDomain)
                .analyticsChartXScale(domain: chartDateDomain(for: domainDates))
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
                    chartSelectionOverlay(proxy: proxy) { location, geometry in
                        updateSelection(at: location, proxy: proxy, geometry: geometry)
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
        return String(format: NSLocalizedString("%d小时%d分", comment: ""), minutes / 60, minutes % 60)
    }

    private var selectedRatio: CGFloat? {
        chartSelectionRatio(selectedDate: selectedDate, in: domainDates)
    }

    private var domainDates: [Date] {
        days.map(\.date)
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
            selectedDate = nearestDate(to: date, in: domainDates)
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
    let domainDates: [Date]
    @Binding var selectedDate: Date?
    var compact: Bool

    var body: some View {
        if series.flatMap(\.points).isEmpty {
            PlaceholderCard(text: NSLocalizedString("再记录几餐，这里会看到你的进餐时间分布。", comment: ""))
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ChartDisplayZone(
                    ratio: selectedRatio,
                    cardWidth: 184,
                    height: displayZoneHeight,
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
                                x: .value(NSLocalizedString("日期", comment: ""), point.date),
                                y: .value(NSLocalizedString("时间", comment: ""), plotValue(point.minutes))
                            )
                            .foregroundStyle(chartColor(for: item.key))
                            .symbolSize(compact ? 28 : 44)

                            if selectedDate.flatMap({ Calendar.current.isDate($0, inSameDayAs: point.date) ? point : nil }) != nil {
                                RuleMark(x: .value(NSLocalizedString("日期", comment: ""), point.date))
                                    .foregroundStyle(AppTheme.primaryText.opacity(0.5))
                                    .lineStyle(.init(lineWidth: 3, dash: [7, 5]))

                                RuleMark(y: .value(NSLocalizedString("时间", comment: ""), plotValue(point.minutes)))
                                    .foregroundStyle(AppTheme.primaryText.opacity(0.5))
                                    .lineStyle(.init(lineWidth: 3, dash: [7, 5]))

                                PointMark(
                                    x: .value(NSLocalizedString("日期", comment: ""), point.date),
                                    y: .value(NSLocalizedString("时间", comment: ""), plotValue(point.minutes))
                                )
                                .foregroundStyle(chartColor(for: item.key))
                                .symbolSize(compact ? 52 : 64)
                            }
                        }

                        if item.showsAverage, let averageMinutes = item.averageMinutes {
                            RuleMark(y: .value(item.title, plotValue(averageMinutes)))
                                .foregroundStyle(chartColor(for: item.key).opacity(0.72))
                                .lineStyle(.init(lineWidth: 3, dash: [7, 5]))
                        }
                    }
                }
                .frame(height: compact ? 200 : 290)
                .chartYScale(domain: adaptiveDomain)
                .analyticsChartXScale(domain: chartDateDomain(for: selectionDates))
                .chartYAxis {
                    AxisMarks(position: .leading, values: axisValues) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let plotted = value.as(Double.self) {
                                Text(clockText(unplotValue(plotted)))
                            }
                        }
                    }
                }
                .chartOverlay { proxy in
                    chartSelectionOverlay(proxy: proxy) { location, geometry in
                        updateSelection(at: location, proxy: proxy, geometry: geometry)
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
        chartSelectionRatio(selectedDate: selectedDate, in: selectionDates)
    }

    private var selectionDates: [Date] {
        if !domainDates.isEmpty {
            return domainDates
        }
        return series.flatMap { $0.points.map(\.date) }
    }

    private var averageMealSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(averageSeries) { item in
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

    private var averageSeries: [MealAnalyticsSeries] {
        series.filter { $0.showsAverage && $0.averageMinutes != nil }
    }

    private var displayZoneHeight: CGFloat {
        let lineCount = max(
            selectedItems?.count ?? 0,
            averageSeries.count
        )
        let clampedLines = max(1, min(lineCount, compact ? 5 : 6))
        return CGFloat(18 + clampedLines * 22)
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
        return plotValue(upper)...plotValue(lower)
    }

    private var axisValues: [Double] {
        let values = series.flatMap { $0.points.map(\.minutes) } + series.compactMap(\.averageMinutes)
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 24 * 60
        let lower = max(0, floor((minValue - 30) / 60) * 60)
        let upper = min(24 * 60, ceil((maxValue + 30) / 60) * 60)
        return stride(from: lower, through: upper, by: 120).map(plotValue)
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
            selectedDate = nearestDate(to: date, in: selectionDates)
        } else {
            selectedDate = nil
        }
    }

    private func plotValue(_ minutes: Double) -> Double {
        24 * 60 - minutes
    }

    private func unplotValue(_ plotted: Double) -> Double {
        24 * 60 - plotted
    }
}

private struct ShowerScatterChart: View {
    let points: [AnalyticsScatterPoint]
    let domainDates: [Date]
    let averageMinutes: Double?
    @Binding var selectedDate: Date?
    var compact: Bool

    var body: some View {
        if points.isEmpty {
            PlaceholderCard(text: NSLocalizedString("还没有洗澡时间数据。", comment: ""))
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ChartDisplayZone(
                    ratio: selectedRatio,
                    cardWidth: 180,
                    height: 84,
                    idle: {
                        AverageTextBlock(
                            title: NSLocalizedString("平均洗澡时间", comment: ""),
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
                                            Text(String(format: NSLocalizedString("第%d次", comment: ""), index + 1))
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
                        RuleMark(y: .value(NSLocalizedString("平均", comment: ""), plotValue(averageMinutes)))
                            .foregroundStyle(Color.teal.opacity(0.72))
                            .lineStyle(.init(lineWidth: 3, dash: [7, 5]))
                    }

                    ForEach(points) { point in
                        PointMark(
                            x: .value(NSLocalizedString("日期", comment: ""), point.date),
                            y: .value(NSLocalizedString("时间", comment: ""), plotValue(point.minutes))
                        )
                        .foregroundStyle(.teal)
                        .symbolSize(compact ? 28 : 44)

                        if selectedDate.flatMap({ Calendar.current.isDate($0, inSameDayAs: point.date) ? point : nil }) != nil {
                            RuleMark(x: .value(NSLocalizedString("日期", comment: ""), point.date))
                                .foregroundStyle(AppTheme.primaryText.opacity(0.5))
                                .lineStyle(.init(lineWidth: 3, dash: [7, 5]))

                            RuleMark(y: .value(NSLocalizedString("时间", comment: ""), plotValue(point.minutes)))
                                .foregroundStyle(AppTheme.primaryText.opacity(0.5))
                                .lineStyle(.init(lineWidth: 3, dash: [7, 5]))

                            PointMark(
                                x: .value(NSLocalizedString("日期", comment: ""), point.date),
                                y: .value(NSLocalizedString("时间", comment: ""), plotValue(point.minutes))
                            )
                            .foregroundStyle(.teal)
                            .symbolSize(compact ? 52 : 64)
                        }
                    }
                }
                .frame(height: compact ? 200 : 290)
                .chartYScale(domain: adaptiveDomain)
                .analyticsChartXScale(domain: chartDateDomain(for: selectionDates))
                .chartYAxis {
                    AxisMarks(position: .leading, values: axisValues) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let plotted = value.as(Double.self) {
                                Text(clockText(unplotValue(plotted)))
                            }
                        }
                    }
                }
                .chartOverlay { proxy in
                    chartSelectionOverlay(proxy: proxy) { location, geometry in
                        updateSelection(at: location, proxy: proxy, geometry: geometry)
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
        chartSelectionRatio(selectedDate: selectedDate, in: selectionDates)
    }

    private var selectionDates: [Date] {
        domainDates.isEmpty ? points.map(\.date) : domainDates
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
        return plotValue(upper)...plotValue(lower)
    }

    private var axisValues: [Double] {
        let minValue = points.map(\.minutes).min() ?? 0
        let maxValue = points.map(\.minutes).max() ?? 24 * 60
        let lower = max(0, floor((minValue - 30) / 60) * 60)
        let upper = min(24 * 60, ceil((maxValue + 30) / 60) * 60)
        return stride(from: lower, through: upper, by: 120).map(plotValue)
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
            selectedDate = nearestDate(to: date, in: selectionDates)
        } else {
            selectedDate = nil
        }
    }

    private func plotValue(_ minutes: Double) -> Double {
        24 * 60 - minutes
    }

    private func unplotValue(_ plotted: Double) -> Double {
        24 * 60 - plotted
    }
}

private struct BowelMovementScatterChart: View {
    let points: [AnalyticsScatterPoint]
    let domainDates: [Date]
    let averageMinutes: Double?
    @Binding var selectedDate: Date?
    var compact: Bool

    var body: some View {
        if points.isEmpty {
            PlaceholderCard(text: NSLocalizedString("还没有排便时间数据。", comment: ""))
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ChartDisplayZone(
                    ratio: selectedRatio,
                    cardWidth: 180,
                    height: 84,
                    idle: {
                        AverageTextBlock(
                            title: NSLocalizedString("平均排便时间", comment: ""),
                            value: averageMinutes.map(clockText) ?? "--",
                            tone: .brown
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
                                                .fill(Color.brown)
                                                .frame(width: 8, height: 8)
                                            Text(String(format: NSLocalizedString("第%d次", comment: ""), index + 1))
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
                        RuleMark(y: .value(NSLocalizedString("平均", comment: ""), plotValue(averageMinutes)))
                            .foregroundStyle(Color.brown.opacity(0.72))
                            .lineStyle(.init(lineWidth: 3, dash: [7, 5]))
                    }

                    ForEach(points) { point in
                        PointMark(
                            x: .value(NSLocalizedString("日期", comment: ""), point.date),
                            y: .value(NSLocalizedString("时间", comment: ""), plotValue(point.minutes))
                        )
                        .foregroundStyle(.brown)
                        .symbolSize(compact ? 28 : 44)

                        if selectedDate.flatMap({ Calendar.current.isDate($0, inSameDayAs: point.date) ? point : nil }) != nil {
                            RuleMark(x: .value(NSLocalizedString("日期", comment: ""), point.date))
                                .foregroundStyle(AppTheme.primaryText.opacity(0.5))
                                .lineStyle(.init(lineWidth: 3, dash: [7, 5]))

                            RuleMark(y: .value(NSLocalizedString("时间", comment: ""), plotValue(point.minutes)))
                                .foregroundStyle(AppTheme.primaryText.opacity(0.5))
                                .lineStyle(.init(lineWidth: 3, dash: [7, 5]))

                            PointMark(
                                x: .value(NSLocalizedString("日期", comment: ""), point.date),
                                y: .value(NSLocalizedString("时间", comment: ""), plotValue(point.minutes))
                            )
                            .foregroundStyle(.brown)
                            .symbolSize(compact ? 52 : 64)
                        }
                    }
                }
                .frame(height: compact ? 200 : 290)
                .chartYScale(domain: adaptiveDomain)
                .analyticsChartXScale(domain: chartDateDomain(for: selectionDates))
                .chartYAxis {
                    AxisMarks(position: .leading, values: axisValues) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let plotted = value.as(Double.self) {
                                Text(clockText(unplotValue(plotted)))
                            }
                        }
                    }
                }
                .chartOverlay { proxy in
                    chartSelectionOverlay(proxy: proxy) { location, geometry in
                        updateSelection(at: location, proxy: proxy, geometry: geometry)
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
        chartSelectionRatio(selectedDate: selectedDate, in: selectionDates)
    }

    private var selectionDates: [Date] {
        domainDates.isEmpty ? points.map(\.date) : domainDates
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
        return plotValue(upper)...plotValue(lower)
    }

    private var axisValues: [Double] {
        let minValue = points.map(\.minutes).min() ?? 0
        let maxValue = points.map(\.minutes).max() ?? 24 * 60
        let lower = max(0, floor((minValue - 30) / 60) * 60)
        let upper = min(24 * 60, ceil((maxValue + 30) / 60) * 60)
        return stride(from: lower, through: upper, by: 120).map(plotValue)
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
            selectedDate = nearestDate(to: date, in: selectionDates)
        } else {
            selectedDate = nil
        }
    }

    private func plotValue(_ minutes: Double) -> Double {
        24 * 60 - minutes
    }

    private func unplotValue(_ plotted: Double) -> Double {
        24 * 60 - plotted
    }
}

private struct SexualActivityBarChart: View {
    let weeklyData: [SexualActivityWeekPoint]
    let averagePerWeek: Double?
    var compact: Bool

    var body: some View {
        if weeklyData.isEmpty {
            PlaceholderCard(text: NSLocalizedString("还没有性生活记录数据。", comment: ""))
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if let averagePerWeek {
                    AverageTextBlock(
                        title: NSLocalizedString("平均每周", comment: ""),
                        value: String(format: NSLocalizedString("%.1f 次/周", comment: ""), averagePerWeek),
                        tone: .pink
                    )
                }

                Chart {
                    ForEach(weeklyData) { point in
                        if point.partnerCount > 0 {
                            BarMark(
                                x: .value(NSLocalizedString("周", comment: ""), point.weekLabel),
                                y: .value(NSLocalizedString("次数", comment: ""), point.partnerCount)
                            )
                            .foregroundStyle(.pink)
                        }
                        if point.masturbationCount > 0 {
                            BarMark(
                                x: .value(NSLocalizedString("周", comment: ""), point.weekLabel),
                                y: .value(NSLocalizedString("次数", comment: ""), point.masturbationCount)
                            )
                            .foregroundStyle(.pink.opacity(0.4))
                        }
                    }
                }
                .frame(height: compact ? 200 : 290)
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
            }
        }
    }
}

private enum HabitFrequencyMetric: String, CaseIterable, Identifiable, Hashable {
    case showers
    case bowelMovements
    case sexualActivity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .showers:
            NSLocalizedString("洗澡", comment: "")
        case .bowelMovements:
            NSLocalizedString("排便", comment: "")
        case .sexualActivity:
            NSLocalizedString("性生活", comment: "")
        }
    }

    var color: Color {
        switch self {
        case .showers:
            Color(red: 0.00, green: 0.68, blue: 0.88)
        case .bowelMovements:
            Color(red: 0.62, green: 0.45, blue: 0.22)
        case .sexualActivity:
            Color(red: 0.96, green: 0.28, blue: 0.55)
        }
    }

    var requiredSection: HomeSectionKind {
        switch self {
        case .showers:
            .showers
        case .bowelMovements:
            .bowelMovements
        case .sexualActivity:
            .sexualActivity
        }
    }

    func count(in point: AnalyticsDayPoint) -> Int {
        switch self {
        case .showers:
            point.showers
        case .bowelMovements:
            point.bowelMovements
        case .sexualActivity:
            point.sexualActivities
        }
    }

    func count(in counts: HabitFrequencyDayCounts) -> Int {
        switch self {
        case .showers:
            counts.showers
        case .bowelMovements:
            counts.bowelMovements
        case .sexualActivity:
            counts.sexualActivities
        }
    }
}

private struct HabitFrequencyCalendarDetailView: View {
    let records: [DailyRecord]
    let preferences: UserPreferences
    let allowedRange: ClosedRange<Date>
    let visibleHomeSections: [HomeSectionKind]
    @State private var visibleMonth: Date
    @State private var selectedMetrics: Set<HabitFrequencyMetric>

    init(records: [DailyRecord], preferences: UserPreferences, allowedRange: ClosedRange<Date>, initialMonth: Date, visibleHomeSections: [HomeSectionKind]) {
        self.records = records
        self.preferences = preferences
        self.allowedRange = allowedRange
        self.visibleHomeSections = visibleHomeSections
        let initialMetrics = HabitFrequencyMetric.allCases.filter { visibleHomeSections.contains($0.requiredSection) }
        _selectedMetrics = State(initialValue: Set(initialMetrics))
        let clamped = min(max(initialMonth.startOfDay, allowedRange.lowerBound.startOfDay), allowedRange.upperBound.startOfDay)
        _visibleMonth = State(initialValue: Calendar.current.dateInterval(of: .month, for: clamped)?.start ?? clamped)
    }

    private var countsByDate: [Date: HabitFrequencyDayCounts] {
        HabitFrequencyDayCounts.aggregate(records: records, preferences: preferences)
    }

    private var monthCounts: [HabitFrequencyDayCounts] {
        monthDates.compactMap { countsByDate[$0.startOfDay] }
    }

    private var visibleMetrics: [HabitFrequencyMetric] {
        HabitFrequencyMetric.allCases.filter { visibleHomeSections.contains($0.requiredSection) }
    }

    private var displayedMetrics: [HabitFrequencyMetric] {
        visibleMetrics.filter { selectedMetrics.contains($0) }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                monthHeader

                if visibleMetrics.isEmpty {
                    PlaceholderCard(text: NSLocalizedString("在设置里打开洗澡、排便或性生活后，这里会显示频率月历。", comment: ""))
                } else {
                    metricSelector
                    monthSummary

                    HabitFrequencyCountMonthView(
                        monthStart: visibleMonth,
                        countsByDate: countsByDate,
                        allowedRange: allowedRange,
                        metrics: displayedMetrics
                    )
                }
            }
            .padding(18)
            .padding(.bottom, 96)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle(NSLocalizedString("频率月历", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var monthHeader: some View {
        HStack(spacing: 14) {
            Button {
                visibleMonth = month(byAdding: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 40, height: 40)
                    .background(AppTheme.elevatedSurface)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canMoveMonth(by: -1))
            .opacity(canMoveMonth(by: -1) ? 1 : 0.35)

            Spacer()

            Text(monthTitle)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.primaryText)

            Spacer()

            Button {
                visibleMonth = month(byAdding: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 40, height: 40)
                    .background(AppTheme.elevatedSurface)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canMoveMonth(by: 1))
            .opacity(canMoveMonth(by: 1) ? 1 : 0.35)
        }
        .foregroundStyle(AppTheme.primaryText)
    }

    private var metricSelector: some View {
        HStack(spacing: 8) {
            ForEach(visibleMetrics) { metric in
                let isSelected = selectedMetrics.contains(metric)
                Button {
                    toggle(metric)
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(metric.color)
                            .frame(width: 8, height: 8)
                        Text(metric.title)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(isSelected ? Color.white : AppTheme.secondaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isSelected ? metric.color : AppTheme.surface)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(isSelected ? Color.clear : AppTheme.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var monthSummary: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: max(displayedMetrics.count, 1)), spacing: 10) {
            ForEach(displayedMetrics) { metric in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(metric.color)
                            .frame(width: 8, height: 8)
                        Text(metric.title)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.secondaryText)
                            .lineLimit(1)
                    }

                    Text(String(format: NSLocalizedString("%d 次", comment: ""), totalCount(for: metric)))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(metric.color)
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private var monthDates: [Date] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: visibleMonth),
              let dayRange = calendar.range(of: .day, in: .month, for: visibleMonth) else { return [] }
        return dayRange.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: interval.start)
        }
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("yMMMM")
        return formatter.string(from: visibleMonth)
    }

    private func totalCount(for metric: HabitFrequencyMetric) -> Int {
        monthCounts.reduce(0) { $0 + metric.count(in: $1) }
    }

    private func month(byAdding value: Int) -> Date {
        Calendar.current.date(byAdding: .month, value: value, to: visibleMonth) ?? visibleMonth
    }

    private func canMoveMonth(by value: Int) -> Bool {
        guard let interval = Calendar.current.dateInterval(of: .month, for: month(byAdding: value)) else { return false }
        return interval.end > allowedRange.lowerBound.startOfDay && interval.start <= allowedRange.upperBound.startOfDay
    }

    private func toggle(_ metric: HabitFrequencyMetric) {
        if selectedMetrics.contains(metric) {
            guard selectedMetrics.count > 1 else { return }
            selectedMetrics.remove(metric)
        } else {
            selectedMetrics.insert(metric)
        }
    }
}

private struct HabitFrequencyCountMonthView: View {
    let monthStart: Date
    let countsByDate: [Date: HabitFrequencyDayCounts]
    let allowedRange: ClosedRange<Date>
    let metrics: [HabitFrequencyMetric]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ForEach(metrics) { metric in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(metric.color)
                            .frame(width: 7, height: 7)
                        Text(metric.title)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
            }

            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)
                        .frame(height: 24)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(monthCells.enumerated()), id: \.offset) { _, date in
                    if let date {
                        HabitFrequencyCountDayCell(
                            date: date,
                            counts: countsByDate[date.startOfDay] ?? .empty,
                            isAllowed: allowedRange.contains(date.startOfDay),
                            metrics: metrics
                        )
                    } else {
                        Color.clear
                            .frame(height: 56)
                    }
                }
            }
        }
        .padding(14)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
    }

    private var monthCells: [Date?] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: monthStart),
              let dayRange = calendar.range(of: .day, in: .month, for: monthStart) else {
            return []
        }
        let leadingBlanks = max(0, interval.start.isoWeekday - 1)
        var cells = Array<Date?>(repeating: nil, count: leadingBlanks)
        cells += dayRange.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: interval.start)
        }
        while cells.count % 7 != 0 {
            cells.append(nil)
        }
        return cells
    }

    private var weekdaySymbols: [String] {
        let symbols = DateFormatter().veryShortWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
        guard symbols.count == 7 else { return symbols }
        return Array(symbols[1...6]) + [symbols[0]]
    }
}

private struct HabitFrequencyCountDayCell: View {
    let date: Date
    let counts: HabitFrequencyDayCounts
    let isAllowed: Bool
    let metrics: [HabitFrequencyMetric]

    var body: some View {
        VStack(spacing: 7) {
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.primaryText)
                .monospacedDigit()

            HStack(spacing: 4) {
                ForEach(metrics) { metric in
                    let count = metric.count(in: counts)
                    Circle()
                        .fill(count > 0 ? metric.color : metric.color.opacity(0.12))
                        .frame(width: 7, height: 7)
                }
            }
        }
        .frame(height: 56)
        .frame(maxWidth: .infinity)
        .opacity(isAllowed ? 1 : 0.28)
    }
}

struct HabitFrequencyDayCounts {
    var showers: Int
    var bowelMovements: Int
    var sexualActivities: Int

    static let empty = HabitFrequencyDayCounts(showers: 0, bowelMovements: 0, sexualActivities: 0)

    static func aggregate(records: [DailyRecord], preferences: UserPreferences = UserPreferences()) -> [Date: HabitFrequencyDayCounts] {
        var result: [Date: HabitFrequencyDayCounts] = [:]

        for record in records {
            let logicalDate = record.date.startOfDay

            for shower in record.showers {
                let date = shower.time.map {
                    logicalDisplayDate(for: $0, timeZoneIdentifier: shower.timeZoneIdentifier, preferences: preferences)
                } ?? logicalDate
                result[date, default: .empty].showers += 1
            }

            for bowelMovement in record.bowelMovements {
                let date = bowelMovement.time.map {
                    logicalDisplayDate(for: $0, timeZoneIdentifier: bowelMovement.timeZoneIdentifier, preferences: preferences)
                } ?? logicalDate
                result[date, default: .empty].bowelMovements += 1
            }

            for activity in record.sexualActivities {
                let date = activity.time.map {
                    logicalDisplayDate(for: $0, timeZoneIdentifier: activity.timeZoneIdentifier, preferences: preferences)
                } ?? activity.date.startOfDay
                result[date, default: .empty].sexualActivities += 1
            }
        }

        return result
    }

    private static func logicalDisplayDate(for timestamp: Date, timeZoneIdentifier: String?, preferences: UserPreferences) -> Date {
        var recordedCalendar = Calendar.current
        if let timeZoneIdentifier, let timeZone = TimeZone(identifier: timeZoneIdentifier) {
            recordedCalendar.timeZone = timeZone
        }
        let logicalDate = preferences.midnightMode.logicalDate(
            for: timestamp,
            timeZone: recordedCalendar.timeZone,
            calendar: recordedCalendar
        )
        let components = recordedCalendar.dateComponents([.year, .month, .day], from: logicalDate)
        var displayComponents = DateComponents()
        displayComponents.calendar = Calendar.current
        displayComponents.timeZone = Calendar.current.timeZone
        displayComponents.year = components.year
        displayComponents.month = components.month
        displayComponents.day = components.day
        return Calendar.current.date(from: displayComponents).map { Calendar.current.startOfDay(for: $0) }
            ?? Calendar.current.startOfDay(for: timestamp)
    }
}

private struct AnalyticsCustomizationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var customization: AnalyticsCustomization
    let visibleHomeSections: [HomeSectionKind]
    let onSave: (AnalyticsCustomization) -> Void

    init(customization: AnalyticsCustomization, visibleHomeSections: [HomeSectionKind], onSave: @escaping (AnalyticsCustomization) -> Void) {
        _customization = State(initialValue: customization)
        self.visibleHomeSections = visibleHomeSections
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            List {
                Section(NSLocalizedString("卡片", comment: "")) {
                    ForEach(filteredMetrics) { metric in
                        ToggleRow(
                            title: metric.title,
                            isOn: customization.visibleMetrics.contains(metric)
                        ) {
                            toggleMetric(metric)
                        }
                    }
                }

                Section(NSLocalizedString("图表", comment: "")) {
                    ForEach(customization.visibleWidgets.filter { isCustomizableWidget($0) && isSectionVisible(for: $0) }) { widget in
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
            .navigationTitle(NSLocalizedString("自定义", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(NSLocalizedString("取消", comment: "")) { dismiss() }
                        .foregroundStyle(AppTheme.secondaryText)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("保存", comment: "")) {
                        onSave(customization)
                        dismiss()
                    }
                    .foregroundStyle(AppTheme.accent)
                }
            }
        }
        .presentationBackground(AppTheme.background)
    }

    private var filteredMetrics: [AnalyticsMetricKind] {
        AnalyticsMetricKind.allCases.filter { isSectionVisible(for: $0) }
    }

    private var availableWidgets: [AnalyticsWidgetKind] {
        AnalyticsWidgetKind.allCases.filter {
            isCustomizableWidget($0) && !customization.visibleWidgets.contains($0) && isSectionVisible(for: $0)
        }
    }

    private func isCustomizableWidget(_ widget: AnalyticsWidgetKind) -> Bool {
        widget != .habitFrequencyCalendar
    }

    private func isSectionVisible(for metric: AnalyticsMetricKind) -> Bool {
        guard let required = metric.requiredSection else { return true }
        return visibleHomeSections.contains(required)
    }

    private func isSectionVisible(for widget: AnalyticsWidgetKind) -> Bool {
        guard let required = widget.requiredSection else { return true }
        return visibleHomeSections.contains(required)
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
    @Environment(\.locale) private var locale
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
                DatePicker(NSLocalizedString("开始", comment: ""), selection: $startDate, in: allowedRange, displayedComponents: .date)
                    .listRowBackground(AppTheme.surface)
                DatePicker(NSLocalizedString("结束", comment: ""), selection: $endDate, in: allowedRange, displayedComponents: .date)
                    .listRowBackground(AppTheme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle(NSLocalizedString("时间范围", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(NSLocalizedString("取消", comment: "")) { dismiss() }
                        .foregroundStyle(AppTheme.secondaryText)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("保存", comment: "")) {
                        onSave(min(startDate, endDate).startOfDay...max(startDate, endDate).startOfDay)
                        dismiss()
                    }
                    .foregroundStyle(AppTheme.accent)
                }
            }
        }
        .presentationBackground(AppTheme.background)
        .environment(\.locale, locale)
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
    var trend: ChartTrendDescriptor? = nil

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(tone)
            }

            Spacer(minLength: 0)

            if let trend {
                trendTag(trend)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private func fixedChartCallout<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    content()
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        )
}

@MainActor
private func chartSelectionOverlay(
    proxy: ChartProxy,
    onSelect: @escaping (CGPoint, GeometryProxy) -> Void
) -> some View {
    GeometryReader { geometry in
        Rectangle()
            .fill(.clear)
            .contentShape(Rectangle())
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { value in
                        onSelect(value.location, geometry)
                    }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 14)
                    .onChanged { value in
                        guard abs(value.translation.width) >= abs(value.translation.height) else { return }
                        onSelect(value.location, geometry)
                    }
            )
    }
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

private struct ChartTrendDescriptor {
    let text: String
    let tone: Color
}

private func trendTag(_ trend: ChartTrendDescriptor) -> some View {
    Text(trend.text)
        .font(.system(size: 11, weight: .bold, design: .rounded))
        .foregroundStyle(trend.tone)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(trend.tone.opacity(0.12))
        .clipShape(Capsule())
}

private func positiveTrendColor() -> Color {
    Color(red: 0.20, green: 0.65, blue: 0.38)
}

private func negativeTrendColor() -> Color {
    Color(red: 0.86, green: 0.30, blue: 0.28)
}

private func neutralTrendDescriptor() -> ChartTrendDescriptor {
    ChartTrendDescriptor(text: NSLocalizedString("--", comment: ""), tone: AppTheme.secondaryText)
}

private func formatTrendDuration(minutes: Int) -> String {
    let hours = minutes / 60
    let remainingMinutes = minutes % 60
    if hours > 0, remainingMinutes > 0 {
        return String(format: NSLocalizedString("%d小时%d分", comment: ""), hours, remainingMinutes)
    }
    if hours > 0 {
        return String(format: NSLocalizedString("%d小时", comment: ""), hours)
    }
    return String(format: NSLocalizedString("%d分", comment: ""), remainingMinutes)
}

private func durationTrendDescriptor(current: Double?, previous: Double?) -> ChartTrendDescriptor {
    guard let current, let previous else { return neutralTrendDescriptor() }
    let deltaMinutes = Int(abs((current - previous) * 60).rounded())
    guard deltaMinutes > 0 else {
        return ChartTrendDescriptor(text: NSLocalizedString("持平", comment: ""), tone: AppTheme.secondaryText)
    }
    return current >= previous
        ? ChartTrendDescriptor(
            text: String(format: NSLocalizedString("增加 %@", comment: ""), formatTrendDuration(minutes: deltaMinutes)),
            tone: positiveTrendColor()
        )
        : ChartTrendDescriptor(
            text: String(format: NSLocalizedString("减少 %@", comment: ""), formatTrendDuration(minutes: deltaMinutes)),
            tone: negativeTrendColor()
        )
}

private func clockTrendDescriptor(current: Double?, previous: Double?) -> ChartTrendDescriptor {
    guard let current, let previous else { return neutralTrendDescriptor() }
    var delta = current - previous
    let fullDay = 24.0 * 60.0
    if delta > fullDay / 2 {
        delta -= fullDay
    } else if delta < -fullDay / 2 {
        delta += fullDay
    }

    let deltaMinutes = Int(abs(delta).rounded())
    guard deltaMinutes > 0 else {
        return ChartTrendDescriptor(text: NSLocalizedString("持平", comment: ""), tone: AppTheme.secondaryText)
    }

    return delta > 0
        ? ChartTrendDescriptor(
            text: String(format: NSLocalizedString("变晚 %@", comment: ""), formatTrendDuration(minutes: deltaMinutes)),
            tone: negativeTrendColor()
        )
        : ChartTrendDescriptor(
            text: String(format: NSLocalizedString("变早 %@", comment: ""), formatTrendDuration(minutes: deltaMinutes)),
            tone: positiveTrendColor()
        )
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

private func chartSelectionRatio(selectedDate: Date?, in dates: [Date]) -> CGFloat? {
    guard let selectedDate else { return nil }
    let uniqueDates = Array(Set(dates.map(\.startOfDay))).sorted()
    guard let index = uniqueDates.firstIndex(where: { Calendar.current.isDate($0, inSameDayAs: selectedDate) }) else {
        return nil
    }
    guard uniqueDates.count > 1 else { return 0.5 }
    return CGFloat(index) / CGFloat(uniqueDates.count - 1)
}

private func chartDateDomain(for dates: [Date]) -> ClosedRange<Date>? {
    let uniqueDates = Array(Set(dates.map(\.startOfDay))).sorted()
    guard let first = uniqueDates.first, let last = uniqueDates.last else { return nil }
    return first...last
}

private extension View {
    @ViewBuilder
    func analyticsChartXScale(domain: ClosedRange<Date>?) -> some View {
        if let domain {
            self.chartXScale(domain: domain, range: .plotDimension(startPadding: 14, endPadding: 14))
        } else {
            self.chartXScale(range: .plotDimension(startPadding: 14, endPadding: 14))
        }
    }
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

// MARK: - Duration Line Chart (for sleep stages)

private struct ChartDurationValue: Identifiable {
    var id: Date { date }
    var date: Date
    var hours: Double
}

private struct DurationLineChart: View {
    let points: [ChartDurationValue]
    let domainDates: [Date]
    let averageHours: Double?
    let previousAverageHours: Double?
    let tone: Color
    @Binding var selectedDate: Date?
    var compact: Bool = false

    init(
        points: [ChartDurationValue],
        domainDates: [Date],
        averageHours: Double?,
        previousAverageHours: Double? = nil,
        tone: Color,
        selectedDate: Binding<Date?> = .constant(nil),
        compact: Bool = false
    ) {
        self.points = points
        self.domainDates = domainDates
        self.averageHours = averageHours
        self.previousAverageHours = previousAverageHours
        self.tone = tone
        self._selectedDate = selectedDate
        self.compact = compact
    }

    var body: some View {
        if points.isEmpty {
            PlaceholderCard(text: NSLocalizedString("还没有足够的睡眠阶段数据。", comment: ""))
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ChartDisplayZone(
                    ratio: selectedRatio,
                    cardWidth: 160,
                    height: 78,
                    idle: {
                        AverageTextBlock(
                            title: NSLocalizedString("平均时长", comment: ""),
                            value: averageHours.map(formatDuration) ?? "--",
                            tone: tone,
                            trend: durationTrendDescriptor(current: averageHours, previous: previousAverageHours)
                        )
                    },
                    selected: {
                        fixedChartCallout {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(selectedPoint?.date ?? .now, format: .dateTime.month().day())
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(AppTheme.secondaryText)
                                Text(selectedPoint.map { formatDuration($0.hours) } ?? "--")
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                    .foregroundStyle(AppTheme.primaryText)
                            }
                        }
                    }
                )

                Chart {
                    if let averageHours {
                        RuleMark(y: .value(NSLocalizedString("平均", comment: ""), averageHours))
                            .foregroundStyle(tone.opacity(0.72))
                            .lineStyle(.init(lineWidth: 3, dash: [7, 5]))
                    }

                    ForEach(points) { point in
                        LineMark(x: .value(NSLocalizedString("日期", comment: ""), point.date), y: .value(NSLocalizedString("时长", comment: ""), point.hours))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(tone)

                        PointMark(x: .value(NSLocalizedString("日期", comment: ""), point.date), y: .value(NSLocalizedString("时长", comment: ""), point.hours))
                            .foregroundStyle(tone)
                            .symbolSize(compact ? 34 : 46)

                        PointMark(x: .value(NSLocalizedString("日期", comment: ""), point.date), y: .value(NSLocalizedString("时长", comment: ""), point.hours))
                            .foregroundStyle(AppTheme.background)
                            .symbolSize(compact ? 12 : 18)

                        if selectedDate.flatMap({ Calendar.current.isDate($0, inSameDayAs: point.date) ? point : nil }) != nil {
                            RuleMark(x: .value(NSLocalizedString("日期", comment: ""), point.date))
                                .foregroundStyle(AppTheme.primaryText.opacity(0.5))
                                .lineStyle(.init(lineWidth: 3, dash: [7, 5]))

                            RuleMark(y: .value(NSLocalizedString("时长", comment: ""), point.hours))
                                .foregroundStyle(AppTheme.primaryText.opacity(0.5))
                                .lineStyle(.init(lineWidth: 3, dash: [7, 5]))

                            PointMark(x: .value(NSLocalizedString("日期", comment: ""), point.date), y: .value(NSLocalizedString("时长", comment: ""), point.hours))
                                .foregroundStyle(tone)
                                .symbolSize(compact ? 54 : 70)
                        }
                    }
                }
                .frame(height: compact ? 190 : 260)
                .chartYScale(domain: adaptiveDomain)
                .analyticsChartXScale(domain: chartDateDomain(for: selectionDates))
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let hours = value.as(Double.self) {
                                Text(formatDuration(hours))
                            }
                        }
                    }
                }
                .chartOverlay { proxy in
                    chartSelectionOverlay(proxy: proxy) { location, geometry in
                        updateSelection(at: location, proxy: proxy, geometry: geometry)
                    }
                }
            }
        }
    }

    private var selectedPoint: ChartDurationValue? {
        guard let selectedDate else { return nil }
        return points.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) })
    }

    private var selectedRatio: CGFloat? {
        chartSelectionRatio(selectedDate: selectedDate, in: selectionDates)
    }

    private var selectionDates: [Date] {
        domainDates.isEmpty ? points.map(\.date) : domainDates
    }

    private var adaptiveDomain: ClosedRange<Double> {
        let values = points.map(\.hours) + (averageHours.map { [$0] } ?? [])
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 3
        let lower = max(0, minValue - 0.3)
        let upper = maxValue + 0.3
        return lower...max(lower + 0.5, upper)
    }

    private func formatDuration(_ hours: Double) -> String {
        let totalMinutes = Int((hours * 60).rounded())
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h > 0 {
            return "\(h)h\(m)m"
        }
        return "\(m)m"
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
            selectedDate = nearestDate(to: date, in: selectionDates)
        } else {
            selectedDate = nil
        }
    }
}

private struct MealMemoryItem: Identifiable, Equatable {
    let id: String
    let mealTitle: String
    let recordDate: Date
    let time: Date?
    let photoURLs: [String]
    let timeZoneIdentifier: String?
    let locationName: String?
    let latitude: Double?
    let longitude: Double?

    init(recordDate: Date, meal: MealEntry) {
        id = "\(recordDate.storageKey())-\(meal.id.uuidString)"
        mealTitle = meal.displayTitle
        self.recordDate = recordDate
        time = meal.time
        photoURLs = meal.photoURLs
        timeZoneIdentifier = meal.timeZoneIdentifier
        locationName = meal.locationName
        latitude = meal.latitude
        longitude = meal.longitude
    }

    var sortDate: Date {
        time ?? recordDate
    }

    var recordedTimeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier ?? "") ?? .autoupdatingCurrent
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var coordinateLabel: String {
        guard let latitude, let longitude else { return "" }
        return String(format: "%.3f, %.3f", latitude, longitude)
    }

    var markerTitle: String {
        if let locationName, !locationName.isEmpty {
            return locationName
        }
        return mealTitle
    }

    var recordedHour: Int? {
        guard let time else { return nil }
        return Calendar.current.dateComponents(in: recordedTimeZone, from: time).hour
    }

    var recordedWeekday: Weekday? {
        guard let time else { return nil }
        let weekday = Calendar.current.dateComponents(in: recordedTimeZone, from: time).weekday ?? 1
        let isoWeekday = weekday == 1 ? 7 : weekday - 1
        return Weekday(rawValue: isoWeekday)
    }
}

private struct MealPhotoTile: Identifiable, Equatable {
    let id: String
    let photoURL: String
    let mealTitle: String
}

private enum MealPhotoWallCache {
    private static let keyPrefix = "dailylogs.mealPhotoWall.selection"
    private static let maxTileCount = 12

    static func selectionIDs(for tiles: [MealPhotoTile], date: Date = .now) -> [String] {
        guard !tiles.isEmpty else { return [] }

        let key = cacheKey(for: tiles, date: date)
        let availableIDs = Set(tiles.map(\.id))
        let targetCount = min(maxTileCount, tiles.count)

        if let storedIDs = UserDefaults.standard.array(forKey: key) as? [String] {
            var selectedIDs = storedIDs.filter { availableIDs.contains($0) }
            if selectedIDs.count >= targetCount {
                return Array(selectedIDs.prefix(targetCount))
            }

            let selectedIDSet = Set(selectedIDs)
            let remainingTiles = tiles.filter { !selectedIDSet.contains($0.id) }
            selectedIDs += randomIDs(from: remainingTiles, limit: targetCount - selectedIDs.count)
            UserDefaults.standard.set(selectedIDs, forKey: key)
            return selectedIDs
        }

        let selectedIDs = randomIDs(from: tiles, limit: targetCount)
        UserDefaults.standard.set(selectedIDs, forKey: key)
        return selectedIDs
    }

    private static func randomIDs(from tiles: [MealPhotoTile], limit: Int) -> [String] {
        guard limit > 0 else { return [] }
        var generator = SeededRandomNumberGenerator(seed: UInt64.random(in: 1...UInt64.max))
        return tiles
            .shuffled(using: &generator)
            .prefix(limit)
            .map(\.id)
    }

    private static func cacheKey(for tiles: [MealPhotoTile], date: Date) -> String {
        "\(keyPrefix).\(date.storageKey()).\(collectionSignature(for: tiles.map(\.id)))"
    }

    private static func collectionSignature(for ids: [String]) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for id in ids.sorted() {
            for byte in id.utf8 {
                hash ^= UInt64(byte)
                hash &*= 0x0000_0100_0000_01B3
            }
            hash ^= 0xff
            hash &*= 0x0000_0100_0000_01B3
        }
        return String(hash, radix: 16)
    }
}

private struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

private struct MealLocationSummary: Identifiable, Equatable {
    let id: String
    let title: String
    let count: Int
}

private struct MealHeatmapRow: Identifiable, Equatable {
    let weekday: Weekday
    let counts: [Int]

    var id: Int { weekday.rawValue }
}

private struct MealMemoriesSection: View {
    let items: [MealMemoryItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            MealMemoryMapCard(items: items)
            MealPhotoWallCard(items: items)
            MealTimeHeatmapCard(items: items)
        }
        .sectionStyle()
    }
}

private struct MealMemoryMapCard: View {
    let items: [MealMemoryItem]

    @State private var cameraPosition: MapCameraPosition = .automatic

    private var mappedItems: [MealMemoryItem] {
        items.filter { $0.coordinate != nil }
    }

    private var topLocations: [MealLocationSummary] {
        let groups = Dictionary(grouping: mappedItems) { item in
            if let locationName = item.locationName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !locationName.isEmpty {
                return locationName
            }
            return item.coordinateLabel
        }

        return groups
            .map { key, value in
                MealLocationSummary(id: key, title: key, count: value.count)
            }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count {
                    return lhs.title < rhs.title
                }
                return lhs.count > rhs.count
            }
            .prefix(4)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardTitle(NSLocalizedString("地图", comment: ""))

            if mappedItems.isEmpty {
                emptyCardState(
                    systemImage: "map",
                    title: NSLocalizedString("还没有带地点的餐食", comment: "")
                )
            } else {
                Map(position: $cameraPosition) {
                    ForEach(mappedItems) { item in
                        if let coordinate = item.coordinate {
                            Marker(item.markerTitle, coordinate: coordinate)
                                .tint(AppTheme.accent)
                        }
                    }
                }
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .onAppear(perform: updateCamera)
                .onChange(of: mappedItems.map(\.id)) { _, _ in
                    updateCamera()
                }

                if !topLocations.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(topLocations) { location in
                                Text("\(location.title) · \(location.count)")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(AppTheme.primaryText)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(AppTheme.surface)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .appCardStyle()
    }

    private func updateCamera() {
        guard !mappedItems.isEmpty else {
            cameraPosition = .automatic
            return
        }

        let coordinates = mappedItems.compactMap(\.coordinate)
        guard let first = coordinates.first else { return }
        guard coordinates.count > 1 else {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: first,
                    latitudinalMeters: 1200,
                    longitudinalMeters: 1200
                )
            )
            return
        }

        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        let minLat = latitudes.min() ?? first.latitude
        let maxLat = latitudes.max() ?? first.latitude
        let minLon = longitudes.min() ?? first.longitude
        let maxLon = longitudes.max() ?? first.longitude
        let latitudeDelta = max(0.02, (maxLat - minLat) * 1.6)
        let longitudeDelta = max(0.02, (maxLon - minLon) * 1.6)

        cameraPosition = .region(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(
                    latitude: (minLat + maxLat) / 2,
                    longitude: (minLon + maxLon) / 2
                ),
                span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
            )
        )
    }
}

private struct MealPhotoWallCard: View {
    let items: [MealMemoryItem]

    @State private var previewingPhoto: MealPhotoTile?
    @State private var cachedPhotoTileIDs: [String] = []

    private var allPhotoTiles: [MealPhotoTile] {
        items
            .flatMap { item in
                item.photoURLs.enumerated().map { index, photoURL in
                    MealPhotoTile(
                        id: "\(item.id)-\(index)",
                        photoURL: photoURL,
                        mealTitle: item.mealTitle
                    )
                }
            }
    }

    private var photoTiles: [MealPhotoTile] {
        let tilesByID = Dictionary(uniqueKeysWithValues: allPhotoTiles.map { ($0.id, $0) })
        return cachedPhotoTileIDs.compactMap { tilesByID[$0] }
    }

    private var photoTileIDs: [String] {
        allPhotoTiles.map(\.id)
    }

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardTitle(NSLocalizedString("照片墙", comment: ""))

            if allPhotoTiles.isEmpty {
                emptyCardState(
                    systemImage: "photo.on.rectangle.angled",
                    title: NSLocalizedString("还没有餐食照片", comment: "")
                )
            } else if photoTiles.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(photoTiles) { tile in
                        Button {
                            previewingPhoto = tile
                        } label: {
                            ZStack(alignment: .topLeading) {
                                PhotoContentView(photoURL: tile.photoURL, contentMode: .fill)
                                    .frame(height: 132)
                                    .frame(maxWidth: .infinity)
                                    .clipped()

                                Text(tile.mealTitle)
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(.black.opacity(0.42))
                                    .clipShape(Capsule())
                                    .padding(8)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .appCardStyle()
        .sheet(item: $previewingPhoto) { tile in
            MealPhotoPreview(photoURL: tile.photoURL)
        }
        .onAppear(perform: refreshCachedPhotoTiles)
        .onChange(of: photoTileIDs) { _, _ in
            refreshCachedPhotoTiles()
        }
    }

    private func refreshCachedPhotoTiles() {
        cachedPhotoTileIDs = MealPhotoWallCache.selectionIDs(for: allPhotoTiles)
    }
}

private struct MealTimeHeatmapCard: View {
    let items: [MealMemoryItem]

    private var rows: [MealHeatmapRow] {
        Weekday.allCases.map { weekday in
            MealHeatmapRow(
                weekday: weekday,
                counts: (0..<24).map { hour in
                    items.filter { $0.recordedWeekday == weekday && $0.recordedHour == hour }.count
                }
            )
        }
    }

    private var maxCount: Int {
        rows.flatMap(\.counts).max() ?? 0
    }

    private var hasTimedMeals: Bool {
        items.contains { $0.recordedHour != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardTitle(NSLocalizedString("时间热力图", comment: ""))

            if !hasTimedMeals {
                emptyCardState(
                    systemImage: "clock",
                    title: NSLocalizedString("还没有餐食时间", comment: "")
                )
            } else {
                GeometryReader { geometry in
                    let labelWidth: CGFloat = 20
                    let spacing: CGFloat = 4
                    let cellWidth = max(10, (geometry.size.width - labelWidth - (spacing * 23)) / 24)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: spacing) {
                            Color.clear.frame(width: labelWidth)
                            ForEach(0..<24, id: \.self) { hour in
                                Text(hour % 6 == 0 ? "\(hour)" : "")
                                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                    .foregroundStyle(AppTheme.secondaryText)
                                    .frame(width: cellWidth, alignment: .center)
                            }
                        }

                        ForEach(rows) { row in
                            HStack(spacing: spacing) {
                                Text(row.weekday.shortLabel)
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(AppTheme.secondaryText)
                                    .frame(width: labelWidth, alignment: .leading)

                                ForEach(Array(row.counts.enumerated()), id: \.offset) { entry in
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(heatmapColor(for: entry.element))
                                        .frame(width: cellWidth, height: 18)
                                }
                            }
                        }
                    }
                }
                .frame(height: 176)
            }
        }
        .padding(16)
        .appCardStyle()
    }

    private func heatmapColor(for count: Int) -> Color {
        guard count > 0, maxCount > 0 else {
            return AppTheme.mutedFill
        }
        let intensity = Double(count) / Double(maxCount)
        return AppTheme.accent.opacity(0.20 + intensity * 0.70)
    }
}

private struct MealPhotoPreview: View {
    @Environment(\.dismiss) private var dismiss

    let photoURL: String
    @State private var isSavingToLibrary = false
    @State private var didSaveToLibrary = false
    @State private var saveErrorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ZoomablePhotoContentView(photoURL: photoURL, contentMode: .fit)
                    .padding(24)
            }
            .overlay(alignment: .topLeading) {
                mediaSaveButton(
                    isSaving: isSavingToLibrary,
                    didSave: didSaveToLibrary,
                    action: savePhotoToLibrary
                )
                .padding(.top, 54)
                .padding(.leading, 18)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("关闭", comment: "")) {
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white)
                }
            }
            .alert(NSLocalizedString("保存失败", comment: ""), isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )) {
                Button(NSLocalizedString("知道了", comment: ""), role: .cancel) {}
            } message: {
                Text(saveErrorMessage ?? "")
            }
        }
    }

    private func savePhotoToLibrary() {
        guard !isSavingToLibrary else { return }
        didSaveToLibrary = false
        isSavingToLibrary = true

        Task {
            do {
                try await MediaLibrarySaver.savePhoto(from: photoURL)
                didSaveToLibrary = true
            } catch {
                saveErrorMessage = error.localizedDescription
            }
            isSavingToLibrary = false
        }
    }
}

private func cardTitle(_ title: String) -> some View {
    Text(title)
        .font(.system(size: 18, weight: .bold, design: .rounded))
        .foregroundStyle(AppTheme.primaryText)
}

private func emptyCardState(systemImage: String, title: String) -> some View {
    VStack(spacing: 10) {
        Image(systemName: systemImage)
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(AppTheme.secondaryText)
        Text(title)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(AppTheme.secondaryText)
    }
    .frame(maxWidth: .infinity, minHeight: 140)
    .background(AppTheme.surface)
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
}

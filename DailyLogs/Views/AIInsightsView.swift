import SwiftUI

struct AIInsightsView: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @State private var showingDatePicker = false
    @State private var selectedInsightDate: Date?

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var report: DailyInsightReport? {
        guard let resolvedInsightDate else { return nil }
        return appViewModel.displayedDailyInsightReport(for: resolvedInsightDate)
    }

    private var activeNarrative: DailyInsightNarrative? {
        guard let resolvedInsightDate else { return nil }
        return appViewModel.activeDailyInsightNarrative(for: resolvedInsightDate)
    }

    private var resolvedInsightDate: Date? {
        selectedInsightDate?.startOfDay ?? appViewModel.dailyInsightTargetDate
    }

    private var resolvedLocale: Locale {
        appViewModel.preferences.appLanguage.locale ?? Locale.autoupdatingCurrent
    }

    private var isDisplayingAIScoreForSelection: Bool {
        guard let resolvedInsightDate else { return false }
        return appViewModel.isDisplayingAIScoredInsight(for: resolvedInsightDate)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundLayer

                if let report {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 18) {
                            heroCard(report)
                            breakdownGrid(report)
                            insightNarrativeCard(report)
                            privacyCard
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 16)
                        .padding(.bottom, 28)
                    }
                    .refreshable {
                        if appViewModel.canGenerateAIInsights {
                            await appViewModel.refreshDailyInsightNarrative(force: true)
                        }
                    }
                } else {
                    unavailableState
                }
            }
            .navigationTitle(NSLocalizedString("AI 洞察", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingDatePicker) {
                AIInsightCalendarSheet(
                    selectedDate: resolvedInsightDate ?? appViewModel.dailyInsightTargetDate ?? appViewModel.logicalToday,
                    allowedRange: appViewModel.availableDateRange,
                    reportProvider: { date in
                        appViewModel.displayedDailyInsightReport(for: date)
                    }
                ) { date in
                    selectedInsightDate = date.startOfDay
                }
            }
            .task(id: taskRefreshKey) {
                if selectedInsightDate == nil {
                    selectedInsightDate = appViewModel.dailyInsightTargetDate
                }
                guard appViewModel.canGenerateAIInsights,
                      let targetDate = appViewModel.dailyInsightTargetDate,
                      resolvedInsightDate?.startOfDay == targetDate.startOfDay else { return }
                await appViewModel.refreshDailyInsightNarrative(for: targetDate)
            }
        }
    }

    private var taskRefreshKey: String {
        let dateKey = resolvedInsightDate?.storageKey() ?? appViewModel.dailyInsightTargetDate?.storageKey() ?? "none"
        return "\(dateKey)-\(appViewModel.canGenerateAIInsights)-\(appViewModel.preferences.appLanguage.rawValue)"
    }

    private var backgroundLayer: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.93, blue: 0.86),
                    AppTheme.background,
                    Color(red: 0.88, green: 0.95, blue: 0.93).opacity(0.9)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color(red: 0.97, green: 0.76, blue: 0.45).opacity(0.16))
                .frame(width: 260, height: 260)
                .offset(x: 150, y: -260)

            Circle()
                .fill(Color(red: 0.26, green: 0.69, blue: 0.66).opacity(0.12))
                .frame(width: 220, height: 220)
                .offset(x: -150, y: -60)
        }
    }

    private func heroCard(_ report: DailyInsightReport) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(report.date.formattedDayTitle(locale: resolvedLocale))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.82))

                    Text(activeNarrative?.headline ?? report.title)
                        .font(.system(size: 29, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 12)

                Button {
                    showingDatePicker = true
                } label: {
                    Image(systemName: "calendar")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.white.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 18) {
                scoreRing(score: report.overallScore)

                VStack(alignment: .leading, spacing: 8) {
                    Text(activeNarrative?.summary ?? report.summary)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        Label(
                            appViewModel.canGenerateAIInsights
                                ? (isDisplayingAIScoreForSelection
                                    ? (appViewModel.isUsingCloudAIProxy
                                        ? NSLocalizedString("云端 AI 已启用", comment: "")
                                        : NSLocalizedString("AI 评分已启用", comment: ""))
                                    : NSLocalizedString("可生成 AI 评分", comment: ""))
                                : NSLocalizedString("当前显示本地评分", comment: ""),
                            systemImage: isDisplayingAIScoreForSelection ? "wand.and.stars" : "cpu"
                        )
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.84))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.12))
                        .clipShape(Capsule())

                        if appViewModel.isGeneratingDailyInsightNarrative {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        }
                    }
                }
            }
        }
        .padding(22)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.13, green: 0.24, blue: 0.33),
                    Color(red: 0.12, green: 0.46, blue: 0.47),
                    Color(red: 0.72, green: 0.48, blue: 0.25)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.10), radius: 12, x: 0, y: 6)
    }

    private func scoreRing(score: Int) -> some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.16), lineWidth: 12)

            Circle()
                .trim(from: 0, to: CGFloat(max(0, min(score, 100))) / 100)
                .stroke(
                    AngularGradient(
                        colors: [
                            Color(red: 0.98, green: 0.85, blue: 0.54),
                            Color(red: 0.49, green: 0.91, blue: 0.78),
                            Color.white
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 2) {
                Text("\(score)")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(NSLocalizedString("当日分数", comment: ""))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.72))
            }
        }
        .frame(width: 112, height: 112)
    }

    private func breakdownGrid(_ report: DailyInsightReport) -> some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(report.components) { component in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        Text(component.kind.title)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.primaryText)

                        Spacer()

                        Text(component.isIncluded ? "\(component.score)/\(component.maxScore)" : NSLocalizedString("未纳入", comment: ""))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(componentColor(component))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(componentColor(component).opacity(component.isIncluded ? 0.14 : 0.08))
                            .clipShape(Capsule())
                    }

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(AppTheme.mutedFill)
                            .frame(height: 8)

                        Capsule()
                            .fill(componentColor(component))
                            .frame(width: componentBarWidth(component: component), height: 8)
                    }

                    Text(component.detail)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(18)
                .background(AppTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(AppTheme.border, lineWidth: 1)
                )
            }
        }
    }

    private func componentBarWidth(component: DailyInsightComponent) -> CGFloat {
        guard component.isIncluded, component.maxScore > 0 else { return 28 }
        return max(28, CGFloat(component.scoreRatio) * 120)
    }

    private func componentColor(_ component: DailyInsightComponent) -> Color {
        guard component.isIncluded else { return AppTheme.secondaryText.opacity(0.45) }
        switch component.kind {
        case .sleep:
            return Color(red: 0.26, green: 0.54, blue: 0.92)
        case .meals:
            return Color(red: 0.86, green: 0.57, blue: 0.20)
        case .shower:
            return Color(red: 0.24, green: 0.69, blue: 0.76)
        case .bowelMovement:
            return Color(red: 0.42, green: 0.66, blue: 0.34)
        }
    }

    private func insightNarrativeCard(_ report: DailyInsightReport) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(
                title: NSLocalizedString("这一天的观察", comment: ""),
                subtitle: appViewModel.canGenerateAIInsights
                    ? (isDisplayingAIScoreForSelection
                        ? NSLocalizedString("这张卡片的分数和文案都由 AI 给出。", comment: "")
                        : NSLocalizedString("现在还是本地兜底分数；生成后会切换成 AI 评分。", comment: ""))
                    : NSLocalizedString("登录后自动启用云端 AI。", comment: "")
            )

            if let aiInsightErrorMessage = appViewModel.aiInsightErrorMessage, !aiInsightErrorMessage.isEmpty {
                Text(aiInsightErrorMessage)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.warning)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(AppTheme.warning.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 12) {
                if let narrative = activeNarrative {
                    ForEach(Array(narrative.bullets.enumerated()), id: \.offset) { _, bullet in
                        insightBullet(bullet)
                    }
                } else {
                    ForEach(Array(report.highlights.enumerated()), id: \.offset) { _, bullet in
                        insightBullet(bullet)
                    }
                }
            }

            if appViewModel.canGenerateAIInsights {
                Button {
                    guard let resolvedInsightDate else { return }
                    Task { await appViewModel.refreshDailyInsightNarrative(for: resolvedInsightDate, force: true) }
                } label: {
                    Text(appViewModel.isGeneratingDailyInsightNarrative
                        ? NSLocalizedString("正在生成 AI 评分…", comment: "")
                        : NSLocalizedString("重新生成 AI 评分", comment: ""))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            appViewModel.isGeneratingDailyInsightNarrative
                                ? AppTheme.secondaryText.opacity(0.35)
                                : AppTheme.actionFill
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(appViewModel.isGeneratingDailyInsightNarrative)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("登录后自动启用云端 AI。", comment: ""))
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)

                    Text(NSLocalizedString("游客模式显示本地评分。", comment: ""))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText.opacity(0.9))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(AppTheme.elevatedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .padding(22)
        .appCardStyle()
    }

    private func insightBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(Color(red: 0.18, green: 0.63, blue: 0.65))
                .frame(width: 8, height: 8)
                .padding(.top, 7)

            Text(text)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(AppTheme.elevatedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: NSLocalizedString("说明", comment: ""),
                subtitle: NSLocalizedString("这是一项趣味型分析功能，不构成医疗或健康建议。", comment: "")
            )

            Text(NSLocalizedString("当前会分析你所选日期的睡眠、餐食、洗澡和排便，并尽量按整天时间轴来理解。", comment: ""))
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.secondaryText)

            Text(NSLocalizedString("AI 请求会经你的云端代理转发；新评分会固定保存，除非相关记录后来被改动。", comment: ""))
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.secondaryText)
        }
        .padding(22)
        .appCardStyle()
    }

    private var unavailableState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryText)

            Text(NSLocalizedString("还没有可分析的数据", comment: ""))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.primaryText)

            Text(NSLocalizedString("等你至少记录一天后，这里就会出现当日评分和 AI 洞察。", comment: ""))
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct AIInsightCalendarSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    @State private var draftDate: Date

    let allowedRange: ClosedRange<Date>
    let reportProvider: (Date) -> DailyInsightReport?
    let onConfirm: (Date) -> Void

    init(
        selectedDate: Date,
        allowedRange: ClosedRange<Date>,
        reportProvider: @escaping (Date) -> DailyInsightReport?,
        onConfirm: @escaping (Date) -> Void
    ) {
        _draftDate = State(initialValue: selectedDate.startOfDay)
        self.allowedRange = allowedRange
        self.reportProvider = reportProvider
        self.onConfirm = onConfirm
    }

    private var selectedReport: DailyInsightReport? {
        reportProvider(draftDate.startOfDay)
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 20) {
                    DatePicker(
                        NSLocalizedString("选择日期", comment: ""),
                        selection: $draftDate,
                        in: allowedRange,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding(12)
                    .background(AppTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                    if let selectedReport {
                        AIInsightRingCalendarPreview(report: selectedReport, locale: locale)
                    } else {
                        Text(NSLocalizedString("还没有可分析的数据", comment: ""))
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.secondaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                            .background(AppTheme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }
                }
                .padding(18)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle(NSLocalizedString("选择日期", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("取消", comment: "")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("确定", comment: "")) {
                        onConfirm(draftDate.startOfDay)
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct AIInsightRingCalendarPreview: View {
    let report: DailyInsightReport
    let locale: Locale

    private var rings: [CalendarRingMetric] {
        let overall = CalendarRingMetric(
            title: NSLocalizedString("当日分数", comment: ""),
            score: report.overallScore,
            maxScore: 100,
            color: AppTheme.accent
        )
        let components = report.components.map {
            CalendarRingMetric(
                title: $0.kind.title,
                score: $0.score,
                maxScore: max($0.maxScore, 1),
                color: color(for: $0.kind)
            )
        }
        return [overall] + components
    }

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                ForEach(Array(rings.enumerated()), id: \.offset) { index, ring in
                    Circle()
                        .stroke(ring.color.opacity(0.14), lineWidth: 12)
                        .frame(width: ringSize(for: index), height: ringSize(for: index))

                    Circle()
                        .trim(from: 0, to: ring.progress)
                        .stroke(
                            ring.color,
                            style: StrokeStyle(lineWidth: 12, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: ringSize(for: index), height: ringSize(for: index))
                }

                VStack(spacing: 4) {
                    Text("\(report.overallScore)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.primaryText)

                    Text(report.date.formattedDayTitle(locale: locale))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
            }
            .frame(height: 230)

            VStack(spacing: 10) {
                ForEach(rings) { ring in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(ring.color)
                            .frame(width: 10, height: 10)

                        Text(ring.title)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.primaryText)

                        Spacer()

                        Text("\(ring.score)/\(ring.maxScore)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(ring.color)
                    }
                }
            }
        }
        .padding(22)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func ringSize(for index: Int) -> CGFloat {
        max(78, 208 - CGFloat(index * 28))
    }

    private func color(for kind: DailyInsightComponentKind) -> Color {
        switch kind {
        case .sleep:
            Color(red: 0.35, green: 0.46, blue: 0.96)
        case .meals:
            Color(red: 0.98, green: 0.62, blue: 0.24)
        case .shower:
            Color(red: 0.22, green: 0.70, blue: 0.67)
        case .bowelMovement:
            Color(red: 0.71, green: 0.49, blue: 0.28)
        }
    }
}

private struct CalendarRingMetric: Identifiable {
    let id = UUID()
    let title: String
    let score: Int
    let maxScore: Int
    let color: Color

    var progress: CGFloat {
        guard maxScore > 0 else { return 0 }
        return CGFloat(max(0, min(Double(score) / Double(maxScore), 1)))
    }
}

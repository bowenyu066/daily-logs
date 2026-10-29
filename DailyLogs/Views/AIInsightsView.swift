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

    private var insightCalendarRange: ClosedRange<Date>? {
        appViewModel.aiInsightCalendarDateRange
    }

    private var isGeneratingSelection: Bool {
        guard let resolvedInsightDate, let generatingDate = appViewModel.generatingDailyInsightDate else { return false }
        return generatingDate.startOfDay == resolvedInsightDate.startOfDay
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
                if let insightCalendarRange {
                    AIInsightCalendarSheet(
                        selectedDate: min(
                            resolvedInsightDate ?? appViewModel.dailyInsightTargetDate ?? insightCalendarRange.upperBound,
                            insightCalendarRange.upperBound
                        ),
                        allowedRange: insightCalendarRange,
                        reportProvider: { date in
                            appViewModel.displayedDailyInsightReport(for: date)
                        }
                    ) { date in
                        selectedInsightDate = date.startOfDay
                    }
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

                if insightCalendarRange != nil {
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
            }

            HStack(spacing: 18) {
                scoreRing(score: report.overallScore, ruleScore: report.ruleScore)

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

                        if isGeneratingSelection {
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

    private func scoreRing(score: Int, ruleScore: Int?) -> some View {
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
                Text(ruleScore == nil
                    ? NSLocalizedString("当日分数", comment: "")
                    : NSLocalizedString("AI 评分", comment: ""))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.72))
                if let ruleScore {
                    Text(String(format: NSLocalizedString("规则分 %d", comment: ""), ruleScore))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.6))
                }
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

                    Capsule()
                        .fill(AppTheme.mutedFill)
                        .frame(height: 8)
                        .overlay(alignment: .leading) {
                            GeometryReader { proxy in
                                Capsule()
                                    .fill(componentColor(component))
                                    .frame(width: componentBarWidth(component: component, trackWidth: proxy.size.width))
                            }
                        }

                    Text(component.detail)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    if let reason = component.aiReason {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(aiDeltaLabel(component.aiDelta ?? 0), systemImage: "wand.and.stars")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(componentColor(component))

                            Text(reason)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(componentColor(component).opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
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

    private func aiDeltaLabel(_ delta: Int) -> String {
        if delta == 0 {
            return NSLocalizedString("AI 维持规则分", comment: "")
        }
        return String(format: NSLocalizedString("AI 调整 %@", comment: ""), delta > 0 ? "+\(delta)" : "\(delta)")
    }

    /// Proportional to the score; a short stub keeps excluded and zero scores visible.
    private func componentBarWidth(component: DailyInsightComponent, trackWidth: CGFloat) -> CGFloat {
        let stub = min(28, trackWidth)
        guard component.isIncluded, component.maxScore > 0 else { return stub }
        return max(min(8, trackWidth), CGFloat(component.scoreRatio) * trackWidth)
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
                        ? (report.ruleScore != nil
                            ? NSLocalizedString("AI 在规则分的基础上调整了睡眠和餐食，并给出观察和建议。", comment: "")
                            : NSLocalizedString("这张卡片的分数和文案都由 AI 给出。", comment: ""))
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
                if let narrative = activeNarrative, let findings = narrative.findings, !findings.isEmpty {
                    ForEach(Array(findings.enumerated()), id: \.offset) { _, finding in
                        insightFinding(finding)
                    }
                    if let followUp = nonEmpty(narrative.followUp) {
                        insightNote(
                            title: NSLocalizedString("上次的建议", comment: ""),
                            text: followUp,
                            systemImage: "arrow.uturn.backward.circle",
                            tint: Color(red: 0.42, green: 0.48, blue: 0.62)
                        )
                    }
                    if let suggestion = nonEmpty(narrative.suggestion) {
                        insightNote(
                            title: NSLocalizedString("明天试试", comment: ""),
                            text: suggestion,
                            systemImage: "lightbulb",
                            tint: Color(red: 0.80, green: 0.52, blue: 0.16)
                        )
                    }
                } else if let narrative = activeNarrative {
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
                    Text(isGeneratingSelection
                        ? NSLocalizedString("正在生成 AI 解读…", comment: "")
                        : (appViewModel.isGeneratingDailyInsightNarrative
                            ? NSLocalizedString("AI 正在分析其他日期…", comment: "")
                            : NSLocalizedString("重新生成 AI 解读", comment: "")))
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

    private func insightFinding(_ finding: DailyInsightNarrative.Finding) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(Color(red: 0.18, green: 0.63, blue: 0.65))
                .frame(width: 8, height: 8)
                .padding(.top, 7)

            VStack(alignment: .leading, spacing: 5) {
                Text(finding.title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text(finding.evidence)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(AppTheme.elevatedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func insightNote(title: String, text: String, systemImage: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(tint)

            Text(text)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(tint.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func nonEmpty(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
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

            Text(NSLocalizedString("AI 会参考你在设置里写的目标、它从过去记录中总结的规律，以及 Apple 健康里的活动数据；餐食照片只有在你开启后才会发送。", comment: ""))
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
    @State private var visibleMonth: Date

    let allowedRange: ClosedRange<Date>
    let reportProvider: (Date) -> DailyInsightReport?
    let onConfirm: (Date) -> Void

    init(
        selectedDate: Date,
        allowedRange: ClosedRange<Date>,
        reportProvider: @escaping (Date) -> DailyInsightReport?,
        onConfirm: @escaping (Date) -> Void
    ) {
        let normalizedDate = selectedDate.startOfDay
        _draftDate = State(initialValue: normalizedDate)
        _visibleMonth = State(initialValue: Calendar.current.dateInterval(of: .month, for: normalizedDate)?.start ?? normalizedDate)
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
                VStack(spacing: 18) {
                    monthHeader
                        .padding(.horizontal, 18)
                        .padding(.top, 18)

                    RingMonthCalendar(
                        visibleMonth: visibleMonth,
                        selectedDate: draftDate,
                        allowedRange: allowedRange,
                        overlayRange: allowedRange,
                        locale: locale,
                        reportForDate: reportProvider,
                        travelPlansForDate: { _ in [] },
                        onTravelPlanSelected: { _ in },
                        onSelect: { draftDate = $0 }
                    )
                    .padding(.horizontal, 18)

                    DailyInsightCalendarDetailCard(
                        date: draftDate,
                        report: selectedReport,
                        locale: locale
                    )
                    .padding(.horizontal, 18)
                }
                .padding(.bottom, 28)
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
        .environment(\.locale, locale)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(AppTheme.background)
    }

    private var monthHeader: some View {
        HStack(spacing: 14) {
            Button {
                visibleMonth = month(byAdding: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 38, height: 38)
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
                    .frame(width: 38, height: 38)
                    .background(AppTheme.elevatedSurface)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canMoveMonth(by: 1))
            .opacity(canMoveMonth(by: 1) ? 1 : 0.35)
        }
        .foregroundStyle(AppTheme.primaryText)
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("yMMMM")
        return formatter.string(from: visibleMonth)
    }

    private func month(byAdding value: Int) -> Date {
        Calendar.current.date(byAdding: .month, value: value, to: visibleMonth) ?? visibleMonth
    }

    private func canMoveMonth(by value: Int) -> Bool {
        guard let interval = Calendar.current.dateInterval(of: .month, for: month(byAdding: value)) else { return false }
        return interval.end > allowedRange.lowerBound.startOfDay && interval.start <= allowedRange.upperBound.startOfDay
    }
}

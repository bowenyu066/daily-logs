import SwiftUI

struct AIInsightsView: View {
    @EnvironmentObject private var appViewModel: AppViewModel

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var report: DailyInsightReport? {
        appViewModel.displayedDailyInsightReport
    }

    private var activeNarrative: DailyInsightNarrative? {
        guard let report,
              appViewModel.dailyInsightNarrativeDate?.startOfDay == report.date.startOfDay else {
            return nil
        }
        return appViewModel.dailyInsightNarrative
    }

    private var resolvedLocale: Locale {
        appViewModel.preferences.appLanguage.locale ?? Locale.autoupdatingCurrent
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
                        if appViewModel.hasOpenAIAPIKey {
                            await appViewModel.refreshDailyInsightNarrative(force: true)
                        }
                    }
                } else {
                    unavailableState
                }
            }
            .navigationTitle(NSLocalizedString("AI 洞察", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .task(id: taskRefreshKey) {
                guard appViewModel.hasOpenAIAPIKey else { return }
                await appViewModel.refreshDailyInsightNarrative()
            }
        }
    }

    private var taskRefreshKey: String {
        let dateKey = appViewModel.dailyInsightTargetDate?.storageKey() ?? "none"
        return "\(dateKey)-\(appViewModel.hasOpenAIAPIKey)-\(appViewModel.preferences.appLanguage.rawValue)"
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
                    Task { await appViewModel.refreshDailyInsightNarrative(force: true) }
                } label: {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.white.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .opacity(appViewModel.hasOpenAIAPIKey ? 1 : 0)
                .accessibilityHidden(!appViewModel.hasOpenAIAPIKey)
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
                            appViewModel.hasOpenAIAPIKey
                                ? (appViewModel.isDisplayingAIScoredInsight
                                    ? NSLocalizedString("AI 评分已启用", comment: "")
                                    : NSLocalizedString("可生成 AI 评分", comment: ""))
                                : NSLocalizedString("当前显示本地评分", comment: ""),
                            systemImage: appViewModel.isDisplayingAIScoredInsight ? "wand.and.stars" : "cpu"
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
                Text(NSLocalizedString("昨日分数", comment: ""))
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
                title: NSLocalizedString("昨天的观察", comment: ""),
                subtitle: appViewModel.hasOpenAIAPIKey
                    ? (appViewModel.isDisplayingAIScoredInsight
                        ? NSLocalizedString("这张卡片的分数和文案都由 AI 给出。", comment: "")
                        : NSLocalizedString("现在还是本地兜底分数；生成后会切换成 AI 评分。", comment: ""))
                    : NSLocalizedString("当前先显示本地总结。添加 API Key 后，这里会升级成 AI 打分和文案。", comment: "")
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

            if appViewModel.hasOpenAIAPIKey {
                Button {
                    Task { await appViewModel.refreshDailyInsightNarrative(force: true) }
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
                    Text(NSLocalizedString("想启用 AI 文案的话，到“设置 > AI 洞察”里贴入你的 OpenAI API Key 就可以。", comment: ""))
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)

                    Text(NSLocalizedString("配置后，这一页的总分和分项分也会一起改成 AI 来打。", comment: ""))
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.secondaryText)

                    Text(NSLocalizedString("Key 只保存在这台设备，不会同步到云端。", comment: ""))
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

            Text(NSLocalizedString("当前版本只分析最近一个完整日的睡眠、餐食、洗澡和排便。未开启的模块不会被纳入评分。", comment: ""))
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.secondaryText)

            Text(NSLocalizedString("未配置 OpenAI API Key 时会回退到本地兜底评分；配置后会优先显示 AI 给出的分数和解读。", comment: ""))
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

            Text(NSLocalizedString("等你至少记录一天后，这里就会出现昨日评分和 AI 洞察。", comment: ""))
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

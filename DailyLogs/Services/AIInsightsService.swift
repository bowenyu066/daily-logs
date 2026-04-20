import Foundation
import CryptoKit
@preconcurrency import FirebaseAuth
import Security

enum DailyInsightComponentKind: String, CaseIterable, Identifiable {
    case sleep
    case meals
    case shower
    case bowelMovement

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sleep:
            NSLocalizedString("睡眠", comment: "")
        case .meals:
            NSLocalizedString("餐食", comment: "")
        case .shower:
            NSLocalizedString("洗澡", comment: "")
        case .bowelMovement:
            NSLocalizedString("排便", comment: "")
        }
    }
}

struct DailyInsightComponent: Identifiable, Equatable {
    var kind: DailyInsightComponentKind
    var score: Int
    var maxScore: Int
    var detail: String
    var isIncluded: Bool

    var id: String { kind.rawValue }

    var scoreRatio: Double {
        guard isIncluded, maxScore > 0 else { return 0 }
        return Double(score) / Double(maxScore)
    }
}

struct DailyInsightNarrative: Codable, Equatable {
    static let currentScoringVersion = 2

    struct ComponentScoreOverride: Codable, Equatable {
        var score: Int?
        var maxScore: Int?
        var detail: String?
        var included: Bool?
    }

    struct LocalizedText: Codable, Equatable {
        var headline: String
        var summary: String
        var bullets: [String]
    }

    var headline: String
    var summary: String
    var bullets: [String]
    var overallScore: Int?
    var components: [String: ComponentScoreOverride]?
    var generatedAt: Date = .now
    var scoringVersion: Int
    var sampleCount: Int
    var payloadSignature: String?
    var sourceLanguageCode: String
    var localizedTexts: [String: LocalizedText]?

    enum CodingKeys: String, CodingKey {
        case headline
        case summary
        case bullets
        case overallScore
        case components
        case generatedAt
        case scoringVersion
        case sampleCount
        case payloadSignature
        case sourceLanguageCode
        case localizedTexts
    }

    init(
        headline: String,
        summary: String,
        bullets: [String],
        overallScore: Int? = nil,
        components: [String: ComponentScoreOverride]? = nil,
        generatedAt: Date = .now,
        scoringVersion: Int = DailyInsightNarrative.currentScoringVersion,
        sampleCount: Int = 1,
        payloadSignature: String? = nil,
        sourceLanguageCode: String = "zh-Hans",
        localizedTexts: [String: LocalizedText]? = nil
    ) {
        self.headline = headline
        self.summary = summary
        self.bullets = bullets
        self.overallScore = overallScore
        self.components = components
        self.generatedAt = generatedAt
        self.scoringVersion = scoringVersion
        self.sampleCount = sampleCount
        self.payloadSignature = payloadSignature
        self.sourceLanguageCode = sourceLanguageCode
        self.localizedTexts = localizedTexts
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        headline = try container.decode(String.self, forKey: .headline)
        summary = try container.decode(String.self, forKey: .summary)
        bullets = try container.decode([String].self, forKey: .bullets)
        overallScore = try container.decodeIfPresent(Int.self, forKey: .overallScore)
        components = try container.decodeIfPresent([String: ComponentScoreOverride].self, forKey: .components)
        generatedAt = try container.decodeIfPresent(Date.self, forKey: .generatedAt) ?? .now
        scoringVersion = try container.decodeIfPresent(Int.self, forKey: .scoringVersion) ?? 1
        sampleCount = try container.decodeIfPresent(Int.self, forKey: .sampleCount) ?? 1
        payloadSignature = try container.decodeIfPresent(String.self, forKey: .payloadSignature)
        sourceLanguageCode = try container.decodeIfPresent(String.self, forKey: .sourceLanguageCode) ?? "zh-Hans"
        localizedTexts = try container.decodeIfPresent([String: LocalizedText].self, forKey: .localizedTexts)
    }

    var hasAIScoring: Bool {
        overallScore != nil || !(components ?? [:]).isEmpty
    }

    func localized(for language: AppLanguage, locale: Locale = .autoupdatingCurrent) -> DailyInsightNarrative {
        let targetLanguageCode = language.aiNarrativeLanguageCode(locale: locale)
        guard targetLanguageCode != sourceLanguageCode,
              let localized = localizedTexts?[targetLanguageCode] else {
            return self
        }

        var copy = self
        copy.headline = localized.headline
        copy.summary = localized.summary
        copy.bullets = localized.bullets
        return copy
    }

    func addingLocalizedText(_ localizedText: LocalizedText, for languageCode: String) -> DailyInsightNarrative {
        var copy = self
        var variants = copy.localizedTexts ?? [:]
        variants[languageCode] = localizedText
        copy.localizedTexts = variants
        return copy
    }
}

struct DailyInsightReport: Equatable {
    var date: Date
    var overallScore: Int
    var title: String
    var summary: String
    var components: [DailyInsightComponent]
    var highlights: [String]

    var includedComponents: [DailyInsightComponent] {
        components.filter(\.isIncluded)
    }

    func applyingAIOverrides(_ narrative: DailyInsightNarrative?) -> DailyInsightReport {
        guard let narrative else { return self }

        let overriddenComponents = components.map { component in
            guard let override = narrative.components?[component.kind.rawValue] else {
                return component
            }

            var updated = component
            if let included = override.included {
                updated.isIncluded = included
            }
            if let score = override.score {
                updated.score = max(0, score)
                updated.maxScore = max(1, override.maxScore ?? 100)
            } else if let maxScore = override.maxScore {
                updated.maxScore = max(1, maxScore)
            }
            if let detail = override.detail?.trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty {
                updated.detail = detail
            }
            if !updated.isIncluded {
                updated.score = 0
            } else {
                updated.score = min(updated.score, updated.maxScore)
            }
            return updated
        }

        let included = overriddenComponents.filter(\.isIncluded)
        let fallbackOverall: Int = {
            guard !included.isEmpty else { return 0 }
            let averageRatio = included.map(\.scoreRatio).reduce(0, +) / Double(included.count)
            return Int((averageRatio * 100).rounded())
        }()

        let headline = narrative.headline.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = narrative.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let bullets = narrative.bullets
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return DailyInsightReport(
            date: date,
            overallScore: max(0, min(narrative.overallScore ?? fallbackOverall, 100)),
            title: headline.isEmpty ? title : headline,
            summary: summary.isEmpty ? self.summary : summary,
            components: overriddenComponents,
            highlights: bullets.isEmpty ? highlights : bullets
        )
    }
}

struct DailyInsightPayload: Codable {
    struct StatisticSummary: Codable {
        var average: Double?
        var standardDeviation: Double?
    }

    struct HistoryWindowSummary: Codable {
        var windowDays: Int
        var recordedDays: Int
        var sleepDurationHours: StatisticSummary
        var mealCompletionRate: StatisticSummary
        var timedMealLoggingRate: StatisticSummary
        var showerCount: StatisticSummary
        var bowelMovementCount: StatisticSummary
        var bedtimeDeviationMinutes: StatisticSummary
        var note: String?
    }

    struct HistoryContext: Codable {
        var trailing7Days: HistoryWindowSummary
        var trailing30Days: HistoryWindowSummary
    }

    struct SleepSection: Codable {
        var source: String
        var bedtimeISO8601: String?
        var bedtimeLocal: String?
        var wakeISO8601: String?
        var wakeLocal: String?
        var targetBedtime: String?
        var durationHours: Double?
        var hasStageData: Bool
        var timeZoneIdentifier: String?
        var note: String?
    }

    struct MealSection: Codable {
        var title: String
        var status: String
        var timeISO8601: String?
        var timeLocal: String?
        var hasPhoto: Bool
        var note: String?
    }

    struct EventSection: Codable {
        var title: String?
        var status: String?
        var timeISO8601: String?
        var timeLocal: String?
        var note: String?
    }

    struct TimelineEntry: Codable {
        var order: Int
        var category: String
        var title: String
        var status: String
        var timeISO8601: String?
        var timeLocal: String?
        var detail: String?
    }

    struct RubricSection: Codable {
        var key: String
        var title: String
        var maxScore: Int
        var fullCreditRule: String
        var partialCreditRule: String
        var cautionRule: String
    }

    struct ScoringRubric: Codable {
        var sampleCount: Int
        var overallMethod: String
        var sections: [RubricSection]
    }

    var language: String
    var analysisDate: String
    var analysisDateTitle: String
    var appTimeZoneIdentifier: String
    var funOnlyDisclaimer: String
    var sleep: SleepSection
    var meals: [MealSection]
    var showerEnabled: Bool
    var showers: [EventSection]
    var bowelMovementEnabled: Bool
    var bowelMovements: [EventSection]
    var timeline: [TimelineEntry]
    var scoringRubric: ScoringRubric
    var comparisonContext: HistoryContext
}

enum DailyInsightAnalyzer {
    static func buildReport(
        for record: DailyRecord,
        preferences: UserPreferences,
        locale: Locale
    ) -> DailyInsightReport {
        let sleepResult = sleepComponent(for: record, preferences: preferences)
        let mealResult = mealComponent(for: record)
        let showerEnabled = preferences.visibleHomeSections.contains(.showers)
        let bowelEnabled = preferences.visibleHomeSections.contains(.bowelMovements)
        let showerResult = hygieneComponent(
            kind: .shower,
            enabled: showerEnabled,
            count: record.showers.count
        )
        let bowelResult = hygieneComponent(
            kind: .bowelMovement,
            enabled: bowelEnabled,
            count: record.bowelMovements.count
        )

        let components = [
            sleepResult.component,
            mealResult.component,
            showerResult.component,
            bowelResult.component
        ]

        let included = components.filter(\.isIncluded)
        let totalScore = included.reduce(0) { $0 + $1.score }
        let totalMax = max(included.reduce(0) { $0 + $1.maxScore }, 1)
        let overallScore = Int((Double(totalScore) / Double(totalMax) * 100).rounded())
        let title = headline(for: overallScore)
        let summary = summary(
            for: overallScore,
            components: included
        )

        let highlights = (sleepResult.highlights + mealResult.highlights + showerResult.highlights + bowelResult.highlights)
            .uniqued()
            .prefix(4)

        return DailyInsightReport(
            date: record.date.startOfDay,
            overallScore: overallScore,
            title: title,
            summary: summary,
            components: components,
            highlights: Array(highlights.isEmpty ? [fallbackHighlight(for: overallScore)] : highlights)
        )
    }

    static func makePayload(
        record: DailyRecord,
        preferences: UserPreferences,
        language: AppLanguage,
        locale: Locale,
        history: [DailyRecord]
    ) -> DailyInsightPayload {
        let sleepTimeZone = TimeZone(identifier: record.sleepRecord.timeZoneIdentifier ?? "") ?? .autoupdatingCurrent

        let meals = record.meals.map { entry in
            DailyInsightPayload.MealSection(
                title: entry.displayTitle,
                status: mealStatusName(entry, recordDate: record.date),
                timeISO8601: entry.time?.displayISO8601,
                timeLocal: localizedClockTime(entry.time, timeZoneIdentifier: entry.timeZoneIdentifier),
                hasPhoto: entry.hasPhoto,
                note: trimmedOptional(entry.note)
            )
        }

        let showers = record.showers.map {
            DailyInsightPayload.EventSection(
                title: NSLocalizedString("洗澡", comment: ""),
                status: "logged",
                timeISO8601: $0.time?.displayISO8601,
                timeLocal: localizedClockTime($0.time, timeZoneIdentifier: $0.timeZoneIdentifier),
                note: trimmedOptional($0.note)
            )
        }

        let bowelMovements = record.bowelMovements.map {
            DailyInsightPayload.EventSection(
                title: NSLocalizedString("排便", comment: ""),
                status: "logged",
                timeISO8601: $0.time?.displayISO8601,
                timeLocal: localizedClockTime($0.time, timeZoneIdentifier: $0.timeZoneIdentifier),
                note: trimmedOptional($0.note)
            )
        }

        let timeline = dailyTimeline(for: record)

        return DailyInsightPayload(
            language: language.displayNameForPrompt,
            analysisDate: record.date.storageKey(),
            analysisDateTitle: record.date.formattedDayTitle(locale: locale),
            appTimeZoneIdentifier: TimeZone.autoupdatingCurrent.identifier,
            funOnlyDisclaimer: NSLocalizedString("这是趣味性 AI 分析，不是医疗或健康建议。", comment: ""),
            sleep: DailyInsightPayload.SleepSection(
                source: record.sleepRecord.source.rawValue,
                bedtimeISO8601: record.sleepRecord.bedtimePreviousNight?.displayISO8601,
                bedtimeLocal: record.sleepRecord.bedtimePreviousNight?.displayClockTime(in: sleepTimeZone),
                wakeISO8601: record.sleepRecord.wakeTimeCurrentDay?.displayISO8601,
                wakeLocal: record.sleepRecord.wakeTimeCurrentDay?.displayClockTime(in: sleepTimeZone),
                targetBedtime: record.sleepRecord.targetBedtime?.canonicalDisplayTime,
                durationHours: record.sleepRecord.duration.map { ($0 / 3600 * 10).rounded() / 10 },
                hasStageData: record.sleepRecord.hasStageData,
                timeZoneIdentifier: record.sleepRecord.timeZoneIdentifier,
                note: trimmedOptional(record.sleepRecord.note)
            ),
            meals: meals,
            showerEnabled: preferences.visibleHomeSections.contains(.showers),
            showers: showers,
            bowelMovementEnabled: preferences.visibleHomeSections.contains(.bowelMovements),
            bowelMovements: bowelMovements,
            timeline: timeline,
            scoringRubric: scoringRubric(),
            comparisonContext: historyContext(
                for: record,
                preferences: preferences,
                history: history
            )
        )
    }

    private static func historyContext(
        for record: DailyRecord,
        preferences: UserPreferences,
        history: [DailyRecord]
    ) -> DailyInsightPayload.HistoryContext {
        DailyInsightPayload.HistoryContext(
            trailing7Days: historyWindowSummary(
                for: record,
                lookbackDays: 7,
                preferences: preferences,
                history: history
            ),
            trailing30Days: historyWindowSummary(
                for: record,
                lookbackDays: 30,
                preferences: preferences,
                history: history
            )
        )
    }

    private static func dailyTimeline(for record: DailyRecord) -> [DailyInsightPayload.TimelineEntry] {
        struct Candidate {
            var sortDate: Date?
            var category: String
            var title: String
            var status: String
            var detail: String?
            var timeZoneIdentifier: String?
        }

        var candidates: [Candidate] = []

        if let bedtime = record.sleepRecord.bedtimePreviousNight {
            candidates.append(
                Candidate(
                    sortDate: bedtime,
                    category: "sleep",
                    title: NSLocalizedString("入睡", comment: ""),
                    status: "logged",
                    detail: record.sleepRecord.duration.map {
                        String(format: NSLocalizedString("总睡眠 %.1f 小时", comment: ""), $0 / 3600)
                    },
                    timeZoneIdentifier: record.sleepRecord.timeZoneIdentifier
                )
            )
        }

        if let wake = record.sleepRecord.wakeTimeCurrentDay {
            candidates.append(
                Candidate(
                    sortDate: wake,
                    category: "sleep",
                    title: NSLocalizedString("起床", comment: ""),
                    status: "logged",
                    detail: nil,
                    timeZoneIdentifier: record.sleepRecord.timeZoneIdentifier
                )
            )
        }

        for meal in record.meals {
            let status = mealStatusName(meal, recordDate: record.date)
            candidates.append(
                Candidate(
                    sortDate: meal.time,
                    category: "meal",
                    title: meal.displayTitle,
                    status: status,
                    detail: meal.note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                        ? NSLocalizedString("含备注", comment: "")
                        : (meal.hasPhoto ? NSLocalizedString("含照片", comment: "") : nil),
                    timeZoneIdentifier: meal.timeZoneIdentifier
                )
            )
        }

        for shower in record.showers {
            candidates.append(
                Candidate(
                    sortDate: shower.time,
                    category: "shower",
                    title: NSLocalizedString("洗澡", comment: ""),
                    status: "logged",
                    detail: trimmedOptional(shower.note),
                    timeZoneIdentifier: shower.timeZoneIdentifier
                )
            )
        }

        for bowel in record.bowelMovements {
            candidates.append(
                Candidate(
                    sortDate: bowel.time,
                    category: "bowelMovement",
                    title: NSLocalizedString("排便", comment: ""),
                    status: "logged",
                    detail: trimmedOptional(bowel.note),
                    timeZoneIdentifier: bowel.timeZoneIdentifier
                )
            )
        }

        let sorted = candidates.enumerated().sorted { lhs, rhs in
            switch (lhs.element.sortDate, rhs.element.sortDate) {
            case let (left?, right?):
                if left == right {
                    return lhs.offset < rhs.offset
                }
                return left < right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.offset < rhs.offset
            }
        }

        return sorted.enumerated().map { index, item in
            DailyInsightPayload.TimelineEntry(
                order: index + 1,
                category: item.element.category,
                title: item.element.title,
                status: item.element.status,
                timeISO8601: item.element.sortDate?.displayISO8601,
                timeLocal: localizedClockTime(item.element.sortDate, timeZoneIdentifier: item.element.timeZoneIdentifier),
                detail: item.element.detail
            )
        }
    }

    private static func scoringRubric() -> DailyInsightPayload.ScoringRubric {
        DailyInsightPayload.ScoringRubric(
            sampleCount: 5,
            overallMethod: NSLocalizedString("四个部分按固定满分评分后，按总分折算到 0-100。", comment: ""),
            sections: [
                .init(
                    key: "sleep",
                    title: NSLocalizedString("睡眠", comment: ""),
                    maxScore: 45,
                    fullCreditRule: NSLocalizedString("7-9 小时且入睡时间接近目标，记录完整时可拿高分。", comment: ""),
                    partialCreditRule: NSLocalizedString("时长稍短/稍长，或作息与目标相差 30-120 分钟，拿中间分。", comment: ""),
                    cautionRule: NSLocalizedString("时长明显不足、严重偏离目标或记录残缺时，才给低分。", comment: "")
                ),
                .init(
                    key: "meals",
                    title: NSLocalizedString("餐食", comment: ""),
                    maxScore: 35,
                    fullCreditRule: NSLocalizedString("三餐记录完整、时间清楚、时间线合理时可拿高分。", comment: ""),
                    partialCreditRule: NSLocalizedString("仅记录有无但没写时间，仍算完成，只扣少量完整度分。", comment: ""),
                    cautionRule: NSLocalizedString("必须结合起床时间和整天时间线判断，不能凭空批评用户没吃早餐。若起床已接近中午，跳过早餐只能算轻微影响或合理。", comment: "")
                ),
                .init(
                    key: "shower",
                    title: NSLocalizedString("洗澡", comment: ""),
                    maxScore: 10,
                    fullCreditRule: NSLocalizedString("启用该项目且有明确记录时，可给 8-10 分。", comment: ""),
                    partialCreditRule: NSLocalizedString("没有记录时给保守中低分，不做重罚。", comment: ""),
                    cautionRule: NSLocalizedString("如果该项目未启用，必须 excluded，不得纳入总分。", comment: "")
                ),
                .init(
                    key: "bowelMovement",
                    title: NSLocalizedString("排便", comment: ""),
                    maxScore: 10,
                    fullCreditRule: NSLocalizedString("启用该项目且有明确记录时，可给 8-10 分。", comment: ""),
                    partialCreditRule: NSLocalizedString("没有记录时给保守中低分，不做重罚。", comment: ""),
                    cautionRule: NSLocalizedString("如果该项目未启用，必须 excluded，不得纳入总分。", comment: "")
                )
            ]
        )
    }

    private static func historyWindowSummary(
        for record: DailyRecord,
        lookbackDays: Int,
        preferences: UserPreferences,
        history: [DailyRecord]
    ) -> DailyInsightPayload.HistoryWindowSummary {
        let endDate = record.date.startOfDay
        let startDate = endDate.adding(days: -lookbackDays)
        let windowRecords = history
            .filter {
                let day = $0.date.startOfDay
                return day >= startDate && day < endDate
            }
            .sorted { $0.date < $1.date }

        let sleepHours = windowRecords.compactMap { $0.sleepRecord.duration.map { ($0 / 3600 * 10).rounded() / 10 } }
        let mealCompletionRates = windowRecords.map(mealCompletionRate(for:))
        let timedMealLoggingRates = windowRecords.map(timedMealLoggingRate(for:))
        let showerCounts = preferences.visibleHomeSections.contains(.showers)
            ? windowRecords.map { Double($0.showers.count) }
            : []
        let bowelMovementCounts = preferences.visibleHomeSections.contains(.bowelMovements)
            ? windowRecords.map { Double($0.bowelMovements.count) }
            : []
        let bedtimeDeviationValues = windowRecords.compactMap {
            bedtimeDeviationMinutes(for: $0.sleepRecord)
        }

        let note: String? = {
            guard !windowRecords.isEmpty else {
                return NSLocalizedString("历史样本还不够，暂时只参考当天表现。", comment: "")
            }
            if windowRecords.count < min(lookbackDays, 3) {
                return String(
                    format: NSLocalizedString("最近只有 %d 天可用记录，趋势判断会更保守。", comment: ""),
                    windowRecords.count
                )
            }
            return nil
        }()

        return DailyInsightPayload.HistoryWindowSummary(
            windowDays: lookbackDays,
            recordedDays: windowRecords.count,
            sleepDurationHours: statisticSummary(for: sleepHours),
            mealCompletionRate: statisticSummary(for: mealCompletionRates),
            timedMealLoggingRate: statisticSummary(for: timedMealLoggingRates),
            showerCount: statisticSummary(for: showerCounts),
            bowelMovementCount: statisticSummary(for: bowelMovementCounts),
            bedtimeDeviationMinutes: statisticSummary(for: bedtimeDeviationValues),
            note: note
        )
    }

    private static func sleepComponent(
        for record: DailyRecord,
        preferences: UserPreferences
    ) -> (component: DailyInsightComponent, highlights: [String]) {
        let maxScore = 45
        let sleep = record.sleepRecord
        guard sleep.hasSleepData else {
            return (
                DailyInsightComponent(
                    kind: .sleep,
                    score: 0,
                    maxScore: maxScore,
                    detail: NSLocalizedString("还没有睡眠记录", comment: ""),
                    isIncluded: true
                ),
                [NSLocalizedString("昨天还没有睡眠记录，所以这部分暂时没有加分。", comment: "")]
            )
        }

        guard let bedtime = sleep.bedtimePreviousNight,
              let wake = sleep.wakeTimeCurrentDay,
              let duration = sleep.duration else {
            return (
                DailyInsightComponent(
                    kind: .sleep,
                    score: 14,
                    maxScore: maxScore,
                    detail: NSLocalizedString("睡眠时间记录还不完整", comment: ""),
                    isIncluded: true
                ),
                [NSLocalizedString("睡眠记录只有一半，补齐入睡和起床时间后会更准确。", comment: "")]
            )
        }

        let durationHours = duration / 3600
        let durationScore: Int
        switch durationHours {
        case 7.0...9.0:
            durationScore = 25
        case 6.5..<7.0, 9.0...9.5:
            durationScore = 21
        case 6.0..<6.5, 9.5...10.0:
            durationScore = 17
        case 5.0..<6.0, 10.0...11.0:
            durationScore = 10
        default:
            durationScore = 4
        }

        let bedtimeScore = bedtimeAlignmentScore(bedtime: bedtime, target: sleep.targetBedtime, timeZoneIdentifier: sleep.timeZoneIdentifier)
        let completenessScore = 7 + (sleep.hasStageData ? 3 : 0)
        let total = min(maxScore, durationScore + bedtimeScore + completenessScore)

        let timeZone = TimeZone(identifier: sleep.timeZoneIdentifier ?? "") ?? .autoupdatingCurrent
        let detail = String(
            format: NSLocalizedString("%@ 到 %@，共 %.1f 小时", comment: ""),
            bedtime.displayClockTime(in: timeZone),
            wake.displayClockTime(in: timeZone),
            durationHours
        )

        var highlights: [String] = []
        if durationHours < 6.5 {
            highlights.append(NSLocalizedString("睡眠时长偏短，是昨天最明显的扣分点。", comment: ""))
        } else if durationHours > 9.5 {
            highlights.append(NSLocalizedString("睡眠时间偏长，可能说明昨天整体恢复感比较重。", comment: ""))
        } else {
            highlights.append(NSLocalizedString("睡眠时长落在比较稳的区间，整体是加分项。", comment: ""))
        }

        if bedtimeScore <= 4 {
            highlights.append(NSLocalizedString("入睡时间和目标时间偏差较大，作息规律性还有提升空间。", comment: ""))
        }

        return (
            DailyInsightComponent(
                kind: .sleep,
                score: total,
                maxScore: maxScore,
                detail: detail,
                isIncluded: true
            ),
            highlights
        )
    }

    private static func mealComponent(for record: DailyRecord) -> (component: DailyInsightComponent, highlights: [String]) {
        let maxScore = 35
        let meals = record.meals
        guard !meals.isEmpty else {
            return (
                DailyInsightComponent(
                    kind: .meals,
                    score: 0,
                    maxScore: maxScore,
                    detail: NSLocalizedString("还没有餐食设置", comment: ""),
                    isIncluded: true
                ),
                [NSLocalizedString("昨天没有可分析的餐食数据。", comment: "")]
            )
        }

        let statuses = meals.map { mealStatusName($0, recordDate: record.date) }
        let loggedCount = statuses.filter { $0.hasPrefix("logged") }.count
        let skippedCount = statuses.filter { $0 == "skipped" }.count
        let missingCount = statuses.filter { $0 == "unrecorded" }.count
        let timedLoggedCount = meals.filter {
            mealStatusName($0, recordDate: record.date).hasPrefix("logged") && $0.time != nil
        }.count

        let baseRatio = statuses.reduce(0.0) { partial, status in
            switch status {
            case "logged_with_time":
                partial + 1.0
            case "logged_without_time":
                partial + 0.88
            case "skipped":
                partial + 0.42
            default:
                partial + 0.2
            }
        } / Double(max(meals.count, 1))
        let timeBonus = Double(timedLoggedCount) / Double(max(meals.count, 1)) * 0.15
        let total = Int((min(baseRatio + timeBonus, 1.0) * Double(maxScore)).rounded())

        let detail = String(
            format: NSLocalizedString("已记录 %d/%d 个餐次", comment: ""),
            loggedCount,
            meals.count
        )

        var highlights: [String] = []
        if missingCount == 0 {
            highlights.append(NSLocalizedString("昨天的餐食记录比较完整，这一项整体是加分的。", comment: ""))
        } else {
            highlights.append(String(
                format: NSLocalizedString("还有 %d 个餐次没有记录，餐食分数主要扣在完整度上。", comment: ""),
                missingCount
            ))
        }
        if skippedCount > 0 {
            highlights.append(String(
                format: NSLocalizedString("其中有 %d 个餐次被主动标记为跳过。", comment: ""),
                skippedCount
            ))
        }

        return (
            DailyInsightComponent(
                kind: .meals,
                score: total,
                maxScore: maxScore,
                detail: detail,
                isIncluded: true
            ),
            highlights
        )
    }

    private static func mealCompletionRate(for record: DailyRecord) -> Double {
        guard !record.meals.isEmpty else { return 0 }
        let completed = record.meals.reduce(0.0) { partial, meal in
            switch mealStatusName(meal, recordDate: record.date) {
            case "logged_with_time":
                partial + 1.0
            case "logged_without_time":
                partial + 0.8
            case "skipped":
                partial + 0.4
            default:
                partial
            }
        }
        return (completed / Double(record.meals.count) * 100).rounded() / 100
    }

    private static func timedMealLoggingRate(for record: DailyRecord) -> Double {
        let loggedMeals = record.meals.filter {
            mealStatusName($0, recordDate: record.date).hasPrefix("logged")
        }
        guard !loggedMeals.isEmpty else { return 0 }
        let timedMeals = loggedMeals.filter { $0.time != nil }
        return (Double(timedMeals.count) / Double(loggedMeals.count) * 100).rounded() / 100
    }

    private static func hygieneComponent(
        kind: DailyInsightComponentKind,
        enabled: Bool,
        count: Int
    ) -> (component: DailyInsightComponent, highlights: [String]) {
        let maxScore = 10
        guard enabled else {
            return (
                DailyInsightComponent(
                    kind: kind,
                    score: 0,
                    maxScore: maxScore,
                    detail: NSLocalizedString("未纳入昨天的分析范围", comment: ""),
                    isIncluded: false
                ),
                []
            )
        }

        if count == 0 {
            return (
                DailyInsightComponent(
                    kind: kind,
                    score: 4,
                    maxScore: maxScore,
                    detail: NSLocalizedString("昨天没有相关记录", comment: ""),
                    isIncluded: true
                ),
                [String(format: NSLocalizedString("%@这部分昨天没有记录，所以分数偏保守。", comment: ""), kind.title)]
            )
        }

        let score = min(maxScore, 7 + min(count, 3))
        let detail = String(
            format: NSLocalizedString("记录了 %d 次", comment: ""),
            count
        )
        return (
            DailyInsightComponent(
                kind: kind,
                score: score,
                maxScore: maxScore,
                detail: detail,
                isIncluded: true
            ),
            [String(format: NSLocalizedString("%@有明确记录，这部分拿到了稳定加分。", comment: ""), kind.title)]
        )
    }

    private static func bedtimeAlignmentScore(
        bedtime: Date,
        target: DateComponents?,
        timeZoneIdentifier: String?
    ) -> Int {
        guard let target else { return 6 }
        let timeZone = TimeZone(identifier: timeZoneIdentifier ?? "") ?? .autoupdatingCurrent
        var calendar = Calendar.current
        calendar.timeZone = timeZone

        let actual = calendar.dateComponents([.hour, .minute], from: bedtime)
        let actualMinutes = normalizedBedtimeMinutes(hour: actual.hour ?? 0, minute: actual.minute ?? 0)
        let targetMinutes = normalizedBedtimeMinutes(hour: target.hour ?? 0, minute: target.minute ?? 0)
        let delta = abs(actualMinutes - targetMinutes)

        switch delta {
        case ...30:
            return 10
        case ...60:
            return 8
        case ...90:
            return 6
        case ...120:
            return 4
        default:
            return 1
        }
    }

    private static func bedtimeDeviationMinutes(for sleep: SleepRecord) -> Double? {
        guard let bedtime = sleep.bedtimePreviousNight,
              let target = sleep.targetBedtime else {
            return nil
        }

        let timeZone = TimeZone(identifier: sleep.timeZoneIdentifier ?? "") ?? .autoupdatingCurrent
        var calendar = Calendar.current
        calendar.timeZone = timeZone

        let actual = calendar.dateComponents([.hour, .minute], from: bedtime)
        let actualMinutes = normalizedBedtimeMinutes(hour: actual.hour ?? 0, minute: actual.minute ?? 0)
        let targetMinutes = normalizedBedtimeMinutes(hour: target.hour ?? 0, minute: target.minute ?? 0)
        return Double(abs(actualMinutes - targetMinutes))
    }

    private static func statisticSummary(for values: [Double]) -> DailyInsightPayload.StatisticSummary {
        guard !values.isEmpty else {
            return DailyInsightPayload.StatisticSummary(average: nil, standardDeviation: nil)
        }

        let average = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { partial, value in
            partial + pow(value - average, 2)
        } / Double(values.count)

        return DailyInsightPayload.StatisticSummary(
            average: (average * 100).rounded() / 100,
            standardDeviation: (sqrt(variance) * 100).rounded() / 100
        )
    }

    private static func normalizedBedtimeMinutes(hour: Int, minute: Int) -> Int {
        let minutes = hour * 60 + minute
        return minutes >= 12 * 60 ? minutes - 24 * 60 : minutes
    }

    private static func headline(for score: Int) -> String {
        switch score {
        case 85...:
            return NSLocalizedString("昨天状态很稳", comment: "")
        case 70...84:
            return NSLocalizedString("昨天整体不错", comment: "")
        case 55...69:
            return NSLocalizedString("昨天有点乱", comment: "")
        default:
            return NSLocalizedString("昨天需要重整节奏", comment: "")
        }
    }

    private static func summary(for score: Int, components: [DailyInsightComponent]) -> String {
        let sorted = components.sorted { $0.scoreRatio > $1.scoreRatio }
        guard let best = sorted.first, let weakest = sorted.last else {
            return NSLocalizedString("现在的数据还不足以形成稳定分析。", comment: "")
        }

        if best.kind == weakest.kind {
            return String(
                format: NSLocalizedString("%@是昨天最主要的参考项，目前整体分数在 %d 分。", comment: ""),
                best.kind.title,
                score
            )
        }

        return String(
            format: NSLocalizedString("主要加分项是%@，目前最值得再留意的是%@。", comment: ""),
            best.kind.title,
            weakest.kind.title
        )
    }

    private static func fallbackHighlight(for score: Int) -> String {
        switch score {
        case 80...:
            return NSLocalizedString("昨天的整体节奏比较顺，可以继续保持。", comment: "")
        case 60...79:
            return NSLocalizedString("昨天整体还可以，但还有一两项记录不够稳。", comment: "")
        default:
            return NSLocalizedString("昨天的数据提示节奏有些散，今天可以再收一收。", comment: "")
        }
    }

    private static func mealStatusName(_ entry: MealEntry, recordDate: Date) -> String {
        let status = entry.effectiveStatus(on: recordDate, relativeTo: recordDate)
        switch status {
        case .logged:
            return entry.time != nil ? "logged_with_time" : "logged_without_time"
        case .skipped:
            return "skipped"
        case .empty:
            return "unrecorded"
        }
    }

    private static func localizedClockTime(_ date: Date?, timeZoneIdentifier: String?) -> String? {
        guard let date else { return nil }
        let timeZone = TimeZone(identifier: timeZoneIdentifier ?? "") ?? .autoupdatingCurrent
        return date.displayClockTime(in: timeZone)
    }

    private static func trimmedOptional(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

protocol OpenAIKeyStoring: Sendable {
    var hasAPIKey: Bool { get }
    func loadAPIKey() -> String?
    func saveAPIKey(_ key: String) throws
    func deleteAPIKey()
}

struct OpenAIKeychainStore: OpenAIKeyStoring, Sendable {
    private let service = "com.flyfishyu.DailyLogs.openai.api-key"
    private let account = "default"

    var hasAPIKey: Bool {
        loadAPIKey()?.isEmpty == false
    }

    func loadAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func saveAPIKey(_ key: String) throws {
        let data = Data(key.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)

        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    func deleteAPIKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

protocol AIInsightNarrativeGenerating: Sendable {
    var isConfigured: Bool { get }
    func generateNarrative(from payload: DailyInsightPayload) async throws -> DailyInsightNarrative
    func translateNarrative(_ narrative: DailyInsightNarrative, to language: AppLanguage) async throws -> DailyInsightNarrative.LocalizedText
}

struct NoopAIInsightNarrativeService: AIInsightNarrativeGenerating, Sendable {
    var isConfigured: Bool { false }

    func generateNarrative(from payload: DailyInsightPayload) async throws -> DailyInsightNarrative {
        throw AIInsightServiceError.missingAPIKey
    }

    func translateNarrative(_ narrative: DailyInsightNarrative, to language: AppLanguage) async throws -> DailyInsightNarrative.LocalizedText {
        throw AIInsightServiceError.missingAPIKey
    }
}

enum AIInsightServiceError: LocalizedError {
    case missingAPIKey
    case missingAuthToken
    case invalidAuthToken
    case missingProxyURL
    case invalidResponse
    case emptyResponse
    case missingScores
    case dailyLimitReached(limit: Int?)
    case providerError(String)
    case requestFailed(statusCode: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return NSLocalizedString("还没有配置 OpenAI API Key。", comment: "")
        case .missingAuthToken:
            return NSLocalizedString("云端 AI 需要登录后的 Firebase 身份令牌。", comment: "")
        case .invalidAuthToken:
            return NSLocalizedString("云端 AI 的登录状态已过期，请重新登录后再试。", comment: "")
        case .missingProxyURL:
            return NSLocalizedString("云端 AI 代理地址还没有配置。", comment: "")
        case .invalidResponse:
            return NSLocalizedString("AI 返回的数据格式无法识别。", comment: "")
        case .emptyResponse:
            return NSLocalizedString("AI 这次没有返回可用内容。", comment: "")
        case .missingScores:
            return NSLocalizedString("AI 返回了文案，但没有返回分数。", comment: "")
        case .dailyLimitReached(let limit):
            if let limit, limit > 0 {
                return String(
                    format: NSLocalizedString("今天的 AI 评分次数已用完（上限 %d 次），请稍后再试。", comment: ""),
                    limit
                )
            }
            return NSLocalizedString("今天的 AI 评分次数已用完，请稍后再试。", comment: "")
        case .providerError(let message):
            return message
        case .requestFailed(let statusCode, let message):
            if let message, !message.isEmpty {
                return message
            }
            return String(
                format: NSLocalizedString("AI 服务暂时不可用（%d）。", comment: ""),
                statusCode
            )
        }
    }
}

struct AIProxyConfiguration: Sendable {
    private static let urlKey = "AIProxyURL"

    let endpointURL: URL?

    init(bundle: Bundle = .main) {
        let rawValue = bundle.object(forInfoDictionaryKey: Self.urlKey) as? String
        let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            endpointURL = URL(string: trimmed)
        } else {
            endpointURL = nil
        }
    }

    init(endpointURL: URL?) {
        self.endpointURL = endpointURL
    }

    var isConfigured: Bool {
        endpointURL != nil
    }
}

struct OpenAIResponsesInsightService: AIInsightNarrativeGenerating, Sendable {
    private let keyStore: OpenAIKeyStoring
    private let session: URLSession
    private let model: String

    init(
        keyStore: OpenAIKeyStoring,
        session: URLSession = .shared,
        model: String = "gpt-5.4-mini"
    ) {
        self.keyStore = keyStore
        self.session = session
        self.model = model
    }

    var isConfigured: Bool {
        keyStore.hasAPIKey
    }

    func generateNarrative(from payload: DailyInsightPayload) async throws -> DailyInsightNarrative {
        guard let apiKey = keyStore.loadAPIKey(), !apiKey.isEmpty else {
            throw AIInsightServiceError.missingAPIKey
        }

        return try await generateAveragedNarrative(sampleCount: 5) {
            try await performNarrativeRequest(
                endpointURL: URL(string: "https://api.openai.com/v1/responses")!,
                authorizationHeader: "Bearer \(apiKey)",
                payload: payload,
                model: model,
                session: session
            )
        }
    }

    func translateNarrative(_ narrative: DailyInsightNarrative, to language: AppLanguage) async throws -> DailyInsightNarrative.LocalizedText {
        guard let apiKey = keyStore.loadAPIKey(), !apiKey.isEmpty else {
            throw AIInsightServiceError.missingAPIKey
        }

        return try await performTranslationRequest(
            endpointURL: URL(string: "https://api.openai.com/v1/responses")!,
            authorizationHeader: "Bearer \(apiKey)",
            narrative: narrative,
            targetLanguage: language,
            model: model,
            session: session
        )
    }
}

struct CloudAIInsightService: AIInsightNarrativeGenerating, Sendable {
    private let configuration: AIProxyConfiguration
    private let session: URLSession
    private let model: String
    private let authTokenProvider: @Sendable () async throws -> String?

    init(
        configuration: AIProxyConfiguration = AIProxyConfiguration(),
        session: URLSession = .shared,
        model: String = "gpt-5.4-mini",
        authTokenProvider: @escaping @Sendable () async throws -> String? = {
            try await fetchFirebaseIDToken()
        }
    ) {
        self.configuration = configuration
        self.session = session
        self.model = model
        self.authTokenProvider = authTokenProvider
    }

    var isConfigured: Bool {
        configuration.isConfigured
    }

    func generateNarrative(from payload: DailyInsightPayload) async throws -> DailyInsightNarrative {
        guard let endpointURL = configuration.endpointURL else {
            throw AIInsightServiceError.missingProxyURL
        }
        guard let idToken = try await authTokenProvider(), !idToken.isEmpty else {
            throw AIInsightServiceError.missingAuthToken
        }

        return try await generateAveragedNarrative(sampleCount: 5) {
            try await performNarrativeRequest(
                endpointURL: endpointURL,
                authorizationHeader: "Bearer \(idToken)",
                payload: payload,
                model: model,
                session: session
            )
        }
    }

    func translateNarrative(_ narrative: DailyInsightNarrative, to language: AppLanguage) async throws -> DailyInsightNarrative.LocalizedText {
        guard let endpointURL = configuration.endpointURL else {
            throw AIInsightServiceError.missingProxyURL
        }
        guard let idToken = try await authTokenProvider(), !idToken.isEmpty else {
            throw AIInsightServiceError.missingAuthToken
        }

        return try await performTranslationRequest(
            endpointURL: endpointURL,
            authorizationHeader: "Bearer \(idToken)",
            narrative: narrative,
            targetLanguage: language,
            model: model,
            session: session
        )
    }
}

struct HybridAIInsightNarrativeService: AIInsightNarrativeGenerating, Sendable {
    private let cloudService: CloudAIInsightService
    private let customKeyService: OpenAIResponsesInsightService

    init(
        cloudService: CloudAIInsightService,
        customKeyService: OpenAIResponsesInsightService
    ) {
        self.cloudService = cloudService
        self.customKeyService = customKeyService
    }

    var isConfigured: Bool {
        customKeyService.isConfigured || cloudService.isConfigured
    }

    func generateNarrative(from payload: DailyInsightPayload) async throws -> DailyInsightNarrative {
        if customKeyService.isConfigured {
            return try await customKeyService.generateNarrative(from: payload)
        }
        return try await cloudService.generateNarrative(from: payload)
    }

    func translateNarrative(_ narrative: DailyInsightNarrative, to language: AppLanguage) async throws -> DailyInsightNarrative.LocalizedText {
        if customKeyService.isConfigured {
            return try await customKeyService.translateNarrative(narrative, to: language)
        }
        return try await cloudService.translateNarrative(narrative, to: language)
    }
}

private func performNarrativeRequest(
    endpointURL: URL,
    authorizationHeader: String,
    payload: DailyInsightPayload,
    model: String,
    session: URLSession
) async throws -> DailyInsightNarrative {
    var request = URLRequest(url: endpointURL)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    request.httpBody = try encoder.encode(makeRequestBody(from: payload, model: model))

    let (data, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse,
          200..<300 ~= httpResponse.statusCode else {
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        throw parseNarrativeRequestError(statusCode: statusCode, data: data)
    }

    return try parseNarrative(from: data)
}

private func performTranslationRequest(
    endpointURL: URL,
    authorizationHeader: String,
    narrative: DailyInsightNarrative,
    targetLanguage: AppLanguage,
    model: String,
    session: URLSession
) async throws -> DailyInsightNarrative.LocalizedText {
    var request = URLRequest(url: endpointURL)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    request.httpBody = try encoder.encode(
        makeTranslationRequestBody(
            from: narrative,
            targetLanguage: targetLanguage,
            model: model
        )
    )

    let (data, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse,
          200..<300 ~= httpResponse.statusCode else {
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        throw parseNarrativeRequestError(statusCode: statusCode, data: data)
    }

    return try parseLocalizedNarrativeText(from: data)
}

private func fetchFirebaseIDToken() async throws -> String? {
    return try await withCheckedThrowingContinuation { continuation in
        Task { @MainActor in
            guard let currentUser = Auth.auth().currentUser else {
                continuation.resume(returning: nil)
                return
            }

            currentUser.getIDToken { token, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: token)
                }
            }
        }
    }
}

private func parseNarrative(from data: Data) throws -> DailyInsightNarrative {
    if let narrative = tryDirectNarrative(from: data) {
        return narrative
    }

    let decoded = try JSONDecoder().decode(OpenAIResponseEnvelope.self, from: data)
    if let narrative = decoded.extractedNarrative {
        return narrative
    }

    if let refusal = decoded.extractedRefusal, !refusal.isEmpty {
        throw AIInsightServiceError.providerError(refusal)
    }

    guard let text = decoded.extractedText, !text.isEmpty else {
        throw AIInsightServiceError.emptyResponse
    }

    let jsonText = extractJSONObject(from: text)
    guard let jsonData = jsonText.data(using: .utf8) else {
        throw AIInsightServiceError.invalidResponse
    }

    let narrative = try JSONDecoder().decode(DailyInsightNarrative.self, from: jsonData)
    guard narrative.hasAIScoring else {
        #if DEBUG
        print("AI insight response missing scores:", jsonText)
        #endif
        throw AIInsightServiceError.missingScores
    }
    return narrative
}

private func parseLocalizedNarrativeText(from data: Data) throws -> DailyInsightNarrative.LocalizedText {
    let decoder = JSONDecoder()
    if let localizedText = try? decoder.decode(DailyInsightNarrative.LocalizedText.self, from: data) {
        return localizedText
    }

    if let envelope = try? decoder.decode(OpenAIResponseEnvelope.self, from: data) {
        if let parsed = envelope.output?
            .flatMap({ $0.content ?? [] })
            .compactMap(\.parsedLocalizedText)
            .first {
            return parsed
        }
        if let text = envelope.extractedText, !text.isEmpty {
            let jsonText = extractJSONObject(from: text)
            if let jsonData = jsonText.data(using: .utf8),
               let localizedText = try? decoder.decode(DailyInsightNarrative.LocalizedText.self, from: jsonData) {
                return localizedText
            }
        }
        if let refusal = envelope.extractedRefusal, !refusal.isEmpty {
            throw AIInsightServiceError.providerError(refusal)
        }
    }

    throw AIInsightServiceError.invalidResponse
}

private func parseNarrativeRequestError(statusCode: Int, data: Data) -> AIInsightServiceError {
    if let envelope = try? JSONDecoder().decode(AIErrorEnvelope.self, from: data) {
        switch envelope.errorValue {
        case .string("missing_auth_token"):
            return .missingAuthToken
        case .string("invalid_auth_token"):
            return .invalidAuthToken
        case .string("daily_limit_reached"):
            return .dailyLimitReached(limit: envelope.limit)
        case .string("rate_limit_failed"):
            return .providerError(NSLocalizedString("云端 AI 的限流检查失败，请稍后再试。", comment: ""))
        case .string("missing_openai_key"):
            return .providerError(NSLocalizedString("云端 AI 还没有配置可用的模型密钥。", comment: ""))
        case .string("openai_proxy_failed"):
            return .providerError(NSLocalizedString("云端 AI 代理调用上游失败，请稍后再试。", comment: ""))
        case .string(let code):
            return .requestFailed(statusCode: statusCode, message: code)
        case .provider(let providerError):
            let message = providerError.message?.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallback = providerError.code?.trimmingCharacters(in: .whitespacesAndNewlines)
            return .requestFailed(statusCode: statusCode, message: message?.isEmpty == false ? message : fallback)
        case .none:
            break
        }
    }

    switch statusCode {
    case 401:
        return .invalidAuthToken
    case 429:
        return .providerError(NSLocalizedString("AI 服务当前比较繁忙，请稍后再试。", comment: ""))
    default:
        return .requestFailed(statusCode: statusCode, message: nil)
    }
}

private func tryDirectNarrative(from data: Data) -> DailyInsightNarrative? {
    let decoder = JSONDecoder()

    if let narrative = try? decoder.decode(DailyInsightNarrative.self, from: data),
       narrative.hasAIScoring {
        return narrative
    }

    guard let rawText = String(data: data, encoding: .utf8) else {
        return nil
    }

    let jsonText = extractJSONObject(from: rawText)
    guard let jsonData = jsonText.data(using: .utf8),
          let narrative = try? decoder.decode(DailyInsightNarrative.self, from: jsonData),
          narrative.hasAIScoring else {
        return nil
    }

    return narrative
}

private func makeRequestBody(from payload: DailyInsightPayload, model: String) throws -> OpenAIResponsesRequestBody {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let payloadData = try encoder.encode(payload)
    let payloadString = String(decoding: payloadData, as: UTF8.self)

    return OpenAIResponsesRequestBody(
        model: model,
        instructions: """
        You are scoring one complete day of lifestyle logs for a journaling app.
        This is fun lifestyle analysis only, not medical advice, diagnosis, or treatment.
        Use only the provided JSON.
        First reconstruct the user's full day timeline from the previous-night bedtime through wake time, meals, showers, and bowel events.
        Use the timeline to avoid contradictions. Example: if wake time is near noon, skipping breakfast is not automatically a serious problem.
        The payload includes the target day, an ordered timeline, a fixed scoring rubric, and trailing 7-day/30-day statistics.
        Use the target day as the baseline, the 7-day summary for short-term trend context, and the 30-day summary for habit stability context.
        The payload does not include any precomputed score. Compute every score yourself from the raw data and the provided rubric.
        Respect whether a section is excluded, skipped, logged without time, or simply unrecorded.
        Logged without time still counts as completed logging. It should lose only a small amount of completeness credit, not be treated as missing.
        Follow the fixed section maxima exactly: sleep 45, meals 35, shower 10, bowelMovement 10.
        If a section is not enabled, set included=false, score=0, and explain that it was not included.
        Never invent habits or judge a meal pattern without timeline support.
        Be concrete about times and counts when present.
        Keep the tone warm, brief, lightly playful, and non-judgmental.
        You must return an overallScore from 0 to 100.
        You must return a score for every section.
        Do not omit score fields. Do not return null score fields.
        Return valid JSON that matches the schema exactly.
        """,
        input: payloadString,
        store: false,
        text: OpenAIResponsesRequestBody.TextConfiguration(
            format: OpenAIResponsesRequestBody.SchemaConfiguration(
                name: "daily_insight_narrative",
                schema: makeNarrativeSchema()
            )
        )
    )
}

private func makeTranslationRequestBody(
    from narrative: DailyInsightNarrative,
    targetLanguage: AppLanguage,
    model: String
) -> OpenAIResponsesRequestBody {
    let input = TranslationRequestPayload(
        sourceLanguage: narrative.sourceLanguageCode,
        targetLanguage: targetLanguage.translationDisplayName,
        headline: narrative.headline,
        summary: narrative.summary,
        bullets: narrative.bullets
    )

    return OpenAIResponsesRequestBody(
        model: model,
        instructions: """
        You are translating short lifestyle score copy for a journaling app.
        Translate the user-facing text into the requested target language only.
        Preserve meaning, tone, brevity, and bullet count.
        Do not add new information, do not remove information, and do not change the number of bullets.
        Return valid JSON that matches the schema exactly.
        """,
        input: String(
            data: (try? JSONEncoder().encode(input)) ?? Data(),
            encoding: .utf8
        ) ?? "{}",
        store: false,
        text: OpenAIResponsesRequestBody.TextConfiguration(
            format: OpenAIResponsesRequestBody.SchemaConfiguration(
                name: "daily_insight_translation",
                schema: makeLocalizedNarrativeSchema()
            )
        )
    )
}

private func generateAveragedNarrative(
    sampleCount: Int,
    generate: @escaping @Sendable () async throws -> DailyInsightNarrative
) async throws -> DailyInsightNarrative {
    var samples: [DailyInsightNarrative] = []
    samples.reserveCapacity(sampleCount)

    for _ in 0..<sampleCount {
        samples.append(try await generate())
    }

    guard let representative = representativeNarrative(from: samples) else {
        throw AIInsightServiceError.emptyResponse
    }

    let averagedOverall = Int(
        (Double(samples.compactMap(\.overallScore).reduce(0, +)) / Double(max(samples.compactMap(\.overallScore).count, 1)))
            .rounded()
    )

    let keys = Set(samples.flatMap { Array(($0.components ?? [:]).keys) })
    let averagedComponents: [String: DailyInsightNarrative.ComponentScoreOverride] = Dictionary(uniqueKeysWithValues: keys.map { key in
        let overrides = samples.compactMap { $0.components?[key] }
        let includedCount = overrides.filter { $0.included ?? true }.count
        let included = includedCount * 2 >= overrides.count
        let averagedScore = Int(
            (Double(overrides.compactMap(\.score).reduce(0, +)) / Double(max(overrides.compactMap(\.score).count, 1)))
                .rounded()
        )
        let averagedMax = Int(
            (Double(overrides.compactMap(\.maxScore).reduce(0, +)) / Double(max(overrides.compactMap(\.maxScore).count, 1)))
                .rounded()
        )
        let representativeDetail = overrides
            .compactMap(\.detail)
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })

        return (
            key,
            DailyInsightNarrative.ComponentScoreOverride(
                score: included ? averagedScore : 0,
                maxScore: max(1, averagedMax),
                detail: representativeDetail,
                included: included
            )
        )
    })

    return DailyInsightNarrative(
        headline: representative.headline,
        summary: representative.summary,
        bullets: representative.bullets,
        overallScore: averagedOverall,
        components: averagedComponents,
        generatedAt: .now,
        scoringVersion: DailyInsightNarrative.currentScoringVersion,
        sampleCount: sampleCount,
        payloadSignature: representative.payloadSignature
    )
}

private func representativeNarrative(from samples: [DailyInsightNarrative]) -> DailyInsightNarrative? {
    guard !samples.isEmpty else { return nil }
    let overallAverage = Double(samples.compactMap(\.overallScore).reduce(0, +)) / Double(max(samples.compactMap(\.overallScore).count, 1))
    return samples.min { lhs, rhs in
        abs(Double(lhs.overallScore ?? 0) - overallAverage) < abs(Double(rhs.overallScore ?? 0) - overallAverage)
    }
}

private func makeNarrativeSchema() -> JSONValue {
    .object([
        "type": .string("object"),
        "properties": .object([
            "headline": .object([
                "type": .string("string"),
                "minLength": .number(1)
            ]),
            "summary": .object([
                "type": .string("string"),
                "minLength": .number(1)
            ]),
            "bullets": .object([
                "type": .string("array"),
                "items": .object([
                    "type": .string("string"),
                    "minLength": .number(1)
                ]),
                "minItems": .number(2),
                "maxItems": .number(4)
            ]),
            "overallScore": .object([
                "type": .string("integer")
            ]),
            "components": .object([
                "type": .string("object"),
                "properties": .object([
                    "sleep": componentSchema(),
                    "meals": componentSchema(),
                    "shower": componentSchema(),
                    "bowelMovement": componentSchema()
                ]),
                "required": .array([
                    .string("sleep"),
                    .string("meals"),
                    .string("shower"),
                    .string("bowelMovement")
                ]),
                "additionalProperties": .bool(false)
            ])
        ]),
        "required": .array([
            .string("headline"),
            .string("summary"),
            .string("bullets"),
            .string("overallScore"),
            .string("components")
        ]),
        "additionalProperties": .bool(false)
    ])
}

private func makeLocalizedNarrativeSchema() -> JSONValue {
    .object([
        "type": .string("object"),
        "properties": .object([
            "headline": .object([
                "type": .string("string"),
                "minLength": .number(1)
            ]),
            "summary": .object([
                "type": .string("string"),
                "minLength": .number(1)
            ]),
            "bullets": .object([
                "type": .string("array"),
                "items": .object([
                    "type": .string("string"),
                    "minLength": .number(1)
                ]),
                "minItems": .number(1),
                "maxItems": .number(4)
            ])
        ]),
        "required": .array([
            .string("headline"),
            .string("summary"),
            .string("bullets")
        ]),
        "additionalProperties": .bool(false)
    ])
}

private func componentSchema() -> JSONValue {
    .object([
        "type": .string("object"),
        "properties": .object([
            "included": .object([
                "type": .string("boolean")
            ]),
            "score": .object([
                "type": .string("integer")
            ]),
            "maxScore": .object([
                "type": .string("integer")
            ]),
            "detail": .object([
                "type": .string("string"),
                "minLength": .number(1)
            ])
        ]),
        "required": .array([
            .string("included"),
            .string("score"),
            .string("maxScore"),
            .string("detail")
        ]),
        "additionalProperties": .bool(false)
    ])
}

private func extractJSONObject(from text: String) -> String {
    guard let start = text.firstIndex(of: "{"),
          let end = text.lastIndex(of: "}") else {
        return text
    }
    return String(text[start...end])
}

private struct OpenAIResponsesRequestBody: Encodable {
    struct TextConfiguration: Encodable {
        var format: SchemaConfiguration
    }

    struct SchemaConfiguration: Encodable {
        var type: String = "json_schema"
        var name: String
        var strict: Bool = true
        var schema: JSONValue
    }

    var model: String
    var instructions: String
    var input: String
    var store: Bool
    var text: TextConfiguration
}

private struct OpenAIResponseEnvelope: Decodable {
    struct OutputItem: Decodable {
        struct ContentItem: Decodable {
            var type: String?
            var text: String?
            var parsed: DailyInsightNarrative?
            var parsedLocalizedText: DailyInsightNarrative.LocalizedText?
            var refusal: String?

            private enum CodingKeys: String, CodingKey {
                case type
                case text
                case parsed
                case refusal
            }

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                type = try container.decodeIfPresent(String.self, forKey: .type)
                text = try container.decodeIfPresent(String.self, forKey: .text)
                parsed = try container.decodeIfPresent(DailyInsightNarrative.self, forKey: .parsed)
                parsedLocalizedText = try container.decodeIfPresent(DailyInsightNarrative.LocalizedText.self, forKey: .parsed)
                refusal = try container.decodeIfPresent(String.self, forKey: .refusal)
            }
        }

        var content: [ContentItem]?
    }

    var outputText: String?
    var outputParsed: DailyInsightNarrative?
    var output: [OutputItem]?
    var refusal: String?

    enum CodingKeys: String, CodingKey {
        case outputText = "output_text"
        case outputParsed = "output_parsed"
        case output
        case refusal
    }

    var extractedNarrative: DailyInsightNarrative? {
        if let outputParsed, outputParsed.hasAIScoring {
            return outputParsed
        }

        return output?
            .flatMap { $0.content ?? [] }
            .compactMap(\.parsed)
            .first(where: \.hasAIScoring)
    }

    var extractedText: String? {
        if let outputText, !outputText.isEmpty {
            return outputText
        }
        let joined = output?
            .flatMap { $0.content ?? [] }
            .compactMap(\.text)
            .joined(separator: "\n")
        return joined?.isEmpty == true ? nil : joined
    }

    var extractedRefusal: String? {
        if let refusal, !refusal.isEmpty {
            return refusal
        }
        let joined = output?
            .flatMap { $0.content ?? [] }
            .compactMap(\.refusal)
            .joined(separator: "\n")
        return joined?.isEmpty == true ? nil : joined
    }
}

private struct AIErrorEnvelope: Decodable {
    struct ProviderError: Decodable {
        var message: String?
        var type: String?
        var code: String?
    }

    enum ErrorValue: Decodable {
        case string(String)
        case provider(ProviderError)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(String.self) {
                self = .string(value)
                return
            }
            self = .provider(try container.decode(ProviderError.self))
        }
    }

    var errorValue: ErrorValue?
    var limit: Int?
    var dateKey: String?

    enum CodingKeys: String, CodingKey {
        case errorValue = "error"
        case limit
        case dateKey
    }
}

private enum JSONValue: Encodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])

    func encode(to encoder: Encoder) throws {
        switch self {
        case .string(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .number(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .bool(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .array(let values):
            var container = encoder.unkeyedContainer()
            for value in values {
                try container.encode(value)
            }
        case .object(let dictionary):
            var container = encoder.container(keyedBy: DynamicCodingKey.self)
            for (key, value) in dictionary {
                try container.encode(value, forKey: DynamicCodingKey(stringValue: key))
            }
        }
    }
}

private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }

    init(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        return nil
    }
}

extension DailyInsightPayload {
    func stableSignature() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(signatureSeed)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private var signatureSeed: SignatureSeed {
        SignatureSeed(
            analysisDate: analysisDate,
            appTimeZoneIdentifier: appTimeZoneIdentifier,
            sleep: SignatureSeed.Sleep(
                source: sleep.source,
                bedtimeISO8601: sleep.bedtimeISO8601,
                wakeISO8601: sleep.wakeISO8601,
                targetBedtime: sleep.targetBedtime,
                durationHours: sleep.durationHours,
                hasStageData: sleep.hasStageData,
                timeZoneIdentifier: sleep.timeZoneIdentifier,
                note: sleep.note
            ),
            meals: meals.enumerated().map { index, meal in
                SignatureSeed.Meal(
                    index: index,
                    status: meal.status,
                    timeISO8601: meal.timeISO8601,
                    hasPhoto: meal.hasPhoto,
                    note: meal.note
                )
            },
            showerEnabled: showerEnabled,
            showers: showers.map {
                SignatureSeed.Event(
                    status: $0.status,
                    timeISO8601: $0.timeISO8601,
                    note: $0.note
                )
            },
            bowelMovementEnabled: bowelMovementEnabled,
            bowelMovements: bowelMovements.map {
                SignatureSeed.Event(
                    status: $0.status,
                    timeISO8601: $0.timeISO8601,
                    note: $0.note
                )
            },
            comparisonContext: SignatureSeed.HistoryContext(
                trailing7Days: SignatureSeed.HistoryWindowSummary(from: comparisonContext.trailing7Days),
                trailing30Days: SignatureSeed.HistoryWindowSummary(from: comparisonContext.trailing30Days)
            ),
            scoringRubric: SignatureSeed.ScoringRubric(
                sampleCount: scoringRubric.sampleCount,
                sections: scoringRubric.sections.map {
                    SignatureSeed.RubricSection(key: $0.key, maxScore: $0.maxScore)
                }
            )
        )
    }

    private struct SignatureSeed: Encodable {
        struct Sleep: Encodable {
            var source: String
            var bedtimeISO8601: String?
            var wakeISO8601: String?
            var targetBedtime: String?
            var durationHours: Double?
            var hasStageData: Bool
            var timeZoneIdentifier: String?
            var note: String?
        }

        struct Meal: Encodable {
            var index: Int
            var status: String
            var timeISO8601: String?
            var hasPhoto: Bool
            var note: String?
        }

        struct Event: Encodable {
            var status: String?
            var timeISO8601: String?
            var note: String?
        }

        struct StatisticSummary: Encodable {
            var average: Double?
            var standardDeviation: Double?
        }

        struct HistoryWindowSummary: Encodable {
            var windowDays: Int
            var recordedDays: Int
            var sleepDurationHours: StatisticSummary
            var mealCompletionRate: StatisticSummary
            var timedMealLoggingRate: StatisticSummary
            var showerCount: StatisticSummary
            var bowelMovementCount: StatisticSummary
            var bedtimeDeviationMinutes: StatisticSummary

            init(from source: DailyInsightPayload.HistoryWindowSummary) {
                windowDays = source.windowDays
                recordedDays = source.recordedDays
                sleepDurationHours = StatisticSummary(
                    average: source.sleepDurationHours.average,
                    standardDeviation: source.sleepDurationHours.standardDeviation
                )
                mealCompletionRate = StatisticSummary(
                    average: source.mealCompletionRate.average,
                    standardDeviation: source.mealCompletionRate.standardDeviation
                )
                timedMealLoggingRate = StatisticSummary(
                    average: source.timedMealLoggingRate.average,
                    standardDeviation: source.timedMealLoggingRate.standardDeviation
                )
                showerCount = StatisticSummary(
                    average: source.showerCount.average,
                    standardDeviation: source.showerCount.standardDeviation
                )
                bowelMovementCount = StatisticSummary(
                    average: source.bowelMovementCount.average,
                    standardDeviation: source.bowelMovementCount.standardDeviation
                )
                bedtimeDeviationMinutes = StatisticSummary(
                    average: source.bedtimeDeviationMinutes.average,
                    standardDeviation: source.bedtimeDeviationMinutes.standardDeviation
                )
            }
        }

        struct HistoryContext: Encodable {
            var trailing7Days: HistoryWindowSummary
            var trailing30Days: HistoryWindowSummary
        }

        struct RubricSection: Encodable {
            var key: String
            var maxScore: Int
        }

        struct ScoringRubric: Encodable {
            var sampleCount: Int
            var sections: [RubricSection]
        }

        var analysisDate: String
        var appTimeZoneIdentifier: String
        var sleep: Sleep
        var meals: [Meal]
        var showerEnabled: Bool
        var showers: [Event]
        var bowelMovementEnabled: Bool
        var bowelMovements: [Event]
        var comparisonContext: HistoryContext
        var scoringRubric: ScoringRubric
    }
}

extension AppLanguage {
    var displayNameForPrompt: String {
        switch self {
        case .system:
            Locale.autoupdatingCurrent.localizedString(forIdentifier: Locale.autoupdatingCurrent.identifier) ?? "System language"
        case .zhHans:
            "Simplified Chinese"
        case .en:
            "English"
        }
    }

    var translationDisplayName: String {
        switch self {
        case .system:
            Locale.autoupdatingCurrent.identifier.hasPrefix("zh") ? "Simplified Chinese" : "English"
        case .zhHans:
            "Simplified Chinese"
        case .en:
            "English"
        }
    }

    func aiNarrativeLanguageCode(locale: Locale = .autoupdatingCurrent) -> String {
        switch self {
        case .system:
            locale.identifier.hasPrefix("zh") ? "zh-Hans" : "en"
        case .zhHans:
            "zh-Hans"
        case .en:
            "en"
        }
    }
}

private struct TranslationRequestPayload: Encodable {
    var sourceLanguage: String
    var targetLanguage: String
    var headline: String
    var summary: String
    var bullets: [String]
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

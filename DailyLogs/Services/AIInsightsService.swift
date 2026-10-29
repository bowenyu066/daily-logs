import Foundation
import CryptoKit
@preconcurrency import FirebaseAuth
import Security
import UIKit

enum DailyInsightComponentKind: String, CaseIterable, Identifiable {
    case sleep
    case meals
    case shower
    case bowelMovement

    var id: String { rawValue }

    /// Shower and bowel movement are minor sections the rule scores on its own: the AI only adjusts
    /// sleep and meals.
    var acceptsAIAdjustment: Bool {
        self == .sleep || self == .meals
    }

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
    /// The rule score before the AI adjusted it; nil when the AI did not score this section.
    var ruleScore: Int? = nil
    var aiReason: String? = nil

    var id: String { kind.rawValue }

    var aiDelta: Int? {
        ruleScore.map { score - $0 }
    }

    /// How far the AI may move a section away from its rule score.
    static func maxAIAdjustment(for kind: DailyInsightComponentKind, maxScore: Int) -> Int {
        guard kind.acceptsAIAdjustment else { return 0 }
        return max(1, Int((Double(maxScore) * 0.2).rounded()))
    }

    var scoreRatio: Double {
        guard isIncluded, maxScore > 0 else { return 0 }
        return Double(score) / Double(maxScore)
    }
}

struct DailyInsightNarrative: Codable, Equatable {
    /// Version 6: the app's rubric scores each section and the model adjusts every included section
    /// within a bounded range, giving a reason, alongside findings, a suggestion and a follow-up.
    static let currentScoringVersion = 6

    struct ComponentScoreOverride: Codable, Equatable {
        var score: Int?
        var maxScore: Int?
        var detail: String?
        var included: Bool?
    }

    struct Finding: Codable, Equatable {
        var title: String
        var evidence: String
    }

    struct ScoreAdjustment: Codable, Equatable {
        var delta: Int
        var reason: String
    }

    struct LocalizedText: Codable, Equatable {
        var headline: String
        var summary: String
        var bullets: [String]
        var findings: [Finding]?
        var suggestion: String?
        var followUp: String?
        var scoreReasons: [String: String]?
    }

    var headline: String
    var summary: String
    var bullets: [String]
    var findings: [Finding]?
    var suggestion: String?
    var followUp: String?
    var scoreAdjustments: [String: ScoreAdjustment]?
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
        case findings
        case suggestion
        case followUp
        case scoreAdjustments
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
        findings: [Finding]? = nil,
        suggestion: String? = nil,
        followUp: String? = nil,
        scoreAdjustments: [String: ScoreAdjustment]? = nil,
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
        self.findings = findings
        self.suggestion = suggestion
        self.followUp = followUp
        self.scoreAdjustments = scoreAdjustments
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
        findings = try container.decodeIfPresent([Finding].self, forKey: .findings)
        suggestion = try container.decodeIfPresent(String.self, forKey: .suggestion)
        followUp = try container.decodeIfPresent(String.self, forKey: .followUp)
        scoreAdjustments = try container.decodeIfPresent([String: ScoreAdjustment].self, forKey: .scoreAdjustments)
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
        overallScore != nil || !(components ?? [:]).isEmpty || !(scoreAdjustments ?? [:]).isEmpty
    }

    /// True for narratives the app can show: current ones carry findings, older ones carried scores.
    var hasAIContent: Bool {
        hasAIScoring || !(findings ?? []).isEmpty
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
        if let findings = localized.findings {
            copy.findings = findings
        }
        if let suggestion = localized.suggestion {
            copy.suggestion = suggestion
        }
        if let followUp = localized.followUp {
            copy.followUp = followUp
        }
        if let reasons = localized.scoreReasons, var adjustments = copy.scoreAdjustments {
            for (key, reason) in reasons where adjustments[key] != nil {
                adjustments[key]?.reason = reason
            }
            copy.scoreAdjustments = adjustments
        }
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
    /// The app's rule-based total when the AI adjusted the section scores.
    var ruleScore: Int? = nil

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

        let adjustments = narrative.scoreAdjustments ?? [:]
        let adjustedComponents = overriddenComponents.map { component in
            guard component.isIncluded, let adjustment = adjustments[component.kind.rawValue] else {
                return component
            }
            let bound = DailyInsightComponent.maxAIAdjustment(for: component.kind, maxScore: component.maxScore)
            guard bound > 0 else { return component }
            let delta = max(-bound, min(adjustment.delta, bound))
            var updated = component
            updated.ruleScore = component.score
            updated.score = max(0, min(component.score + delta, component.maxScore))
            let reason = adjustment.reason.trimmingCharacters(in: .whitespacesAndNewlines)
            updated.aiReason = reason.isEmpty ? nil : reason
            return updated
        }
        let isAdjusted = adjustedComponents.contains { $0.ruleScore != nil }

        let included = adjustedComponents.filter(\.isIncluded)
        let fallbackOverall: Int = {
            if isAdjusted {
                // Same formula as the rule score, so an adjustment of zero keeps the total unchanged.
                let totalMax = max(included.reduce(0) { $0 + $1.maxScore }, 1)
                return Int((Double(included.reduce(0) { $0 + $1.score }) / Double(totalMax) * 100).rounded())
            }
            // Without score overrides the app's own overall score stands.
            guard narrative.components?.isEmpty == false else { return overallScore }
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
            components: adjustedComponents,
            highlights: bullets.isEmpty ? highlights : bullets,
            ruleScore: isAdjusted ? overallScore : nil
        )
    }
}

struct DailyInsightPayload: Codable {
    struct StatisticSummary: Codable {
        var average: Double?
        var standardDeviation: Double?
    }

    struct TrendSummary: Codable {
        var currentAverage: Double?
        var previousAverage: Double?
        var changeFromPreviousAverage: Double?
        var direction: String
        var volatility: String
        var observedDays: Int
        var comparisonDays: Int
    }

    struct TargetDaySummary: Codable {
        var sleepDurationHours: Double?
        var trackedMealCount: Int
        var loggedMealCount: Int
        var skippedMealCount: Int
        var unrecordedMealCount: Int
        var timedLoggedMealCount: Int
        var showerCount: Int
        var hasShowerRecord: Bool
        var bowelMovementCount: Int
        var hasBowelMovementRecord: Bool
        var timelineEventCount: Int
        var authoritativeNote: String
    }

    struct HistoryDaySnapshot: Codable {
        var date: String
        var weekday: String
        var sleepDurationHours: Double?
        var bedtimeLocal: String?
        var wakeLocal: String?
        var mealCompletionRate: Double
        var timedMealLoggingRate: Double
        var firstMealLocal: String?
        var lastMealLocal: String?
        var showerCount: Int?
        var bowelMovementCount: Int?
        var bedtimeDeviationMinutes: Double?
        var notes: String?
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
        var sleepDurationTrend: TrendSummary
        var mealCompletionTrend: TrendSummary
        var timedMealLoggingTrend: TrendSummary
        var showerCountTrend: TrendSummary
        var bowelMovementCountTrend: TrendSummary
        var bedtimeDeviationTrend: TrendSummary
        var note: String?
    }

    struct HistoryContext: Codable {
        var trailing7Days: HistoryWindowSummary
        var trailing30Days: HistoryWindowSummary
        var dailySnapshots: [HistoryDaySnapshot]
    }

    struct SleepStageMinutes: Codable {
        var deep: Int
        var rem: Int
        var light: Int
        var awake: Int
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
        var stageMinutes: SleepStageMinutes?
        var timeZoneIdentifier: String?
        var note: String?
    }

    struct MealSection: Codable {
        var title: String
        var status: String
        var timeISO8601: String?
        var timeLocal: String?
        var hasPhoto: Bool
        var photoCount: Int
        var locationName: String?
        var note: String?
    }

    struct DayContext: Codable {
        var weekday: String
        var locationName: String?
        var weather: String?
        var lowTemperatureCelsius: Double?
        var highTemperatureCelsius: Double?
        var travelPhase: String?
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

    /// Scores the app computed with its fixed rules. The model treats them as given.
    struct AppScores: Codable {
        struct Section: Codable {
            var key: String
            var title: String
            var included: Bool
            var score: Int
            var maxScore: Int
            var maxAdjustment: Int
            var detail: String
        }

        var total: Int
        var method: String
        var sections: [Section]
    }

    var language: String
    var analysisDate: String
    var analysisDateTitle: String
    var appTimeZoneIdentifier: String
    var funOnlyDisclaimer: String
    var targetDay: TargetDaySummary
    var sleep: SleepSection
    var meals: [MealSection]
    var showerEnabled: Bool
    var showers: [EventSection]
    var bowelMovementEnabled: Bool
    var bowelMovements: [EventSection]
    var timeline: [TimelineEntry]
    var dayContext: DayContext
    var appScores: AppScores
    var comparisonContext: HistoryContext
}

enum DailyInsightAnalyzer {
    static func hasMeaningfulLogData(in record: DailyRecord) -> Bool {
        let hasSleepNote = record.sleepRecord.note?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false
        let hasMealData = record.meals.contains { meal in
            meal.status != .empty
                || meal.time != nil
                || meal.hasPhoto
                || meal.note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                || meal.locationName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                || meal.latitude != nil
                || meal.longitude != nil
        }

        return record.sleepRecord.hasSleepData
            || hasSleepNote
            || hasMealData
            || !record.showers.isEmpty
            || !record.bowelMovements.isEmpty
            || !record.sexualActivities.isEmpty
            || record.dailyVideo != nil
    }

    /// `history` is used to find the usual shower and bowel movement times; only the 30 days
    /// before the record's day count.
    static func buildReport(
        for record: DailyRecord,
        preferences: UserPreferences,
        locale: Locale,
        history: [DailyRecord] = []
    ) -> DailyInsightReport {
        let day = record.date.startOfDay
        let windowStart = day.adding(days: -30)
        let recentHistory = history.filter {
            let historyDay = $0.date.startOfDay
            return historyDay >= windowStart && historyDay < day
        }
        let sleepResult = sleepComponent(for: record, preferences: preferences)
        let mealResult = mealComponent(for: record)
        let showerEnabled = preferences.visibleHomeSections.contains(.showers)
        let bowelEnabled = preferences.visibleHomeSections.contains(.bowelMovements)
        let showerResult = hygieneComponent(
            kind: .shower,
            enabled: showerEnabled,
            entryMinutes: record.showers.map { clockMinutes($0.time, timeZoneIdentifier: $0.timeZoneIdentifier) },
            historyMinutes: recentHistory.flatMap(\.showers).compactMap { clockMinutes($0.time, timeZoneIdentifier: $0.timeZoneIdentifier) }
        )
        let bowelResult = hygieneComponent(
            kind: .bowelMovement,
            enabled: bowelEnabled,
            entryMinutes: record.bowelMovements.map { clockMinutes($0.time, timeZoneIdentifier: $0.timeZoneIdentifier) },
            historyMinutes: recentHistory.flatMap(\.bowelMovements).compactMap { clockMinutes($0.time, timeZoneIdentifier: $0.timeZoneIdentifier) }
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
                photoCount: entry.photoURLs.count,
                locationName: trimmedOptional(entry.locationName),
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
        let targetDay = targetDaySummary(for: record, timeline: timeline)

        return DailyInsightPayload(
            language: language.displayNameForPrompt,
            analysisDate: record.date.storageKey(),
            analysisDateTitle: record.date.formattedDayTitle(locale: locale),
            appTimeZoneIdentifier: TimeZone.autoupdatingCurrent.identifier,
            funOnlyDisclaimer: NSLocalizedString("这是趣味性 AI 分析，不是医疗或健康建议。", comment: ""),
            targetDay: targetDay,
            sleep: DailyInsightPayload.SleepSection(
                source: record.sleepRecord.source.rawValue,
                bedtimeISO8601: record.sleepRecord.bedtimePreviousNight?.displayISO8601,
                bedtimeLocal: record.sleepRecord.bedtimePreviousNight?.displayClockTime(in: sleepTimeZone),
                wakeISO8601: record.sleepRecord.wakeTimeCurrentDay?.displayISO8601,
                wakeLocal: record.sleepRecord.wakeTimeCurrentDay?.displayClockTime(in: sleepTimeZone),
                targetBedtime: record.sleepRecord.targetBedtime?.canonicalDisplayTime,
                durationHours: record.sleepRecord.duration.map { ($0 / 3600 * 10).rounded() / 10 },
                hasStageData: record.sleepRecord.hasStageData,
                stageMinutes: stageMinutes(for: record.sleepRecord),
                timeZoneIdentifier: record.sleepRecord.timeZoneIdentifier,
                note: trimmedOptional(record.sleepRecord.note)
            ),
            meals: meals,
            showerEnabled: preferences.visibleHomeSections.contains(.showers),
            showers: showers,
            bowelMovementEnabled: preferences.visibleHomeSections.contains(.bowelMovements),
            bowelMovements: bowelMovements,
            timeline: timeline,
            dayContext: dayContext(for: record),
            appScores: appScores(
                from: buildReport(for: record, preferences: preferences, locale: locale, history: history)
            ),
            comparisonContext: historyContext(
                for: record,
                preferences: preferences,
                history: history
            )
        )
    }

    private static func targetDaySummary(
        for record: DailyRecord,
        timeline: [DailyInsightPayload.TimelineEntry]
    ) -> DailyInsightPayload.TargetDaySummary {
        let mealStatuses = record.meals.map { mealStatusName($0, recordDate: record.date) }
        let loggedCount = mealStatuses.filter { $0.hasPrefix("logged") }.count
        let skippedCount = mealStatuses.filter { $0 == "skipped" }.count
        let unrecordedCount = mealStatuses.filter { $0 == "unrecorded" }.count
        let timedLoggedCount = record.meals.filter {
            mealStatusName($0, recordDate: record.date).hasPrefix("logged") && $0.time != nil
        }.count

        return DailyInsightPayload.TargetDaySummary(
            sleepDurationHours: record.sleepRecord.duration.map { rounded($0 / 3600, places: 1) },
            trackedMealCount: record.meals.count,
            loggedMealCount: loggedCount,
            skippedMealCount: skippedCount,
            unrecordedMealCount: unrecordedCount,
            timedLoggedMealCount: timedLoggedCount,
            showerCount: record.showers.count,
            hasShowerRecord: !record.showers.isEmpty,
            bowelMovementCount: record.bowelMovements.count,
            hasBowelMovementRecord: !record.bowelMovements.isEmpty,
            timelineEventCount: timeline.count,
            authoritativeNote: NSLocalizedString("这些是目标当天的权威计数；历史窗口只用于趋势对比，不能当作当天记录。", comment: "")
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
            ),
            dailySnapshots: historyDaySnapshots(
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

    private static func appScores(from report: DailyInsightReport) -> DailyInsightPayload.AppScores {
        DailyInsightPayload.AppScores(
            total: report.overallScore,
            method: "Fixed rules: sleep 45, meals 35, shower 10, bowel movement 10; sections that are not enabled are excluded and the total is scaled to 0-100. Shower and bowel movement are minor: logged at roughly the user's usual time earns full marks, and the number of entries does not matter.",
            sections: report.components.map {
                DailyInsightPayload.AppScores.Section(
                    key: $0.kind.rawValue,
                    title: $0.kind.title,
                    included: $0.isIncluded,
                    score: $0.score,
                    maxScore: $0.maxScore,
                    maxAdjustment: $0.isIncluded ? DailyInsightComponent.maxAIAdjustment(for: $0.kind, maxScore: $0.maxScore) : 0,
                    detail: $0.detail
                )
            }
        )
    }

    private static func dayContext(for record: DailyRecord) -> DailyInsightPayload.DayContext {
        let travelPhase = (
            record.meals.compactMap(\.travelContext)
                + record.showers.compactMap(\.travelContext)
                + record.bowelMovements.compactMap(\.travelContext)
        ).first?.phase.rawValue

        return DailyInsightPayload.DayContext(
            weekday: weekdayName(for: record.date),
            locationName: trimmedOptional(record.locationName),
            weather: trimmedOptional(record.weatherSnapshot?.conditionDescription),
            lowTemperatureCelsius: record.weatherSnapshot.map { rounded($0.lowTemperatureCelsius, places: 1) },
            highTemperatureCelsius: record.weatherSnapshot.map { rounded($0.highTemperatureCelsius, places: 1) },
            travelPhase: travelPhase
        )
    }

    private static func stageMinutes(for sleep: SleepRecord) -> DailyInsightPayload.SleepStageMinutes? {
        guard sleep.hasStageData else { return nil }
        let durations = sleep.stageDurations
        func minutes(_ stage: SleepStage) -> Int {
            Int(((durations[stage] ?? 0) / 60).rounded())
        }
        return DailyInsightPayload.SleepStageMinutes(
            deep: minutes(.deep),
            rem: minutes(.rem),
            light: minutes(.light),
            awake: minutes(.awake)
        )
    }

    private static func weekdayName(for date: Date) -> String {
        let names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        return names[(Calendar.current.component(.weekday, from: date) - 1) % 7]
    }

    private static func dayNotes(for record: DailyRecord) -> String? {
        let notes = ([record.sleepRecord.note] + record.meals.map(\.note) + record.showers.map(\.note) + record.bowelMovements.map(\.note))
            .compactMap(trimmedOptional)
        guard !notes.isEmpty else { return nil }
        let joined = notes.joined(separator: " / ")
        return joined.count > 120 ? String(joined.prefix(120)) + "…" : joined
    }

    private static func loggedMealClockTimes(for record: DailyRecord) -> (first: String?, last: String?) {
        let timedMeals = record.meals
            .filter { mealStatusName($0, recordDate: record.date) == "logged_with_time" }
            .compactMap { meal in meal.time.map { (time: $0, timeZoneIdentifier: meal.timeZoneIdentifier) } }
            .sorted { $0.time < $1.time }
        return (
            timedMeals.first.flatMap { localizedClockTime($0.time, timeZoneIdentifier: $0.timeZoneIdentifier) },
            timedMeals.last.flatMap { localizedClockTime($0.time, timeZoneIdentifier: $0.timeZoneIdentifier) }
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
        let previousStartDate = startDate.adding(days: -lookbackDays)
        let windowRecords = history
            .filter {
                let day = $0.date.startOfDay
                return day >= startDate && day < endDate
            }
            .sorted { $0.date < $1.date }
        let previousWindowRecords = history
            .filter {
                let day = $0.date.startOfDay
                return day >= previousStartDate && day < startDate
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
        let previousSleepHours = previousWindowRecords.compactMap { $0.sleepRecord.duration.map { ($0 / 3600 * 10).rounded() / 10 } }
        let previousMealCompletionRates = previousWindowRecords.map(mealCompletionRate(for:))
        let previousTimedMealLoggingRates = previousWindowRecords.map(timedMealLoggingRate(for:))
        let previousShowerCounts = preferences.visibleHomeSections.contains(.showers)
            ? previousWindowRecords.map { Double($0.showers.count) }
            : []
        let previousBowelMovementCounts = preferences.visibleHomeSections.contains(.bowelMovements)
            ? previousWindowRecords.map { Double($0.bowelMovements.count) }
            : []
        let previousBedtimeDeviationValues = previousWindowRecords.compactMap {
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
            sleepDurationTrend: trendSummary(for: sleepHours, previousValues: previousSleepHours),
            mealCompletionTrend: trendSummary(for: mealCompletionRates, previousValues: previousMealCompletionRates),
            timedMealLoggingTrend: trendSummary(for: timedMealLoggingRates, previousValues: previousTimedMealLoggingRates),
            showerCountTrend: trendSummary(for: showerCounts, previousValues: previousShowerCounts),
            bowelMovementCountTrend: trendSummary(for: bowelMovementCounts, previousValues: previousBowelMovementCounts),
            bedtimeDeviationTrend: trendSummary(for: bedtimeDeviationValues, previousValues: previousBedtimeDeviationValues),
            note: note
        )
    }

    private static func historyDaySnapshots(
        for record: DailyRecord,
        lookbackDays: Int,
        preferences: UserPreferences,
        history: [DailyRecord]
    ) -> [DailyInsightPayload.HistoryDaySnapshot] {
        let endDate = record.date.startOfDay
        let startDate = endDate.adding(days: -lookbackDays)
        let showerEnabled = preferences.visibleHomeSections.contains(.showers)
        let bowelEnabled = preferences.visibleHomeSections.contains(.bowelMovements)

        return history
            .filter {
                let day = $0.date.startOfDay
                return day >= startDate && day < endDate
            }
            .sorted { $0.date < $1.date }
            .map { historicalRecord in
                let sleep = historicalRecord.sleepRecord
                let sleepTimeZoneIdentifier = sleep.timeZoneIdentifier
                let mealTimes = loggedMealClockTimes(for: historicalRecord)
                return DailyInsightPayload.HistoryDaySnapshot(
                    date: historicalRecord.date.storageKey(),
                    weekday: weekdayName(for: historicalRecord.date),
                    sleepDurationHours: sleep.duration.map { rounded($0 / 3600, places: 1) },
                    bedtimeLocal: localizedClockTime(sleep.bedtimePreviousNight, timeZoneIdentifier: sleepTimeZoneIdentifier),
                    wakeLocal: localizedClockTime(sleep.wakeTimeCurrentDay, timeZoneIdentifier: sleepTimeZoneIdentifier),
                    mealCompletionRate: mealCompletionRate(for: historicalRecord),
                    timedMealLoggingRate: timedMealLoggingRate(for: historicalRecord),
                    firstMealLocal: mealTimes.first,
                    lastMealLocal: mealTimes.last,
                    showerCount: showerEnabled ? historicalRecord.showers.count : nil,
                    bowelMovementCount: bowelEnabled ? historicalRecord.bowelMovements.count : nil,
                    bedtimeDeviationMinutes: bedtimeDeviationMinutes(for: sleep),
                    notes: dayNotes(for: historicalRecord)
                )
            }
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
                [NSLocalizedString("这一天还没有睡眠记录，所以这部分暂时没有加分。", comment: "")]
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
            highlights.append(NSLocalizedString("睡眠时长偏短，是当天最明显的扣分点。", comment: ""))
        } else if durationHours > 9.5 {
            highlights.append(NSLocalizedString("睡眠时间偏长，可能说明当天整体恢复感比较重。", comment: ""))
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
                [NSLocalizedString("当天没有可分析的餐食数据。", comment: "")]
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
            highlights.append(NSLocalizedString("当天的餐食记录比较完整，这一项整体是加分的。", comment: ""))
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

    /// Logging one at a time of day the user has used before earns full marks; how many there were
    /// does not matter. Without enough history to tell what is usual, any entry earns full marks.
    private static func hygieneComponent(
        kind: DailyInsightComponentKind,
        enabled: Bool,
        entryMinutes: [Int?],
        historyMinutes: [Int]
    ) -> (component: DailyInsightComponent, highlights: [String]) {
        let maxScore = 10
        guard enabled else {
            return (
                DailyInsightComponent(
                    kind: kind,
                    score: 0,
                    maxScore: maxScore,
                    detail: NSLocalizedString("未纳入当天的分析范围", comment: ""),
                    isIncluded: false
                ),
                []
            )
        }

        let count = entryMinutes.count
        if count == 0 {
            return (
                DailyInsightComponent(
                    kind: kind,
                    score: 4,
                    maxScore: maxScore,
                    detail: NSLocalizedString("当天没有相关记录", comment: ""),
                    isIncluded: true
                ),
                [String(format: NSLocalizedString("%@这部分当天没有记录，所以分数偏保守。", comment: ""), kind.title)]
            )
        }

        let timedEntries = entryMinutes.compactMap { $0 }
        if historyMinutes.count >= 3, !timedEntries.isEmpty {
            // Usual means at least two entries in the window were within the tolerance of it.
            let isAtUsualTime = timedEntries.contains { entry in
                historyMinutes.filter { clockDistance($0, entry) <= usualTimeToleranceMinutes }.count >= 2
            }
            if !isAtUsualTime {
                return (
                    DailyInsightComponent(
                        kind: kind,
                        score: 8,
                        maxScore: maxScore,
                        detail: String(format: NSLocalizedString("记录了 %d 次，时间和平时不太一样", comment: ""), count),
                        isIncluded: true
                    ),
                    [String(format: NSLocalizedString("%@的时间和平时不太一样，这部分小扣了一点。", comment: ""), kind.title)]
                )
            }
            return (
                DailyInsightComponent(
                    kind: kind,
                    score: maxScore,
                    maxScore: maxScore,
                    detail: String(format: NSLocalizedString("记录了 %d 次，时间和平时差不多", comment: ""), count),
                    isIncluded: true
                ),
                [String(format: NSLocalizedString("%@有明确记录，这部分拿到了稳定加分。", comment: ""), kind.title)]
            )
        }

        return (
            DailyInsightComponent(
                kind: kind,
                score: maxScore,
                maxScore: maxScore,
                detail: String(format: NSLocalizedString("记录了 %d 次", comment: ""), count),
                isIncluded: true
            ),
            [String(format: NSLocalizedString("%@有明确记录，这部分拿到了稳定加分。", comment: ""), kind.title)]
        )
    }

    private static let usualTimeToleranceMinutes = 150

    private static func clockMinutes(_ date: Date?, timeZoneIdentifier: String?) -> Int? {
        guard let date else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier ?? "") ?? .autoupdatingCurrent
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private static func clockDistance(_ lhs: Int, _ rhs: Int) -> Int {
        let difference = abs(lhs - rhs) % 1440
        return min(difference, 1440 - difference)
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

    private static func trendSummary(
        for currentValues: [Double],
        previousValues: [Double]
    ) -> DailyInsightPayload.TrendSummary {
        let current = statisticSummary(for: currentValues)
        let previous = statisticSummary(for: previousValues)
        let change: Double? = {
            guard let currentAverage = current.average,
                  let previousAverage = previous.average else {
                return nil
            }
            return rounded(currentAverage - previousAverage, places: 2)
        }()

        return DailyInsightPayload.TrendSummary(
            currentAverage: current.average,
            previousAverage: previous.average,
            changeFromPreviousAverage: change,
            direction: trendDirection(change: change, previousAverage: previous.average),
            volatility: volatilityLevel(standardDeviation: current.standardDeviation, average: current.average),
            observedDays: currentValues.count,
            comparisonDays: previousValues.count
        )
    }

    private static func trendDirection(change: Double?, previousAverage: Double?) -> String {
        guard let change else { return "unknown" }
        let threshold = max(0.05, abs(previousAverage ?? 0) * 0.05)
        if abs(change) <= threshold {
            return "flat"
        }
        return change > 0 ? "up" : "down"
    }

    private static func volatilityLevel(standardDeviation: Double?, average: Double?) -> String {
        guard let standardDeviation else { return "unknown" }
        let denominator = max(abs(average ?? 0), 1)
        let coefficient = standardDeviation / denominator
        switch coefficient {
        case ..<0.15:
            return "low"
        case ..<0.35:
            return "medium"
        default:
            return "high"
        }
    }

    private static func rounded(_ value: Double, places: Int) -> Double {
        let multiplier = pow(10.0, Double(places))
        return (value * multiplier).rounded() / multiplier
    }

    private static func normalizedBedtimeMinutes(hour: Int, minute: Int) -> Int {
        let minutes = hour * 60 + minute
        return minutes >= 12 * 60 ? minutes - 24 * 60 : minutes
    }

    private static func headline(for score: Int) -> String {
        switch score {
        case 85...:
            return NSLocalizedString("这一天状态很稳", comment: "")
        case 70...84:
            return NSLocalizedString("这一天整体不错", comment: "")
        case 55...69:
            return NSLocalizedString("这一天有点乱", comment: "")
        default:
            return NSLocalizedString("这一天需要重整节奏", comment: "")
        }
    }

    private static func summary(for score: Int, components: [DailyInsightComponent]) -> String {
        let sorted = components.sorted { $0.scoreRatio > $1.scoreRatio }
        guard let best = sorted.first, let weakest = sorted.last else {
            return NSLocalizedString("现在的数据还不足以形成稳定分析。", comment: "")
        }

        if best.kind == weakest.kind {
            return String(
                format: NSLocalizedString("%@是当天最主要的参考项，目前整体分数在 %d 分。", comment: ""),
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
            return NSLocalizedString("这一天的整体节奏比较顺，可以继续保持。", comment: "")
        case 60...79:
            return NSLocalizedString("这一天整体还可以，但还有一两项记录不够稳。", comment: "")
        default:
            return NSLocalizedString("这一天的数据提示节奏有些散，之后可以再收一收。", comment: "")
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

/// Inputs for one insight request that stay out of the payload signature: they are gathered when
/// the request is made (photos, Health data) or legitimately change from day to day (memory).
struct DailyInsightContext: Sendable {
    struct Photo: Sendable {
        var mealTitle: String
        var timeLocal: String?
        var jpegData: Data
    }

    var goals: String?
    var memory: [String] = []
    var memoryLanguage = "Simplified Chinese"
    var previousSuggestion: String?
    var health: DailyHealthSummary?
    var photos: [Photo] = []

    static let empty = DailyInsightContext()
}

struct DailyHealthSummary: Codable, Equatable, Sendable {
    var steps: Int?
    var activeEnergyKilocalories: Int?
    var exerciseMinutes: Int?
    var restingHeartRate: Int?
    var heartRateVariabilityMilliseconds: Int?

    var isEmpty: Bool {
        steps == nil
            && activeEnergyKilocalories == nil
            && exerciseMinutes == nil
            && restingHeartRate == nil
            && heartRateVariabilityMilliseconds == nil
    }
}

struct DailyInsightGeneration: Sendable {
    var narrative: DailyInsightNarrative
    /// The model's updated observations about the user, or nil when the service returned none.
    var memory: [String]?
}

protocol AIInsightNarrativeGenerating: Sendable {
    var isConfigured: Bool { get }
    func generateNarrative(from payload: DailyInsightPayload) async throws -> DailyInsightNarrative
    func generateInsight(from payload: DailyInsightPayload, context: DailyInsightContext) async throws -> DailyInsightGeneration
    func translateNarrative(_ narrative: DailyInsightNarrative, to language: AppLanguage) async throws -> DailyInsightNarrative.LocalizedText
}

extension AIInsightNarrativeGenerating {
    func generateInsight(from payload: DailyInsightPayload, context: DailyInsightContext) async throws -> DailyInsightGeneration {
        DailyInsightGeneration(narrative: try await generateNarrative(from: payload), memory: nil)
    }
}

/// Loads a day's meal photos, downscaled, so the model can see what was eaten.
enum DailyInsightPhotoLoader {
    static func photos(
        for record: DailyRecord,
        limit: Int = 6,
        perMeal: Int = 2,
        maxPixelSide: CGFloat = 768
    ) async -> [DailyInsightContext.Photo] {
        var photos: [DailyInsightContext.Photo] = []
        for meal in record.meals where meal.hasPhoto {
            for reference in meal.photoURLs.prefix(perMeal) {
                guard photos.count < limit else { return photos }
                guard let image = await image(for: reference),
                      let jpegData = downscaledJPEG(image, maxPixelSide: maxPixelSide) else { continue }
                let timeZone = TimeZone(identifier: meal.timeZoneIdentifier ?? "") ?? .autoupdatingCurrent
                photos.append(
                    DailyInsightContext.Photo(
                        mealTitle: meal.displayTitle,
                        timeLocal: meal.time?.displayClockTime(in: timeZone),
                        jpegData: jpegData
                    )
                )
            }
        }
        return photos
    }

    private static func image(for reference: String) async -> UIImage? {
        if let url = LocalPhotoStorageService.resolvedURL(for: reference),
           let data = try? Data(contentsOf: url) {
            return UIImage(data: data)
        }
        return await RemotePhotoCache.shared.image(for: reference)
    }

    private static func downscaledJPEG(_ image: UIImage, maxPixelSide: CGFloat) -> Data? {
        let longestSide = max(image.size.width, image.size.height)
        guard longestSide > 0 else { return nil }
        let scale = min(1, maxPixelSide / longestSide)
        let targetSize = CGSize(
            width: (image.size.width * scale).rounded(.down),
            height: (image.size.height * scale).rounded(.down)
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resized.jpegData(compressionQuality: 0.6)
    }
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
        model: String = "gpt-5.6-luna"
    ) {
        self.keyStore = keyStore
        self.session = session
        self.model = model
    }

    var isConfigured: Bool {
        keyStore.hasAPIKey
    }

    func generateNarrative(from payload: DailyInsightPayload) async throws -> DailyInsightNarrative {
        try await generateInsight(from: payload, context: .empty).narrative
    }

    func generateInsight(from payload: DailyInsightPayload, context: DailyInsightContext) async throws -> DailyInsightGeneration {
        guard let apiKey = keyStore.loadAPIKey(), !apiKey.isEmpty else {
            throw AIInsightServiceError.missingAPIKey
        }

        return try await performInsightRequest(
            endpointURL: URL(string: "https://api.openai.com/v1/responses")!,
            authorizationHeader: "Bearer \(apiKey)",
            payload: payload,
            context: context,
            model: model,
            session: session
        )
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
        model: String = "gpt-5.6-luna",
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
        try await generateInsight(from: payload, context: .empty).narrative
    }

    func generateInsight(from payload: DailyInsightPayload, context: DailyInsightContext) async throws -> DailyInsightGeneration {
        guard let endpointURL = configuration.endpointURL else {
            throw AIInsightServiceError.missingProxyURL
        }
        guard let idToken = try await authTokenProvider(), !idToken.isEmpty else {
            throw AIInsightServiceError.missingAuthToken
        }

        return try await performInsightRequest(
            endpointURL: endpointURL,
            authorizationHeader: "Bearer \(idToken)",
            payload: payload,
            context: context,
            model: model,
            session: session
        )
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

    func generateInsight(from payload: DailyInsightPayload, context: DailyInsightContext) async throws -> DailyInsightGeneration {
        if customKeyService.isConfigured {
            return try await customKeyService.generateInsight(from: payload, context: context)
        }
        return try await cloudService.generateInsight(from: payload, context: context)
    }

    func translateNarrative(_ narrative: DailyInsightNarrative, to language: AppLanguage) async throws -> DailyInsightNarrative.LocalizedText {
        if customKeyService.isConfigured {
            return try await customKeyService.translateNarrative(narrative, to: language)
        }
        return try await cloudService.translateNarrative(narrative, to: language)
    }
}

private func performInsightRequest(
    endpointURL: URL,
    authorizationHeader: String,
    payload: DailyInsightPayload,
    context: DailyInsightContext,
    model: String,
    session: URLSession
) async throws -> DailyInsightGeneration {
    var request = URLRequest(url: endpointURL)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    request.httpBody = try encoder.encode(makeInsightRequestBody(from: payload, context: context, model: model))

    let (data, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse,
          200..<300 ~= httpResponse.statusCode else {
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        throw parseNarrativeRequestError(statusCode: statusCode, data: data)
    }

    let insight = try parseStructuredResponse(InsightResponse.self, from: data) { !$0.zh.findings.isEmpty }
    var generation = insight.generation()
    generation.narrative.generatedAt = .now
    generation.narrative.scoringVersion = DailyInsightNarrative.currentScoringVersion
    generation.narrative.sampleCount = 1
    return generation
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

private func parseLocalizedNarrativeText(from data: Data) throws -> DailyInsightNarrative.LocalizedText {
    try parseStructuredResponse(DailyInsightNarrative.LocalizedText.self, from: data)
}

/// Accepts the structured value directly, as `parsed` content, or as JSON text inside a Responses
/// API envelope.
private func parseStructuredResponse<Value: Decodable>(
    _ type: Value.Type,
    from data: Data,
    isUsable: (Value) -> Bool = { _ in true }
) throws -> Value {
    let decoder = JSONDecoder()
    if let direct = try? decoder.decode(Value.self, from: data), isUsable(direct) {
        return direct
    }

    guard let envelope = try? decoder.decode(OpenAIResponseEnvelope<Value>.self, from: data) else {
        throw AIInsightServiceError.invalidResponse
    }
    if let parsed = envelope.parsedValues.first(where: isUsable) {
        return parsed
    }
    if let refusal = envelope.extractedRefusal, !refusal.isEmpty {
        throw AIInsightServiceError.providerError(refusal)
    }
    guard let text = envelope.extractedText, !text.isEmpty else {
        throw AIInsightServiceError.emptyResponse
    }
    guard let jsonData = extractJSONObject(from: text).data(using: .utf8),
          let value = try? decoder.decode(Value.self, from: jsonData) else {
        throw AIInsightServiceError.invalidResponse
    }
    guard isUsable(value) else {
        throw AIInsightServiceError.emptyResponse
    }
    return value
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
        case .string("openai_upstream_timeout"):
            return .providerError(NSLocalizedString("云端 AI 响应超时，请稍后重试。", comment: ""))
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
    case 504:
        return .providerError(NSLocalizedString("云端 AI 响应超时，请稍后重试。", comment: ""))
    default:
        return .requestFailed(statusCode: statusCode, message: nil)
    }
}

private let insightInstructions = """
You are the analyst inside DailyLogs, a personal journaling app. The user logs sleep, meals (sometimes with photos), showers and bowel movements. This is lifestyle reflection, not medical advice: never diagnose, never name conditions.

The app scores each section with fixed rules (day.appScores); each section's detail says what the rule counted. You give the final score by adjusting each included section by at most its maxAdjustment points, up or down, for what the rule cannot see: how the day compares with this user's own baseline and recent days, progress on context.goals, sleep stages and timing regularity, what the meal photos show, and context such as travel, weekday or weather. Do not adjust again for what the rule already counted. Beyond the score, notice what the user would not notice on their own, show the evidence from their data, and give one concrete thing to try next.

How to work:
1. Rebuild the target day: previous-night bedtime, wake time, meals, other events, in order (day.timeline). Note day.dayContext (weekday, place, weather, travel) and context.health when present.
2. Compare the day with the user's own baseline: day.comparisonContext has 7/30-day statistics, trends and one snapshot per recent day (bedtime, wake time, first/last meal times, notes). Look for links across days (late last meal and late bedtime, short sleep and a skipped meal the next day, weekday vs weekend drift), streaks, rebounds, and anything unusual for this user.
3. Use context.memory (what earlier analyses learned about this user) and context.goals (what the user wants to improve). Prefer findings that bear on the goals.
4. When photos are attached, look at what was eaten (rough composition, vegetables, protein, staple carbs, drinks, portion) and use it. Do not estimate calories precisely, and never describe a meal you were not shown.
5. When context.previousSuggestion is present, judge from this day's data whether it was followed and say so in followUp, briefly and kindly; say so if the data cannot tell. Use an empty string when there is no previous suggestion.

Rules:
- scoreAdjustments: exactly one entry per section whose maxAdjustment is above 0 (sleep and meals when included), none for any other section. Shower and bowel movement are minor sections the rule already scores on whether they were logged at the usual time. delta is an integer within plus or minus that section's maxAdjustment; the final section score stays between 0 and its maxScore, so a section already at full marks can only stay or go down. Use 0 when the rule got it right. reasonZh and reasonEn: one short sentence each, citing the concrete evidence behind the delta (or why the rule score stands). Be consistent: the same behavior should earn a similar adjustment on different days.
- findings: 1 to 3. Each is specific to this user's data and cites concrete times, numbers or dates as evidence. No generic advice ("sleep matters"). If the data is thin, write fewer findings rather than padding.
- The target-day arrays and day.targetDay counts are the only source of truth for the target day. History is for comparison; never infer a target-day meal, shower or bowel movement from history. Unrecorded is not the same as skipped.
- suggestion: exactly one, small and concrete enough to do tomorrow (a time, an amount or an action), and tied to a finding.
- headline: specific to this day, at most 16 Chinese characters / 8 English words. summary: one or two sentences.
- Tone: warm and direct, like a perceptive friend; light humor is fine; no moralizing.
- zh is natural Simplified Chinese and en is natural English, with the same content; do not translate word for word.
- memory: return the full updated list of durable observations about this user, at most 12 short sentences, written in context.memoryLanguage. Keep items that still hold, refine or drop ones the data contradicts, and add a pattern only when several days support it. Never store one-off events or guesses about health conditions.
"""

private func makeInsightRequestBody(
    from payload: DailyInsightPayload,
    context: DailyInsightContext,
    model: String
) throws -> OpenAIResponsesRequestBody {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let input = InsightRequestInput(
        day: payload,
        context: InsightRequestInput.Context(
            goals: context.goals?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            memory: context.memory,
            memoryLanguage: context.memoryLanguage,
            previousSuggestion: context.previousSuggestion?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            health: context.health?.isEmpty == false ? context.health : nil,
            attachedPhotos: context.photos.enumerated().map { index, photo in
                InsightRequestInput.PhotoLabel(index: index + 1, meal: photo.mealTitle, timeLocal: photo.timeLocal)
            }
        )
    )
    var content = [
        OpenAIResponsesInput.ContentPart.text(String(decoding: try encoder.encode(input), as: UTF8.self))
    ]
    for (index, photo) in context.photos.enumerated() {
        content.append(.text("Photo \(index + 1): \(photo.mealTitle)\(photo.timeLocal.map { " \($0)" } ?? "")"))
        content.append(.image(jpegData: photo.jpegData))
    }

    return OpenAIResponsesRequestBody(
        model: model,
        instructions: insightInstructions,
        input: .userContent(content),
        store: false,
        reasoning: OpenAIResponsesRequestBody.ReasoningConfiguration(effort: "medium"),
        text: OpenAIResponsesRequestBody.TextConfiguration(
            verbosity: "medium",
            format: OpenAIResponsesRequestBody.SchemaConfiguration(
                name: "daily_insight",
                schema: makeInsightSchema()
            )
        )
    )
}

private struct InsightRequestInput: Encodable {
    struct PhotoLabel: Encodable {
        var index: Int
        var meal: String
        var timeLocal: String?
    }

    struct Context: Encodable {
        var goals: String?
        var memory: [String]
        var memoryLanguage: String
        var previousSuggestion: String?
        var health: DailyHealthSummary?
        var attachedPhotos: [PhotoLabel]
    }

    var day: DailyInsightPayload
    var context: Context
}

private struct InsightResponse: Codable {
    struct Text: Codable {
        var headline: String
        var summary: String
        var findings: [DailyInsightNarrative.Finding]
        var suggestion: String
        var followUp: String
    }

    struct ScoreAdjustment: Codable {
        var section: String
        var delta: Int
        var reasonZh: String
        var reasonEn: String
    }

    var scoreAdjustments: [ScoreAdjustment]
    var zh: Text
    var en: Text
    var memory: [String]

    func generation() -> DailyInsightGeneration {
        let knownSections = Set(DailyInsightComponentKind.allCases.map(\.rawValue))
        var adjustments: [String: DailyInsightNarrative.ScoreAdjustment] = [:]
        var englishReasons: [String: String] = [:]
        for adjustment in scoreAdjustments where knownSections.contains(adjustment.section) {
            adjustments[adjustment.section] = DailyInsightNarrative.ScoreAdjustment(
                delta: adjustment.delta,
                reason: adjustment.reasonZh
            )
            englishReasons[adjustment.section] = adjustment.reasonEn
        }
        let english = DailyInsightNarrative.LocalizedText(
            headline: en.headline,
            summary: en.summary,
            bullets: en.findings.map(\.title),
            findings: en.findings,
            suggestion: en.suggestion,
            followUp: en.followUp,
            scoreReasons: englishReasons.isEmpty ? nil : englishReasons
        )
        let narrative = DailyInsightNarrative(
            headline: zh.headline,
            summary: zh.summary,
            bullets: zh.findings.map(\.title),
            findings: zh.findings,
            suggestion: zh.suggestion,
            followUp: zh.followUp,
            scoreAdjustments: adjustments.isEmpty ? nil : adjustments,
            sourceLanguageCode: AppLanguage.zhHans.aiNarrativeLanguageCode(),
            localizedTexts: [AppLanguage.en.aiNarrativeLanguageCode(): english]
        )
        let cleanedMemory = memory
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(12)
            .map { $0.count > 120 ? String($0.prefix(120)) : $0 }
        return DailyInsightGeneration(narrative: narrative, memory: Array(cleanedMemory))
    }
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
        input: .text(String(
            data: (try? JSONEncoder().encode(input)) ?? Data(),
            encoding: .utf8
        ) ?? "{}"),
        store: false,
        reasoning: OpenAIResponsesRequestBody.ReasoningConfiguration(effort: "low"),
        text: OpenAIResponsesRequestBody.TextConfiguration(
            verbosity: "low",
            format: OpenAIResponsesRequestBody.SchemaConfiguration(
                name: "daily_insight_translation",
                schema: makeLocalizedNarrativeSchema()
            )
        )
    )
}

private func makeInsightSchema() -> JSONValue {
    func nonEmptyString() -> JSONValue {
        .object(["type": .string("string"), "minLength": .number(1)])
    }

    let finding: JSONValue = .object([
        "type": .string("object"),
        "properties": .object([
            "title": nonEmptyString(),
            "evidence": nonEmptyString()
        ]),
        "required": .array([.string("title"), .string("evidence")]),
        "additionalProperties": .bool(false)
    ])
    let text: JSONValue = .object([
        "type": .string("object"),
        "properties": .object([
            "headline": nonEmptyString(),
            "summary": nonEmptyString(),
            "findings": .object([
                "type": .string("array"),
                "items": finding,
                "minItems": .number(1),
                "maxItems": .number(3)
            ]),
            "suggestion": nonEmptyString(),
            "followUp": .object(["type": .string("string")])
        ]),
        "required": .array([
            .string("headline"),
            .string("summary"),
            .string("findings"),
            .string("suggestion"),
            .string("followUp")
        ]),
        "additionalProperties": .bool(false)
    ])

    let scoreAdjustment: JSONValue = .object([
        "type": .string("object"),
        "properties": .object([
            "section": .object([
                "type": .string("string"),
                "enum": .array(DailyInsightComponentKind.allCases.map { .string($0.rawValue) })
            ]),
            "delta": .object(["type": .string("integer")]),
            "reasonZh": nonEmptyString(),
            "reasonEn": nonEmptyString()
        ]),
        "required": .array([.string("section"), .string("delta"), .string("reasonZh"), .string("reasonEn")]),
        "additionalProperties": .bool(false)
    ])

    return .object([
        "type": .string("object"),
        "properties": .object([
            "scoreAdjustments": .object([
                "type": .string("array"),
                "items": scoreAdjustment,
                "maxItems": .number(Double(DailyInsightComponentKind.allCases.count))
            ]),
            "zh": text,
            "en": text,
            "memory": .object([
                "type": .string("array"),
                "items": nonEmptyString(),
                "maxItems": .number(12)
            ])
        ]),
        "required": .array([.string("scoreAdjustments"), .string("zh"), .string("en"), .string("memory")]),
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

private func extractJSONObject(from text: String) -> String {
    guard let start = text.firstIndex(of: "{"),
          let end = text.lastIndex(of: "}") else {
        return text
    }
    return String(text[start...end])
}

private enum OpenAIResponsesInput: Encodable {
    enum ContentPart: Encodable {
        case text(String)
        case image(jpegData: Data)

        private enum CodingKeys: String, CodingKey {
            case type
            case text
            case imageURL = "image_url"
            case detail
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text(let text):
                try container.encode("input_text", forKey: .type)
                try container.encode(text, forKey: .text)
            case .image(let jpegData):
                try container.encode("input_image", forKey: .type)
                try container.encode("data:image/jpeg;base64,\(jpegData.base64EncodedString())", forKey: .imageURL)
                try container.encode("low", forKey: .detail)
            }
        }
    }

    case text(String)
    case userContent([ContentPart])

    private struct Message: Encodable {
        var role = "user"
        var content: [ContentPart]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text):
            try container.encode(text)
        case .userContent(let content):
            try container.encode([Message(content: content)])
        }
    }
}

private struct OpenAIResponsesRequestBody: Encodable {
    struct ReasoningConfiguration: Encodable {
        var effort: String
    }

    struct TextConfiguration: Encodable {
        var verbosity: String
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
    var input: OpenAIResponsesInput
    var store: Bool
    var reasoning: ReasoningConfiguration
    var text: TextConfiguration
}

private struct OpenAIResponseEnvelope<Parsed: Decodable>: Decodable {
    struct OutputItem: Decodable {
        struct ContentItem: Decodable {
            var type: String?
            var text: String?
            var parsed: Parsed?
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
                parsed = (try? container.decodeIfPresent(Parsed.self, forKey: .parsed)) ?? nil
                refusal = try container.decodeIfPresent(String.self, forKey: .refusal)
            }
        }

        var content: [ContentItem]?
    }

    var outputText: String?
    var outputParsed: Parsed?
    var output: [OutputItem]?
    var refusal: String?

    enum CodingKeys: String, CodingKey {
        case outputText = "output_text"
        case outputParsed = "output_parsed"
        case output
        case refusal
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        outputText = try container.decodeIfPresent(String.self, forKey: .outputText)
        outputParsed = (try? container.decodeIfPresent(Parsed.self, forKey: .outputParsed)) ?? nil
        output = try container.decodeIfPresent([OutputItem].self, forKey: .output)
        refusal = try container.decodeIfPresent(String.self, forKey: .refusal)
    }

    var parsedValues: [Parsed] {
        [outputParsed].compactMap { $0 } + (output ?? []).flatMap { $0.content ?? [] }.compactMap(\.parsed)
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
            targetDay: SignatureSeed.TargetDaySummary(from: targetDay),
            sleep: SignatureSeed.Sleep(
                source: sleep.source,
                bedtimeISO8601: sleep.bedtimeISO8601,
                wakeISO8601: sleep.wakeISO8601,
                targetBedtime: sleep.targetBedtime,
                durationHours: sleep.durationHours,
                hasStageData: sleep.hasStageData,
                stageMinutes: sleep.stageMinutes.map { [$0.deep, $0.rem, $0.light, $0.awake] },
                timeZoneIdentifier: sleep.timeZoneIdentifier,
                note: sleep.note
            ),
            meals: meals.enumerated().map { index, meal in
                SignatureSeed.Meal(
                    index: index,
                    status: meal.status,
                    timeISO8601: meal.timeISO8601,
                    hasPhoto: meal.hasPhoto,
                    photoCount: meal.photoCount,
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
                trailing30Days: SignatureSeed.HistoryWindowSummary(from: comparisonContext.trailing30Days),
                dailySnapshots: comparisonContext.dailySnapshots.map {
                    SignatureSeed.HistoryDaySnapshot(from: $0)
                }
            )
        )
    }

    private struct SignatureSeed: Encodable {
        struct TargetDaySummary: Encodable {
            var sleepDurationHours: Double?
            var trackedMealCount: Int
            var loggedMealCount: Int
            var skippedMealCount: Int
            var unrecordedMealCount: Int
            var timedLoggedMealCount: Int
            var showerCount: Int
            var hasShowerRecord: Bool
            var bowelMovementCount: Int
            var hasBowelMovementRecord: Bool
            var timelineEventCount: Int

            init(from source: DailyInsightPayload.TargetDaySummary) {
                sleepDurationHours = source.sleepDurationHours
                trackedMealCount = source.trackedMealCount
                loggedMealCount = source.loggedMealCount
                skippedMealCount = source.skippedMealCount
                unrecordedMealCount = source.unrecordedMealCount
                timedLoggedMealCount = source.timedLoggedMealCount
                showerCount = source.showerCount
                hasShowerRecord = source.hasShowerRecord
                bowelMovementCount = source.bowelMovementCount
                hasBowelMovementRecord = source.hasBowelMovementRecord
                timelineEventCount = source.timelineEventCount
            }
        }

        struct Sleep: Encodable {
            var source: String
            var bedtimeISO8601: String?
            var wakeISO8601: String?
            var targetBedtime: String?
            var durationHours: Double?
            var hasStageData: Bool
            var stageMinutes: [Int]?
            var timeZoneIdentifier: String?
            var note: String?
        }

        struct Meal: Encodable {
            var index: Int
            var status: String
            var timeISO8601: String?
            var hasPhoto: Bool
            var photoCount: Int
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

        struct TrendSummary: Encodable {
            var currentAverage: Double?
            var previousAverage: Double?
            var changeFromPreviousAverage: Double?
            var direction: String
            var volatility: String
            var observedDays: Int
            var comparisonDays: Int

            init(from source: DailyInsightPayload.TrendSummary) {
                currentAverage = source.currentAverage
                previousAverage = source.previousAverage
                changeFromPreviousAverage = source.changeFromPreviousAverage
                direction = source.direction
                volatility = source.volatility
                observedDays = source.observedDays
                comparisonDays = source.comparisonDays
            }
        }

        struct HistoryDaySnapshot: Encodable {
            var date: String
            var sleepDurationHours: Double?
            var mealCompletionRate: Double
            var timedMealLoggingRate: Double
            var firstMealLocal: String?
            var lastMealLocal: String?
            var showerCount: Int?
            var bowelMovementCount: Int?
            var bedtimeDeviationMinutes: Double?
            var notes: String?

            init(from source: DailyInsightPayload.HistoryDaySnapshot) {
                date = source.date
                sleepDurationHours = source.sleepDurationHours
                mealCompletionRate = source.mealCompletionRate
                timedMealLoggingRate = source.timedMealLoggingRate
                firstMealLocal = source.firstMealLocal
                lastMealLocal = source.lastMealLocal
                showerCount = source.showerCount
                bowelMovementCount = source.bowelMovementCount
                bedtimeDeviationMinutes = source.bedtimeDeviationMinutes
                notes = source.notes
            }
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
            var sleepDurationTrend: TrendSummary
            var mealCompletionTrend: TrendSummary
            var timedMealLoggingTrend: TrendSummary
            var showerCountTrend: TrendSummary
            var bowelMovementCountTrend: TrendSummary
            var bedtimeDeviationTrend: TrendSummary

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
                sleepDurationTrend = TrendSummary(from: source.sleepDurationTrend)
                mealCompletionTrend = TrendSummary(from: source.mealCompletionTrend)
                timedMealLoggingTrend = TrendSummary(from: source.timedMealLoggingTrend)
                showerCountTrend = TrendSummary(from: source.showerCountTrend)
                bowelMovementCountTrend = TrendSummary(from: source.bowelMovementCountTrend)
                bedtimeDeviationTrend = TrendSummary(from: source.bedtimeDeviationTrend)
            }
        }

        struct HistoryContext: Encodable {
            var trailing7Days: HistoryWindowSummary
            var trailing30Days: HistoryWindowSummary
            var dailySnapshots: [HistoryDaySnapshot]
        }

        var analysisDate: String
        var appTimeZoneIdentifier: String
        var targetDay: TargetDaySummary
        var sleep: Sleep
        var meals: [Meal]
        var showerEnabled: Bool
        var showers: [Event]
        var bowelMovementEnabled: Bool
        var bowelMovements: [Event]
        var comparisonContext: HistoryContext
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

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

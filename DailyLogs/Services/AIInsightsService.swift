import Foundation
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
    struct ComponentScoreOverride: Codable, Equatable {
        var score: Int?
        var maxScore: Int?
        var detail: String?
        var included: Bool?
    }

    var headline: String
    var summary: String
    var bullets: [String]
    var overallScore: Int?
    var components: [String: ComponentScoreOverride]?
    var generatedAt: Date = .now

    enum CodingKeys: String, CodingKey {
        case headline
        case summary
        case bullets
        case overallScore
        case components
        case generatedAt
    }

    init(
        headline: String,
        summary: String,
        bullets: [String],
        overallScore: Int? = nil,
        components: [String: ComponentScoreOverride]? = nil,
        generatedAt: Date = .now
    ) {
        self.headline = headline
        self.summary = summary
        self.bullets = bullets
        self.overallScore = overallScore
        self.components = components
        self.generatedAt = generatedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        headline = try container.decode(String.self, forKey: .headline)
        summary = try container.decode(String.self, forKey: .summary)
        bullets = try container.decode([String].self, forKey: .bullets)
        overallScore = try container.decodeIfPresent(Int.self, forKey: .overallScore)
        components = try container.decodeIfPresent([String: ComponentScoreOverride].self, forKey: .components)
        generatedAt = try container.decodeIfPresent(Date.self, forKey: .generatedAt) ?? .now
    }

    var hasAIScoring: Bool {
        overallScore != nil || !(components ?? [:]).isEmpty
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
        var timeISO8601: String?
        var timeLocal: String?
        var note: String?
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
                timeISO8601: $0.time?.displayISO8601,
                timeLocal: localizedClockTime($0.time, timeZoneIdentifier: $0.timeZoneIdentifier),
                note: trimmedOptional($0.note)
            )
        }

        let bowelMovements = record.bowelMovements.map {
            DailyInsightPayload.EventSection(
                timeISO8601: $0.time?.displayISO8601,
                timeLocal: localizedClockTime($0.time, timeZoneIdentifier: $0.timeZoneIdentifier),
                note: trimmedOptional($0.note)
            )
        }

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
                targetBedtime: record.sleepRecord.targetBedtime?.displayTime,
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
}

struct NoopAIInsightNarrativeService: AIInsightNarrativeGenerating, Sendable {
    var isConfigured: Bool { false }

    func generateNarrative(from payload: DailyInsightPayload) async throws -> DailyInsightNarrative {
        throw AIInsightServiceError.missingAPIKey
    }
}

enum AIInsightServiceError: LocalizedError {
    case missingAPIKey
    case missingAuthToken
    case missingProxyURL
    case invalidResponse
    case emptyResponse
    case missingScores

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            NSLocalizedString("还没有配置 OpenAI API Key。", comment: "")
        case .missingAuthToken:
            NSLocalizedString("云端 AI 需要登录后的 Firebase 身份令牌。", comment: "")
        case .missingProxyURL:
            NSLocalizedString("云端 AI 代理地址还没有配置。", comment: "")
        case .invalidResponse:
            NSLocalizedString("AI 返回的数据格式无法识别。", comment: "")
        case .emptyResponse:
            NSLocalizedString("AI 这次没有返回可用内容。", comment: "")
        case .missingScores:
            NSLocalizedString("AI 返回了文案，但没有返回分数。", comment: "")
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

        return try await performNarrativeRequest(
            endpointURL: URL(string: "https://api.openai.com/v1/responses")!,
            authorizationHeader: "Bearer \(apiKey)",
            payload: payload,
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

        return try await performNarrativeRequest(
            endpointURL: endpointURL,
            authorizationHeader: "Bearer \(idToken)",
            payload: payload,
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
        throw AIInsightServiceError.invalidResponse
    }

    return try parseNarrative(from: data)
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
    let decoded = try JSONDecoder().decode(OpenAIResponseEnvelope.self, from: data)
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
        The payload includes the target day plus trailing 7-day and 30-day summary statistics.
        Use the target day as the baseline, then use the 7-day summary for short-term trend context and the 30-day summary for habit stability context.
        Reward genuine improvement versus the recent baseline, and avoid over-penalizing a single off day when the 30-day habit pattern is stable.
        The payload does not include any precomputed score. Compute every score yourself from the raw data.
        Respect whether a section is excluded, skipped, logged without time, or simply unrecorded.
        Be concrete about times and counts when present.
        Keep the tone warm, brief, lightly playful, and non-judgmental.
        You must return an overallScore from 0 to 100.
        You must return a score for every section.
        If a section is not enabled, set included to false and score to 0.
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
        }

        var content: [ContentItem]?
    }

    var outputText: String?
    var output: [OutputItem]?

    enum CodingKeys: String, CodingKey {
        case outputText = "output_text"
        case output
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

private extension AppLanguage {
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
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

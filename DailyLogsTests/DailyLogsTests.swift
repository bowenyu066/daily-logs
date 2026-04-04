import AuthenticationServices
import CoreLocation
import Foundation
import Testing
import UIKit
@testable import DailyLogs

struct DailyLogsTests {
    @Test
    func sleepDurationAcrossMidnight() {
        let calendar = Calendar.current
        let bedtime = calendar.date(from: DateComponents(year: 2026, month: 3, day: 13, hour: 23, minute: 30))!
        let wake = calendar.date(from: DateComponents(year: 2026, month: 3, day: 14, hour: 7, minute: 15))!
        let record = SleepRecord(
            bedtimePreviousNight: bedtime,
            wakeTimeCurrentDay: wake,
            targetBedtime: nil,
            source: .manual
        )

        #expect(record.duration == 27_900)
    }

    @Test
    func analyticsSummaryCountsMealsAndShowers() {
        let baseDay = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 10))!
        let record = DailyRecord(
            date: baseDay,
            sleepRecord: SleepRecord(
                bedtimePreviousNight: baseDay.addingTimeInterval(-8 * 3600),
                wakeTimeCurrentDay: baseDay,
                targetBedtime: nil,
                source: .manual
            ),
            meals: [
                MealEntry(mealKind: .breakfast, status: .logged, time: baseDay.settingTime(hour: 8, minute: 0)),
                MealEntry(mealKind: .lunch, status: .skipped),
                MealEntry(mealKind: .dinner, status: .logged, time: baseDay.settingTime(hour: 18, minute: 0))
            ],
            showers: [
                ShowerEntry(time: baseDay.settingTime(hour: 20, minute: 0))
            ],
            sunTimes: nil
        )

        let summary = AnalyticsCalculator.build(
            records: [record],
            range: .custom,
            customRange: baseDay...baseDay
        )

        #expect(summary.averageSleepHours == 8)
        #expect(summary.defaultMealCompletionRate == 2.0 / 3.0)
        #expect(summary.averageShowers == 1)
        #expect(summary.days.first?.loggedMeals == 2)
        #expect(summary.days.first?.trackedMeals == 3)
    }

    @Test
    func analyticsAveragesStartFromFirstFeatureRecord() {
        let calendar = Calendar.current
        let day1 = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        let day2 = calendar.date(from: DateComponents(year: 2026, month: 3, day: 2))!
        let day3 = calendar.date(from: DateComponents(year: 2026, month: 3, day: 3))!

        let records = [
            DailyRecord(
                date: day1,
                sleepRecord: SleepRecord(),
                meals: [MealEntry(mealKind: .breakfast)],
                showers: [],
                bowelMovements: [],
                sexualActivities: [],
                sunTimes: nil
            ),
            DailyRecord(
                date: day2,
                sleepRecord: SleepRecord(),
                meals: [MealEntry(mealKind: .breakfast)],
                showers: [ShowerEntry(time: day2.settingTime(hour: 21, minute: 0))],
                bowelMovements: [BowelMovementEntry(time: day2.settingTime(hour: 8, minute: 15))],
                sexualActivities: [SexualActivityEntry(date: day2)],
                sunTimes: nil
            ),
            DailyRecord(
                date: day3,
                sleepRecord: SleepRecord(),
                meals: [MealEntry(mealKind: .breakfast)],
                showers: [],
                bowelMovements: [],
                sexualActivities: [],
                sunTimes: nil
            )
        ]

        let summary = AnalyticsCalculator.build(
            records: records,
            range: .custom,
            customRange: day1...day3
        )

        #expect(summary.averageShowers == 0.5)
        #expect(summary.averageBowelMovements == 0.5)
        #expect(summary.averageSexualActivity == 1)
    }

    @Test
    func analyticsAverageBedtimeWrapsAcrossMidnight() throws {
        let calendar = Calendar.current
        let day1 = calendar.date(from: DateComponents(year: 2026, month: 3, day: 5))!
        let day2 = calendar.date(from: DateComponents(year: 2026, month: 3, day: 6))!

        let records = [
            DailyRecord(
                date: day1,
                sleepRecord: SleepRecord(
                    bedtimePreviousNight: day1.adding(days: -1).settingTime(hour: 23, minute: 57),
                    wakeTimeCurrentDay: day1.settingTime(hour: 7, minute: 30),
                    source: .manual
                ),
                meals: [MealEntry(mealKind: .breakfast)],
                showers: [],
                sunTimes: nil
            ),
            DailyRecord(
                date: day2,
                sleepRecord: SleepRecord(
                    bedtimePreviousNight: day2.adding(days: -1).settingTime(hour: 0, minute: 12),
                    wakeTimeCurrentDay: day2.settingTime(hour: 7, minute: 20),
                    source: .manual
                ),
                meals: [MealEntry(mealKind: .breakfast)],
                showers: [],
                sunTimes: nil
            )
        ]

        let summary = AnalyticsCalculator.build(
            records: records,
            range: .custom,
            customRange: day1...day2
        )

        let average = try #require(summary.averageBedtimeMinutes)
        #expect(abs(average - 5) < 1)
    }

    @Test
    func dailyInsightReportOnlyIncludesEnabledOptionalSections() throws {
        let day = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 20))!
        let preferences = UserPreferences(
            visibleHomeSections: [.sleep, .meals, .showers]
        )
        let record = DailyRecord(
            date: day,
            sleepRecord: SleepRecord(
                bedtimePreviousNight: day.adding(days: -1).settingTime(hour: 23, minute: 40),
                wakeTimeCurrentDay: day.settingTime(hour: 7, minute: 20),
                targetBedtime: DateComponents(hour: 23, minute: 30),
                source: RecordSource.manual
            ),
            meals: [
                MealEntry(mealKind: .breakfast, status: .logged, time: day.settingTime(hour: 8, minute: 10)),
                MealEntry(mealKind: .lunch, status: .logged),
                MealEntry(mealKind: .dinner, status: .skipped)
            ],
            showers: [
                ShowerEntry(time: day.settingTime(hour: 21, minute: 5))
            ],
            bowelMovements: [
                BowelMovementEntry(time: day.settingTime(hour: 7, minute: 45))
            ],
            sexualActivities: [],
            sunTimes: nil
        )

        let report = DailyInsightAnalyzer.buildReport(
            for: record,
            preferences: preferences,
            locale: Locale(identifier: "en_US")
        )

        let showerComponent = try #require(report.components.first(where: { $0.kind == .shower }))
        let bowelComponent = try #require(report.components.first(where: { $0.kind == .bowelMovement }))

        #expect(showerComponent.isIncluded == true)
        #expect(bowelComponent.isIncluded == false)
        #expect(report.includedComponents.count == 3)
        #expect(report.overallScore > 0)
    }

    @Test
    func dailyInsightPayloadPreservesMealStatusesAndSectionFlags() throws {
        let day = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 20))!
        let preferences = UserPreferences(
            appLanguage: .en,
            visibleHomeSections: [.sleep, .meals]
        )
        let record = DailyRecord(
            date: day,
            sleepRecord: SleepRecord(
                bedtimePreviousNight: day.adding(days: -1).settingTime(hour: 0, minute: 5),
                wakeTimeCurrentDay: day.settingTime(hour: 7, minute: 10),
                source: RecordSource.manual
            ),
            meals: [
                MealEntry(mealKind: .breakfast, status: .logged, time: day.settingTime(hour: 8, minute: 0)),
                MealEntry(mealKind: .lunch, status: .logged),
                MealEntry(mealKind: .dinner, status: .skipped),
                MealEntry(mealKind: .custom, customTitle: "Snack")
            ],
            showers: [],
            bowelMovements: [],
            sexualActivities: [],
            sunTimes: nil
        )

        let payload = DailyInsightAnalyzer.makePayload(
            record: record,
            preferences: preferences,
            language: .en,
            locale: Locale(identifier: "en_US"),
            history: [record]
        )
        let payloadJSON = String(decoding: try JSONEncoder().encode(payload), as: UTF8.self)

        #expect(payload.meals.map(\.status) == ["logged_with_time", "logged_without_time", "skipped", "unrecorded"])
        #expect(payload.showerEnabled == false)
        #expect(payload.bowelMovementEnabled == false)
        #expect(payload.comparisonContext.trailing7Days.recordedDays == 0)
        #expect(payloadJSON.contains("\"overallScore\"") == false)
        #expect(payloadJSON.contains("\"scoreBreakdown\"") == false)
        #expect(payloadJSON.contains("\"localSummary\"") == false)
    }

    @Test
    func dailyInsightNarrativeDecodesWithoutGeneratedAt() throws {
        let json = """
        {
          "headline": "昨天还不错",
          "summary": "睡眠和餐食比较稳。",
          "bullets": ["睡了 7.2 小时", "三餐里有两餐已记录"]
        }
        """

        let narrative = try JSONDecoder().decode(DailyInsightNarrative.self, from: Data(json.utf8))

        #expect(narrative.headline == "昨天还不错")
        #expect(narrative.summary == "睡眠和餐食比较稳。")
        #expect(narrative.bullets.count == 2)
    }

    @Test
    func dailyInsightNarrativeWithoutScoresIsDetected() throws {
        let narrative = DailyInsightNarrative(
            headline: "只有文案",
            summary: "没有分数",
            bullets: ["bullet 1", "bullet 2"]
        )

        #expect(narrative.hasAIScoring == false)
    }

    @Test
    func dailyInsightReportAppliesAIScoreOverrides() {
        let baseReport = DailyInsightReport(
            date: Date().startOfDay,
            overallScore: 61,
            title: "本地标题",
            summary: "本地总结",
            components: [
                DailyInsightComponent(kind: .sleep, score: 24, maxScore: 45, detail: "本地睡眠", isIncluded: true),
                DailyInsightComponent(kind: .meals, score: 18, maxScore: 35, detail: "本地餐食", isIncluded: true),
                DailyInsightComponent(kind: .shower, score: 4, maxScore: 10, detail: "本地洗澡", isIncluded: true),
                DailyInsightComponent(kind: .bowelMovement, score: 0, maxScore: 10, detail: "本地排便", isIncluded: false)
            ],
            highlights: ["本地观察 1", "本地观察 2"]
        )
        let narrative = DailyInsightNarrative(
            headline: "AI 说昨天很稳",
            summary: "AI 总结",
            bullets: ["AI 观察 1", "AI 观察 2"],
            overallScore: 88,
            components: [
                "sleep": .init(score: 91, maxScore: 100, detail: "AI 睡眠", included: true),
                "meals": .init(score: 82, maxScore: 100, detail: "AI 餐食", included: true),
                "shower": .init(score: 76, maxScore: 100, detail: "AI 洗澡", included: true),
                "bowelMovement": .init(score: 0, maxScore: 100, detail: "AI 排便未纳入", included: false)
            ]
        )

        let resolved = baseReport.applyingAIOverrides(narrative)

        #expect(resolved.overallScore == 88)
        #expect(resolved.title == "AI 说昨天很稳")
        #expect(resolved.summary == "AI 总结")
        #expect(resolved.highlights == ["AI 观察 1", "AI 观察 2"])
        #expect(resolved.components.first(where: { $0.kind == .sleep })?.score == 91)
        #expect(resolved.components.first(where: { $0.kind == .sleep })?.maxScore == 100)
        #expect(resolved.components.first(where: { $0.kind == .bowelMovement })?.isIncluded == false)
    }

    @Test @MainActor
    func refreshDailyInsightNarrativeRegeneratesWhenCachedNarrativeHasNoAIScoring() async {
        let today = Date().startOfDay
        let yesterday = today.adding(days: -1)
        let preferences = UserPreferences(
            healthKitSyncEnabled: false,
            visibleHomeSections: [.sleep, .meals, .showers]
        )
        let user = UserAccount(
            userID: "test-user",
            displayName: "Tester",
            email: nil,
            authMode: .guest,
            createdAt: today.adding(days: -30)
        )
        let record = DailyRecord(
            date: yesterday,
            sleepRecord: SleepRecord(
                bedtimePreviousNight: yesterday.adding(days: -1).settingTime(hour: 23, minute: 40),
                wakeTimeCurrentDay: yesterday.settingTime(hour: 7, minute: 20),
                source: .manual
            ),
            meals: [
                MealEntry(mealKind: .breakfast, status: .logged, time: yesterday.settingTime(hour: 8, minute: 0))
            ],
            showers: [],
            bowelMovements: [],
            sexualActivities: [],
            sunTimes: nil
        )
        let aiService = MockAIInsightNarrativeService(responses: [
            DailyInsightNarrative(
                headline: "旧版文案",
                summary: "没有分数",
                bullets: ["旧 bullet 1", "旧 bullet 2"]
            ),
            DailyInsightNarrative(
                headline: "旧版文案 2",
                summary: "还是没有分数",
                bullets: ["旧 bullet 3", "旧 bullet 4"]
            ),
            DailyInsightNarrative(
                headline: "新版 AI 打分",
                summary: "现在带分数了",
                bullets: ["新 bullet 1", "新 bullet 2"],
                overallScore: 84,
                components: [
                    "sleep": .init(score: 86, maxScore: 100, detail: "AI 睡眠", included: true),
                    "meals": .init(score: 80, maxScore: 100, detail: "AI 餐食", included: true),
                    "shower": .init(score: 65, maxScore: 100, detail: "AI 洗澡", included: true),
                    "bowelMovement": .init(score: 0, maxScore: 100, detail: "AI 排便未纳入", included: false)
                ]
            )
        ])
        let viewModel = AppViewModel(
            authService: MockAuthService(user: user),
            repository: InMemoryDailyRecordRepository(records: [yesterday.storageKey(): record]),
            preferencesStore: MockPreferencesStore(preferences: preferences),
            photoStorageService: MockPhotoStorageService(),
            sunTimesService: MockSunTimesService(),
            healthSyncAdapter: MockHealthSyncAdapter(sleepRecord: nil),
            cloudSyncService: NoopCloudSyncService(),
            aiInsightNarrativeService: aiService,
            openAIKeyStore: MockOpenAIKeyStore(key: "test-key"),
            locationService: LocationService(),
            selectedDate: yesterday,
            dailyRecord: DailyRecord.empty(for: yesterday, preferences: preferences),
            preferences: preferences
        )

        await viewModel.bootstrap()
        await viewModel.refreshDailyInsightNarrative(force: true)
        #expect(viewModel.isDisplayingAIScoredInsight == false)

        await viewModel.refreshDailyInsightNarrative()

        #expect(aiService.callCount == 3)
        #expect(viewModel.dailyInsightNarrative?.headline == "新版 AI 打分")
        #expect(viewModel.isDisplayingAIScoredInsight == true)
        #expect(viewModel.displayedDailyInsightReport?.overallScore == 84)
    }

    @Test @MainActor
    func refreshDailyInsightNarrativeUsesPersistedNarrativeWithoutCallingAI() async {
        let today = Date().startOfDay
        let yesterday = today.adding(days: -1)
        let preferences = UserPreferences(
            healthKitSyncEnabled: false,
            visibleHomeSections: [.sleep, .meals, .showers]
        )
        let user = UserAccount(
            userID: "persisted-ai-user",
            displayName: "Tester",
            email: nil,
            authMode: .guest,
            createdAt: today.adding(days: -30)
        )
        let persistedNarrative = DailyInsightNarrative(
            headline: "已缓存的 AI",
            summary: "直接命中缓存",
            bullets: ["缓存 bullet 1", "缓存 bullet 2"],
            overallScore: 90,
            components: [
                "sleep": .init(score: 92, maxScore: 100, detail: "AI 睡眠", included: true),
                "meals": .init(score: 88, maxScore: 100, detail: "AI 餐食", included: true),
                "shower": .init(score: 80, maxScore: 100, detail: "AI 洗澡", included: true),
                "bowelMovement": .init(score: 0, maxScore: 100, detail: "AI 排便未纳入", included: false)
            ]
        )
        let record = DailyRecord(
            date: yesterday,
            sleepRecord: SleepRecord(
                bedtimePreviousNight: yesterday.adding(days: -1).settingTime(hour: 23, minute: 20),
                wakeTimeCurrentDay: yesterday.settingTime(hour: 7, minute: 15),
                source: .manual
            ),
            meals: [
                MealEntry(mealKind: .breakfast, status: .logged, time: yesterday.settingTime(hour: 8, minute: 0))
            ],
            showers: [],
            bowelMovements: [],
            sexualActivities: [],
            sunTimes: nil,
            aiInsightNarrative: persistedNarrative
        )
        let aiService = MockAIInsightNarrativeService(responses: [
            DailyInsightNarrative(
                headline: "不该被调用",
                summary: "不该生成",
                bullets: ["x", "y"],
                overallScore: 10,
                components: [
                    "sleep": .init(score: 10, maxScore: 100, detail: "x", included: true),
                    "meals": .init(score: 10, maxScore: 100, detail: "x", included: true),
                    "shower": .init(score: 10, maxScore: 100, detail: "x", included: true),
                    "bowelMovement": .init(score: 0, maxScore: 100, detail: "x", included: false)
                ]
            )
        ])
        let viewModel = AppViewModel(
            authService: MockAuthService(user: user),
            repository: InMemoryDailyRecordRepository(records: [yesterday.storageKey(): record]),
            preferencesStore: MockPreferencesStore(preferences: preferences),
            photoStorageService: MockPhotoStorageService(),
            sunTimesService: MockSunTimesService(),
            healthSyncAdapter: MockHealthSyncAdapter(sleepRecord: nil),
            cloudSyncService: NoopCloudSyncService(),
            aiInsightNarrativeService: aiService,
            openAIKeyStore: MockOpenAIKeyStore(key: "test-key"),
            locationService: LocationService(),
            selectedDate: yesterday,
            dailyRecord: DailyRecord.empty(for: yesterday, preferences: preferences),
            preferences: preferences
        )

        await viewModel.bootstrap()
        await viewModel.refreshDailyInsightNarrative()

        #expect(aiService.callCount == 0)
        #expect(viewModel.activeDailyInsightNarrative?.headline == "已缓存的 AI")
        #expect(viewModel.displayedDailyInsightReport?.overallScore == 90)
    }

    @Test @MainActor
    func bootstrapClearsLegacyOpenAIKeyAndUsesInjectedAIServiceState() async {
        let today = Date().startOfDay
        let preferences = UserPreferences(healthKitSyncEnabled: false)
        let user = UserAccount(
            userID: "legacy-key-user",
            displayName: "Tester",
            email: nil,
            authMode: .guest,
            createdAt: today
        )
        let keyStore = MockOpenAIKeyStore(key: "legacy-key")
        let aiService = MockAIInsightNarrativeService(responses: [
            DailyInsightNarrative(
                headline: "AI 可用",
                summary: "测试注入的服务仍然可用",
                bullets: ["a", "b"],
                overallScore: 80,
                components: [
                    "sleep": .init(score: 80, maxScore: 100, detail: "x", included: true),
                    "meals": .init(score: 80, maxScore: 100, detail: "x", included: true),
                    "shower": .init(score: 80, maxScore: 100, detail: "x", included: true),
                    "bowelMovement": .init(score: 0, maxScore: 100, detail: "x", included: false)
                ]
            )
        ])
        let viewModel = AppViewModel(
            authService: MockAuthService(user: user),
            repository: InMemoryDailyRecordRepository(),
            preferencesStore: MockPreferencesStore(preferences: preferences),
            photoStorageService: MockPhotoStorageService(),
            sunTimesService: MockSunTimesService(),
            healthSyncAdapter: MockHealthSyncAdapter(sleepRecord: nil),
            cloudSyncService: NoopCloudSyncService(),
            aiInsightNarrativeService: aiService,
            openAIKeyStore: keyStore,
            locationService: LocationService(),
            selectedDate: today,
            dailyRecord: DailyRecord.empty(for: today, preferences: preferences),
            preferences: preferences
        )

        await viewModel.bootstrap()

        #expect(keyStore.key == nil)
        #expect(keyStore.deleteCallCount == 1)
        #expect(viewModel.canGenerateAIInsights == true)
        #expect(viewModel.isUsingCloudAIProxy == false)
    }

    @Test
    func anchoringCurrentClockTimeCopiesCurrentHourAndMinute() {
        let baseDate = Date().startOfDay.adding(days: -3)
        let anchored = baseDate.anchoringCurrentClockTime()
        let nowComponents = Calendar.current.dateComponents([.hour, .minute], from: .now)
        let anchoredComponents = Calendar.current.dateComponents([.hour, .minute], from: anchored)

        #expect(anchoredComponents.hour == nowComponents.hour)
        #expect(anchoredComponents.minute == nowComponents.minute)
        #expect(anchored.startOfDay == baseDate.startOfDay)
    }

    @Test
    func recordsByStorageKeyDeduplicatesSameDayRemoteRecords() {
        let calendar = Calendar.current
        let day = calendar.date(from: DateComponents(year: 2026, month: 3, day: 16, hour: 0, minute: 0))!
        let laterSameDay = calendar.date(from: DateComponents(year: 2026, month: 3, day: 16, hour: 18, minute: 45))!

        let sparseRecord = DailyRecord(
            date: day,
            sleepRecord: SleepRecord(),
            meals: [MealEntry(mealKind: .breakfast)],
            showers: [],
            sunTimes: nil
        )

        let richerRecord = DailyRecord(
            date: laterSameDay,
            sleepRecord: SleepRecord(
                bedtimePreviousNight: laterSameDay.addingTimeInterval(-8 * 3600),
                wakeTimeCurrentDay: laterSameDay,
                targetBedtime: nil,
                source: .manual
            ),
            meals: [
                MealEntry(
                    mealKind: .breakfast,
                    status: .logged,
                    time: laterSameDay.settingTime(hour: 8, minute: 30),
                    photoURL: "/tmp/breakfast.jpg"
                )
            ],
            showers: [ShowerEntry(time: laterSameDay.settingTime(hour: 21, minute: 0))],
            sunTimes: SunTimes(
                sunrise: laterSameDay.settingTime(hour: 6, minute: 50),
                sunset: laterSameDay.settingTime(hour: 19, minute: 12)
            )
        )

        let deduplicated = AppViewModel.recordsByStorageKey([sparseRecord, richerRecord])
        let expected = DailyRecord(
            date: richerRecord.date,
            sleepRecord: richerRecord.sleepRecord,
            meals: richerRecord.meals,
            showers: richerRecord.showers,
            sunTimes: richerRecord.sunTimes
        ).anchoredToStorageKey(day.storageKey())

        #expect(deduplicated.count == 1)
        #expect(deduplicated[day.storageKey()] == expected)
    }

    @Test
    func recordsByStorageKeyPrefersMoreRecentlyModifiedRecord() {
        let calendar = Calendar.current
        let day = calendar.date(from: DateComponents(year: 2026, month: 3, day: 18, hour: 0, minute: 0))!

        let olderRecord = DailyRecord(
            date: day,
            sleepRecord: SleepRecord(),
            meals: [
                MealEntry(mealKind: .breakfast, status: .logged, time: day.settingTime(hour: 8, minute: 0))
            ],
            showers: [ShowerEntry(time: day.settingTime(hour: 21, minute: 0))],
            sunTimes: nil,
            modifiedAt: day.settingTime(hour: 9, minute: 0)
        )

        let newerRecord = DailyRecord(
            date: day.settingTime(hour: 18, minute: 0),
            sleepRecord: SleepRecord(),
            meals: [MealEntry(mealKind: .breakfast)],
            showers: [],
            sunTimes: nil,
            modifiedAt: day.settingTime(hour: 22, minute: 0)
        )

        let deduplicated = AppViewModel.recordsByStorageKey([olderRecord, newerRecord])
        let expected = DailyRecord(
            date: newerRecord.date,
            sleepRecord: newerRecord.sleepRecord,
            meals: newerRecord.meals,
            showers: newerRecord.showers,
            sunTimes: newerRecord.sunTimes,
            modifiedAt: newerRecord.modifiedAt
        ).anchoredToStorageKey(day.storageKey())

        #expect(deduplicated[day.storageKey()] == expected)
    }

    @Test
    func recordsByStorageKeyCollapsesShiftedTravelDuplicatesUsingRecordedTimeZones() {
        let formatter = ISO8601DateFormatter()
        let london = TimeZone(identifier: "Europe/London")!
        let shiftedDate = formatter.date(from: "2026-03-27T00:00:00Z")!

        let shiftedRecord = DailyRecord(
            date: shiftedDate,
            sleepRecord: SleepRecord(
                bedtimePreviousNight: formatter.date(from: "2026-03-26T23:40:00Z"),
                wakeTimeCurrentDay: formatter.date(from: "2026-03-27T07:20:00Z"),
                source: .manual,
                timeZoneIdentifier: london.identifier
            ),
            meals: [
                MealEntry(
                    mealKind: .breakfast,
                    status: .logged,
                    time: formatter.date(from: "2026-03-27T08:10:00Z"),
                    timeZoneIdentifier: london.identifier
                )
            ],
            showers: [],
            bowelMovements: [],
            sexualActivities: [],
            sunTimes: nil,
            modifiedAt: formatter.date(from: "2026-03-27T12:00:00Z")
        )

        let duplicate = shiftedRecord.anchoredToStorageKey("2026-03-27")
        let deduplicated = AppViewModel.recordsByStorageKey([shiftedRecord, duplicate])

        #expect(deduplicated.count == 1)
        #expect(deduplicated["2026-03-27"]?.date.storageKey() == "2026-03-27")
    }

    @Test
    func storageKeyRoundTripPreservesCalendarDayAcrossTimeZones() throws {
        var londonCalendar = Calendar(identifier: .gregorian)
        londonCalendar.timeZone = TimeZone(identifier: "Europe/London")!
        let stored = try #require(Date.fromStorageKey("2026-03-27", calendar: londonCalendar))

        var bostonCalendar = Calendar(identifier: .gregorian)
        bostonCalendar.timeZone = TimeZone(identifier: "America/New_York")!

        #expect(stored.storageKey(calendar: londonCalendar) == "2026-03-27")
        #expect(stored.storageKey(calendar: bostonCalendar) == "2026-03-27")
    }

    @Test
    func localRepositoryAnchorsStoredRecordsToTheirDictionaryKeys() throws {
        let formatter = ISO8601DateFormatter()
        let filename = "dailylogs-tests-\(UUID().uuidString).json"
        let store = LocalJSONStore(filename: filename)
        let repository = LocalDailyRecordRepository(store: store)
        let userID = "travel-user"
        let storedKey = "2026-03-27"

        var database = LocalJSONStore.Database()
        database.recordsByUser[userID] = [
            storedKey: DailyRecord(
                date: formatter.date(from: "2026-03-27T00:00:00Z")!,
                sleepRecord: SleepRecord(
                    bedtimePreviousNight: formatter.date(from: "2026-03-26T23:50:00Z"),
                    wakeTimeCurrentDay: formatter.date(from: "2026-03-27T07:10:00Z"),
                    source: .manual,
                    timeZoneIdentifier: "Europe/London"
                ),
                meals: [],
                showers: [],
                bowelMovements: [],
                sexualActivities: [],
                sunTimes: nil
            )
        ]
        try store.save(database)

        let loaded = try repository.loadAllRecords(userID: userID)

        #expect(loaded.count == 1)
        #expect(loaded.first?.date.storageKey() == storedKey)
    }

    @Test @MainActor
    func updatingProfileDoesNotMoveRegistrationDateEarlier() throws {
        let filename = "dailylogs-auth-tests-\(UUID().uuidString).json"
        let store = LocalJSONStore(filename: filename)
        let authService = LocalAuthService(store: store)
        let userID = "travel-auth-user"
        let pollutedDate = try #require(Date.fromStorageKey("2026-03-12"))
        let authoritativeDate = try #require(Date.fromStorageKey("2026-03-13"))

        var database = LocalJSONStore.Database()
        database.profilesByUser[userID] = UserProfile(
            userID: userID,
            displayName: "Tester",
            email: nil,
            authMode: .apple,
            createdAt: pollutedDate
        )
        database.recordsByUser[userID] = [
            "2026-03-12": DailyRecord.empty(
                for: pollutedDate,
                preferences: UserPreferences()
            )
        ]
        try store.save(database)

        let authoritativeUser = UserAccount(
            userID: userID,
            displayName: "Tester",
            email: nil,
            authMode: .apple,
            createdAt: authoritativeDate
        )

        let updated = try authService.updateDisplayName("Updated Tester", for: authoritativeUser)
        let savedProfile = try #require(store.load().profilesByUser[userID])

        #expect(updated.createdAt.storageKey() == "2026-03-13")
        #expect(savedProfile.createdAt.storageKey() == "2026-03-13")
    }

    @Test
    func blankManualSleepRecordStillAllowsHealthKitSync() {
        #expect(SleepRecord(source: .manual).blocksHealthKitSync == false)

        let manualSleep = SleepRecord(
            bedtimePreviousNight: Date(timeIntervalSince1970: 1_710_000_000),
            wakeTimeCurrentDay: Date(timeIntervalSince1970: 1_710_025_200),
            source: .manual
        )

        #expect(manualSleep.blocksHealthKitSync == true)
    }

    @Test
    func recordedTimeZoneMigrationBackfillsLegacyTimes() {
        let day = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 17))!
        let record = DailyRecord(
            date: day,
            sleepRecord: SleepRecord(
                bedtimePreviousNight: day.addingTimeInterval(-8 * 3600),
                wakeTimeCurrentDay: day,
                source: .manual
            ),
            meals: [
                MealEntry(
                    mealKind: .breakfast,
                    status: .logged,
                    time: day.settingTime(hour: 8, minute: 0)
                )
            ],
            showers: [
                ShowerEntry(time: day.settingTime(hour: 21, minute: 15))
            ],
            sunTimes: SunTimes(
                sunrise: day.settingTime(hour: 6, minute: 55),
                sunset: day.settingTime(hour: 19, minute: 8)
            )
        )

        let migrated = record.backfillingRecordedTimeZones("America/Denver")

        #expect(migrated.sleepRecord.timeZoneIdentifier == "America/Denver")
        #expect(migrated.meals.first?.timeZoneIdentifier == "America/Denver")
        #expect(migrated.showers.first?.timeZoneIdentifier == "America/Denver")
        #expect(migrated.sunTimes?.timeZoneIdentifier == "America/Denver")
    }

    @Test
    func timeDisplayModeDefaultsToRecordedTimeZone() {
        #expect(UserPreferences().timeDisplayMode == .recorded)
    }

    @Test @MainActor
    func manualHealthKitSyncCanOverwriteExistingSleepData() async {
        let today = Date().startOfDay
        let localSleep = SleepRecord(
            bedtimePreviousNight: today.adding(days: -1).settingTime(hour: 23, minute: 30),
            wakeTimeCurrentDay: today.settingTime(hour: 7, minute: 0),
            targetBedtime: nil,
            source: .manual
        )
        let healthKitSleep = SleepRecord(
            bedtimePreviousNight: today.adding(days: -1).settingTime(hour: 22, minute: 45),
            wakeTimeCurrentDay: today.settingTime(hour: 6, minute: 50),
            targetBedtime: nil,
            source: .healthKit
        )
        var record = DailyRecord.empty(for: today, preferences: UserPreferences())
        record.sleepRecord = localSleep

        let repository = InMemoryDailyRecordRepository(records: [today.storageKey(): record])
        let healthSyncAdapter = MockHealthSyncAdapter(sleepRecord: healthKitSleep)
        let preferences = UserPreferences(healthKitSyncEnabled: true)
        let user = UserAccount(
            userID: "test-user",
            displayName: "Tester",
            email: nil,
            authMode: .guest,
            createdAt: today.adding(days: -30)
        )
        let viewModel = AppViewModel(
            authService: MockAuthService(user: user),
            repository: repository,
            preferencesStore: MockPreferencesStore(preferences: preferences),
            photoStorageService: MockPhotoStorageService(),
            sunTimesService: MockSunTimesService(),
            healthSyncAdapter: healthSyncAdapter,
            cloudSyncService: NoopCloudSyncService(),
            aiInsightNarrativeService: NoopAIInsightNarrativeService(),
            openAIKeyStore: MockOpenAIKeyStore(),
            locationService: LocationService(),
            selectedDate: today,
            dailyRecord: DailyRecord.empty(for: today, preferences: preferences),
            preferences: preferences
        )

        await viewModel.bootstrap()
        await Task.yield()

        #expect(viewModel.dailyRecord.sleepRecord.bedtimePreviousNight == localSleep.bedtimePreviousNight)
        #expect(healthSyncAdapter.fetchCount == 0)

        await viewModel.overwriteSleepWithHealthKit()

        #expect(healthSyncAdapter.fetchCount == 1)
        #expect(viewModel.dailyRecord.sleepRecord.bedtimePreviousNight == healthKitSleep.bedtimePreviousNight)
        #expect(viewModel.dailyRecord.sleepRecord.wakeTimeCurrentDay == healthKitSleep.wakeTimeCurrentDay)
        #expect(viewModel.dailyRecord.sleepRecord.source == .healthKit)
    }

    @Test @MainActor
    func bootstrapLoadsLocalTodayRecordBeforeCloudBootstrapReturns() async {
        let today = Date().startOfDay
        let localSleep = SleepRecord(
            bedtimePreviousNight: today.adding(days: -1).settingTime(hour: 23, minute: 40),
            wakeTimeCurrentDay: today.settingTime(hour: 8, minute: 5),
            targetBedtime: nil,
            source: .manual
        )

        var localRecord = DailyRecord.empty(for: today, preferences: UserPreferences())
        localRecord.sleepRecord = localSleep

        let repository = InMemoryDailyRecordRepository(records: [today.storageKey(): localRecord])
        let user = UserAccount(
            userID: "cloud-user",
            displayName: "Tester",
            email: nil,
            authMode: .apple,
            createdAt: today.adding(days: -30)
        )
        let cloudSyncService = BlockingCloudSyncService()
        let viewModel = AppViewModel(
            authService: MockAuthService(user: user),
            repository: repository,
            preferencesStore: MockPreferencesStore(preferences: UserPreferences()),
            photoStorageService: MockPhotoStorageService(),
            sunTimesService: MockSunTimesService(),
            healthSyncAdapter: MockHealthSyncAdapter(sleepRecord: nil),
            cloudSyncService: cloudSyncService,
            aiInsightNarrativeService: NoopAIInsightNarrativeService(),
            openAIKeyStore: MockOpenAIKeyStore(),
            locationService: LocationService(),
            selectedDate: today,
            dailyRecord: DailyRecord.empty(for: today, preferences: UserPreferences()),
            preferences: UserPreferences()
        )

        let bootstrapTask = Task {
            await viewModel.bootstrap()
        }

        await cloudSyncService.waitUntilBootstrapStarts()

        #expect(viewModel.dailyRecord.sleepRecord.bedtimePreviousNight == localSleep.bedtimePreviousNight)
        #expect(viewModel.dailyRecord.sleepRecord.wakeTimeCurrentDay == localSleep.wakeTimeCurrentDay)

        await cloudSyncService.resumeBootstrap()
        await bootstrapTask.value
    }

    @Test @MainActor
    func saveMealReusesExistingLogicalSlotWhenEditorHasStaleMealID() async {
        let today = Date().startOfDay
        let existingBreakfast = MealEntry(
            id: UUID(),
            mealKind: .breakfast,
            status: .empty
        )
        let existingRecord = DailyRecord(
            date: today,
            sleepRecord: SleepRecord(),
            meals: [
                existingBreakfast,
                MealEntry(mealKind: .lunch),
                MealEntry(mealKind: .dinner)
            ],
            showers: [],
            bowelMovements: [],
            sexualActivities: [],
            sunTimes: nil
        )

        let user = UserAccount(
            userID: "meal-user",
            displayName: "Tester",
            email: nil,
            authMode: .guest,
            createdAt: today.adding(days: -30)
        )
        let viewModel = AppViewModel(
            authService: MockAuthService(user: user),
            repository: InMemoryDailyRecordRepository(records: [today.storageKey(): existingRecord]),
            preferencesStore: MockPreferencesStore(preferences: UserPreferences()),
            photoStorageService: MockPhotoStorageService(),
            sunTimesService: MockSunTimesService(),
            healthSyncAdapter: MockHealthSyncAdapter(sleepRecord: nil),
            cloudSyncService: NoopCloudSyncService(),
            aiInsightNarrativeService: NoopAIInsightNarrativeService(),
            openAIKeyStore: MockOpenAIKeyStore(),
            locationService: LocationService(),
            selectedDate: today,
            dailyRecord: existingRecord,
            preferences: UserPreferences()
        )

        let staleBreakfastFromEditor = MealEntry(
            id: UUID(),
            mealKind: .breakfast,
            status: .logged,
            time: today.settingTime(hour: 8, minute: 20)
        )

        await viewModel.saveMeal(staleBreakfastFromEditor, images: [])

        let breakfasts = viewModel.dailyRecord.meals.filter { $0.mealKind == .breakfast }
        #expect(breakfasts.count == 1)
        #expect(breakfasts.first?.id == existingBreakfast.id)
        #expect(breakfasts.first?.status == .logged)
        #expect(breakfasts.first?.time == today.settingTime(hour: 8, minute: 20))
    }

    @Test @MainActor
    func bootstrapDeduplicatesDuplicateMealSlotsAndKeepsRicherMeal() async {
        let today = Date().startOfDay
        let richerBreakfast = MealEntry(
            id: UUID(),
            mealKind: .breakfast,
            status: .logged,
            time: today.settingTime(hour: 8, minute: 10)
        )
        let duplicateBreakfast = MealEntry(
            id: UUID(),
            mealKind: .breakfast,
            status: .empty
        )
        let duplicatedRecord = DailyRecord(
            date: today,
            sleepRecord: SleepRecord(),
            meals: [
                duplicateBreakfast,
                richerBreakfast,
                MealEntry(mealKind: .lunch),
                MealEntry(mealKind: .dinner)
            ],
            showers: [],
            bowelMovements: [],
            sexualActivities: [],
            sunTimes: nil
        )

        let user = UserAccount(
            userID: "dup-user",
            displayName: "Tester",
            email: nil,
            authMode: .guest,
            createdAt: today.adding(days: -30)
        )
        let viewModel = AppViewModel(
            authService: MockAuthService(user: user),
            repository: InMemoryDailyRecordRepository(records: [today.storageKey(): duplicatedRecord]),
            preferencesStore: MockPreferencesStore(preferences: UserPreferences()),
            photoStorageService: MockPhotoStorageService(),
            sunTimesService: MockSunTimesService(),
            healthSyncAdapter: MockHealthSyncAdapter(sleepRecord: nil),
            cloudSyncService: NoopCloudSyncService(),
            aiInsightNarrativeService: NoopAIInsightNarrativeService(),
            openAIKeyStore: MockOpenAIKeyStore(),
            locationService: LocationService(),
            selectedDate: today,
            dailyRecord: DailyRecord.empty(for: today, preferences: UserPreferences()),
            preferences: UserPreferences()
        )

        await viewModel.bootstrap()

        let breakfasts = viewModel.dailyRecord.meals.filter { $0.mealKind == .breakfast }
        #expect(breakfasts.count == 1)
        #expect(breakfasts.first?.id == richerBreakfast.id)
        #expect(breakfasts.first?.status == .logged)
        #expect(breakfasts.first?.time == richerBreakfast.time)
    }

    @Test @MainActor
    func automaticHealthKitSyncOnlyRunsOnceForToday() async {
        let today = Date().startOfDay
        let healthKitSleep = SleepRecord(
            bedtimePreviousNight: today.adding(days: -1).settingTime(hour: 23, minute: 10),
            wakeTimeCurrentDay: today.settingTime(hour: 7, minute: 5),
            source: .healthKit
        )

        let repository = InMemoryDailyRecordRepository(records: [today.storageKey(): DailyRecord.empty(for: today, preferences: UserPreferences())])
        let healthSyncAdapter = MockHealthSyncAdapter(sleepRecord: healthKitSleep)
        let preferences = UserPreferences(healthKitSyncEnabled: true)
        let user = UserAccount(
            userID: "test-user",
            displayName: "Tester",
            email: nil,
            authMode: .guest,
            createdAt: today.adding(days: -30)
        )
        let viewModel = AppViewModel(
            authService: MockAuthService(user: user),
            repository: repository,
            preferencesStore: MockPreferencesStore(preferences: preferences),
            photoStorageService: MockPhotoStorageService(),
            sunTimesService: MockSunTimesService(),
            healthSyncAdapter: healthSyncAdapter,
            cloudSyncService: NoopCloudSyncService(),
            aiInsightNarrativeService: NoopAIInsightNarrativeService(),
            openAIKeyStore: MockOpenAIKeyStore(),
            locationService: LocationService(),
            selectedDate: today,
            dailyRecord: DailyRecord.empty(for: today, preferences: preferences),
            preferences: preferences
        )

        await viewModel.bootstrap()
        await Task.yield()
        await Task.yield()

        #expect(healthSyncAdapter.fetchCount == 1)

        await viewModel.syncHealthKitForCurrentDate()

        #expect(healthSyncAdapter.fetchCount == 1)
        #expect(viewModel.dailyRecord.sleepRecord.source == .healthKit)
    }

    @Test @MainActor
    func automaticHealthKitSyncSkipsPastDates() async {
        let today = Date().startOfDay
        let yesterday = today.adding(days: -1)
        let healthKitSleep = SleepRecord(
            bedtimePreviousNight: yesterday.adding(days: -1).settingTime(hour: 23, minute: 0),
            wakeTimeCurrentDay: yesterday.settingTime(hour: 7, minute: 0),
            source: .healthKit
        )

        let repository = InMemoryDailyRecordRepository(records: [yesterday.storageKey(): DailyRecord.empty(for: yesterday, preferences: UserPreferences())])
        let healthSyncAdapter = MockHealthSyncAdapter(sleepRecord: healthKitSleep)
        let preferences = UserPreferences(healthKitSyncEnabled: true)
        let user = UserAccount(
            userID: "test-user",
            displayName: "Tester",
            email: nil,
            authMode: .guest,
            createdAt: today.adding(days: -30)
        )
        let viewModel = AppViewModel(
            authService: MockAuthService(user: user),
            repository: repository,
            preferencesStore: MockPreferencesStore(preferences: preferences),
            photoStorageService: MockPhotoStorageService(),
            sunTimesService: MockSunTimesService(),
            healthSyncAdapter: healthSyncAdapter,
            cloudSyncService: NoopCloudSyncService(),
            aiInsightNarrativeService: NoopAIInsightNarrativeService(),
            openAIKeyStore: MockOpenAIKeyStore(),
            locationService: LocationService(),
            selectedDate: yesterday,
            dailyRecord: DailyRecord.empty(for: yesterday, preferences: preferences),
            preferences: preferences
        )

        await viewModel.bootstrap()
        await Task.yield()

        #expect(healthSyncAdapter.fetchCount == 0)
    }

    @Test
    func cloudCryptoRoundTripPreservesRecord() throws {
        let crypto = CloudCryptoService()
        let metadata = crypto.makeMetadata()
        let key = try crypto.deriveKey(passphrase: "horse-battery-staple", metadata: metadata)

        let day = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 18))!
        let original = DailyRecord(
            date: day,
            sleepRecord: SleepRecord(
                bedtimePreviousNight: day.adding(days: -1).settingTime(hour: 23, minute: 30),
                wakeTimeCurrentDay: day.settingTime(hour: 7, minute: 0),
                targetBedtime: nil,
                source: .manual,
                note: "slept well"
            ),
            meals: [
                MealEntry(
                    mealKind: .breakfast,
                    status: .logged,
                    time: day.settingTime(hour: 8, minute: 33),
                    photoURL: SecureCloudPhotoReference.make(
                        bucket: "dailylogs.appspot.com",
                        path: "users/test-user/secure-meal-photos/a.bin"
                    ),
                    note: "oatmeal"
                )
            ],
            showers: [
                ShowerEntry(
                    time: day.settingTime(hour: 8, minute: 17),
                    note: "quick shower"
                )
            ],
            sunTimes: SunTimes(
                sunrise: day.settingTime(hour: 6, minute: 58),
                sunset: day.settingTime(hour: 19, minute: 11),
                timeZoneIdentifier: "America/Denver"
            )
        )

        let envelope = try crypto.encrypt(original, key: key)
        let decrypted = try crypto.decrypt(DailyRecord.self, from: envelope, key: key)

        #expect(decrypted == original)
    }

    @Test
    func secureCloudPhotoReferenceRoundTrip() {
        let reference = SecureCloudPhotoReference.make(
            bucket: "dailylogs.appspot.com",
            path: "users/test-user/secure-meal-photos/photo.bin"
        )

        #expect(SecureCloudPhotoReference.isSecureReference(reference))
        #expect(SecureCloudPhotoReference.parse(reference)?.bucket == "dailylogs.appspot.com")
        #expect(SecureCloudPhotoReference.parse(reference)?.path == "users/test-user/secure-meal-photos/photo.bin")
        #expect(SecureCloudPhotoReference.parse("https://example.com/image.jpg") == nil)
    }

    @Test
    func mealEntryDecodesLegacySinglePhotoField() throws {
        let json = """
        {
          "mealKind": "breakfast",
          "status": "logged",
          "photoURL": "/tmp/legacy-breakfast.jpg"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(MealEntry.self, from: json)

        #expect(decoded.photoURLs == ["/tmp/legacy-breakfast.jpg"])
        #expect(decoded.photoURL == "/tmp/legacy-breakfast.jpg")
    }

    @Test
    func mealEntryRoundTripPreservesMultiplePhotoURLs() throws {
        let original = MealEntry(
            mealKind: .lunch,
            status: .logged,
            photoURLs: ["/tmp/lunch-1.jpg", "/tmp/lunch-2.jpg"]
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MealEntry.self, from: data)

        #expect(decoded.photoURLs == original.photoURLs)
    }
}

@MainActor
private final class MockAuthService: AuthService {
    var currentUser: UserAccount?

    init(user: UserAccount?) {
        self.currentUser = user
    }

    func restoreSession() -> UserAccount? {
        currentUser
    }

    func prepareAppleSignIn(_ request: ASAuthorizationAppleIDRequest) {}

    func handleAppleSignIn(result: Result<ASAuthorization, Error>) async throws -> UserAccount {
        currentUser!
    }

    func continueAsGuest() throws -> UserAccount {
        currentUser!
    }

    func updateDisplayName(_ name: String, for user: UserAccount) throws -> UserAccount {
        user
    }

    func signOut() throws {}
}

private final class InMemoryDailyRecordRepository: DailyRecordRepository {
    private var records: [String: DailyRecord]

    init(records: [String: DailyRecord] = [:]) {
        self.records = records
    }

    func loadRecord(for date: Date, preferences: UserPreferences, userID: String) throws -> DailyRecord {
        records[date.storageKey()] ?? DailyRecord.empty(for: date, preferences: preferences)
    }

    func saveRecord(_ record: DailyRecord, userID: String) throws {
        records[record.date.storageKey()] = record
    }

    func loadAllRecords(userID: String) throws -> [DailyRecord] {
        Array(records.values)
    }
}

private final class MockOpenAIKeyStore: OpenAIKeyStoring, @unchecked Sendable {
    var key: String? = nil
    private(set) var deleteCallCount = 0

    init(key: String? = nil) {
        self.key = key
    }

    var hasAPIKey: Bool {
        key?.isEmpty == false
    }

    func loadAPIKey() -> String? {
        key
    }

    func saveAPIKey(_ key: String) throws {}

    func deleteAPIKey() {
        deleteCallCount += 1
        key = nil
    }
}

private final class MockAIInsightNarrativeService: AIInsightNarrativeGenerating, @unchecked Sendable {
    private let lock = NSLock()
    private let responses: [DailyInsightNarrative]
    private var nextIndex = 0
    private var storedCallCount = 0

    init(responses: [DailyInsightNarrative]) {
        self.responses = responses
    }

    var callCount: Int {
        lock.withLock { storedCallCount }
    }

    var isConfigured: Bool { true }

    func generateNarrative(from payload: DailyInsightPayload) async throws -> DailyInsightNarrative {
        lock.withLock {
            storedCallCount += 1
            let response = responses[min(nextIndex, responses.count - 1)]
            if nextIndex < responses.count - 1 {
                nextIndex += 1
            }
            return response
        }
    }
}

private struct MockPreferencesStore: PreferencesStore {
    var preferences: UserPreferences

    func loadPreferences(userID: String?) throws -> UserPreferences {
        preferences
    }

    func savePreferences(_ preferences: UserPreferences, userID: String?) throws {}
}

private struct MockPhotoStorageService: PhotoStorageService {
    func savePhoto(_ image: UIImage) throws -> String {
        "/tmp/mock.jpg"
    }

    func deletePhoto(at path: String) throws {}
}

private struct MockSunTimesService: SunTimesService {
    func sunTimes(for date: Date, coordinate: CLLocationCoordinate2D, timeZone: TimeZone) -> SunTimes? {
        nil
    }
}

@MainActor
private final class MockHealthSyncAdapter: HealthSyncAdapter {
    private let sleepRecord: SleepRecord?
    private(set) var fetchCount = 0

    init(sleepRecord: SleepRecord?) {
        self.sleepRecord = sleepRecord
    }

    func requestAuthorization() async throws {}

    func fetchSleepData(for date: Date, after registrationDate: Date) async throws -> SleepRecord? {
        fetchCount += 1
        return sleepRecord
    }
}

private actor BlockingCloudSyncGate {
    private var bootstrapStarted = false
    private var continuation: CheckedContinuation<CloudBootstrapPayload, Never>?

    func awaitBootstrap() async -> CloudBootstrapPayload {
        bootstrapStarted = true
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilStarted() async {
        while !bootstrapStarted {
            await Task.yield()
        }
    }

    func resume(payload: CloudBootstrapPayload = CloudBootstrapPayload(profile: nil, preferences: nil, records: [])) {
        continuation?.resume(returning: payload)
        continuation = nil
    }
}

private final class BlockingCloudSyncService: CloudSyncService, @unchecked Sendable {
    private let gate = BlockingCloudSyncGate()

    var isAvailable: Bool { true }

    func bootstrap(user: UserAccount, localPreferences: UserPreferences, localRecords: [DailyRecord]) async throws -> CloudBootstrapPayload {
        await gate.awaitBootstrap()
    }

    func pushPreferences(_ preferences: UserPreferences, user: UserAccount) async throws {}

    func pushRecord(_ record: DailyRecord, user: UserAccount) async throws {}

    func pushProfile(_ user: UserAccount) async throws {}

    func protectionSnapshot(for user: UserAccount) async throws -> CloudProtectionSnapshot {
        CloudProtectionSnapshot(mode: .disabled, localKeyAvailable: false)
    }

    func enableAutomaticEndToEndEncryption(
        user: UserAccount,
        localPreferences: UserPreferences,
        localRecords: [DailyRecord],
        progress: @escaping @Sendable (CloudMigrationProgress) async -> Void
    ) async throws {}

    func waitUntilBootstrapStarts() async {
        await gate.waitUntilStarted()
    }

    func resumeBootstrap() async {
        await gate.resume()
    }
}

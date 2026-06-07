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
    func sleepDurationSubtractsAwakeStages() {
        let calendar = Calendar.current
        let bedtime = calendar.date(from: DateComponents(year: 2026, month: 3, day: 13, hour: 23, minute: 0))!
        let wake = calendar.date(from: DateComponents(year: 2026, month: 3, day: 14, hour: 7, minute: 0))!
        let record = SleepRecord(
            bedtimePreviousNight: bedtime,
            wakeTimeCurrentDay: wake,
            targetBedtime: nil,
            source: .healthKit,
            stageIntervals: [
                SleepStageInterval(stage: .light, start: bedtime, end: bedtime.addingTimeInterval(2 * 3600)),
                SleepStageInterval(stage: .awake, start: bedtime.addingTimeInterval(2 * 3600), end: bedtime.addingTimeInterval(2.5 * 3600)),
                SleepStageInterval(stage: .deep, start: bedtime.addingTimeInterval(2.5 * 3600), end: wake)
            ]
        )

        #expect(record.duration == 27_000)
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
        #expect(abs(average - 12) < 1)
    }

    @Test
    func analyticsCustomRangeStopsAtToday() {
        let today = Date().startOfDay
        let customStart = today.adding(days: -3)
        let customEnd = today.adding(days: 3)
        let record = DailyRecord(
            date: customStart,
            sleepRecord: SleepRecord(),
            meals: [MealEntry(mealKind: .breakfast)],
            showers: [],
            sunTimes: nil
        )
        let summary = AnalyticsCalculator.build(
            records: [record],
            range: .custom,
            customRange: customStart...customEnd
        )

        #expect(summary.days.first?.date == customStart)
        #expect(summary.days.last?.date == today)
    }

    @Test
    func analyticsWeekRangeEndsAtYesterday() throws {
        let today = Date().startOfDay
        let records = (0..<7).map { offset in
            let date = today.adding(days: -(offset + 1))
            return DailyRecord(
                date: date,
                sleepRecord: SleepRecord(
                    bedtimePreviousNight: date.adding(days: -1).settingTime(hour: 23, minute: 0),
                    wakeTimeCurrentDay: date.settingTime(hour: 7, minute: 0),
                    source: .manual
                ),
                meals: [MealEntry(mealKind: .breakfast)],
                showers: [],
                sunTimes: nil
            )
        }

        let summary = AnalyticsCalculator.build(
            records: records,
            range: .week,
            today: today
        )

        #expect(summary.days.count == 7)
        #expect(summary.days.last?.date == today.adding(days: -1))
        #expect(summary.averageSleepHours == 8)
    }

    @Test
    func analyticsWeekRangeKeepsEmptyLastDayForMidnightModeLogicalToday() throws {
        let calendar = Calendar.current
        let logicalToday = calendar.date(from: DateComponents(year: 2026, month: 4, day: 19))!
        let records = (0..<6).map { offset in
            let date = logicalToday.adding(days: -(offset + 2))
            return DailyRecord(
                date: date,
                sleepRecord: SleepRecord(
                    bedtimePreviousNight: date.adding(days: -1).settingTime(hour: 23, minute: 0),
                    wakeTimeCurrentDay: date.settingTime(hour: 7, minute: 0),
                    source: .manual
                ),
                meals: [MealEntry(mealKind: .breakfast)],
                showers: [],
                sunTimes: nil
            )
        }

        let summary = AnalyticsCalculator.build(
            records: records,
            range: .week,
            today: logicalToday
        )

        #expect(summary.days.count == 7)
        #expect(summary.days.first?.date.storageKey() == "2026-04-12")
        #expect(summary.days.last?.date.storageKey() == "2026-04-18")
        #expect(summary.days.last?.sleepHours == nil)
        #expect(summary.days.last?.loggedMeals == 0)
    }

    @Test
    func analyticsUsesActualCalendarDayForTimedEvents() {
        let calendar = Calendar.current
        let logicalDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 19))!
        let actualNextDay = calendar.date(from: DateComponents(year: 2026, month: 4, day: 20, hour: 1, minute: 27))!
        let record = DailyRecord(
            date: logicalDate,
            sleepRecord: SleepRecord(),
            meals: [],
            showers: [ShowerEntry(time: actualNextDay)],
            bowelMovements: [],
            sexualActivities: [],
            sunTimes: nil
        )

        let summary = AnalyticsCalculator.build(
            records: [record],
            range: .custom,
            customRange: logicalDate...logicalDate.adding(days: 1),
            today: logicalDate.adding(days: 1)
        )

        #expect(summary.days.first?.date.storageKey() == "2026-04-19")
        #expect(summary.days.first?.showers == 0)
        #expect(summary.days.last?.date.storageKey() == "2026-04-20")
        #expect(summary.days.last?.showers == 1)
        #expect(summary.showerPoints.first?.date.storageKey() == "2026-04-20")
    }

    @Test
    func analyticsSplitsBedtimeAndWakeByActualDates() {
        let calendar = Calendar.current
        let wakeDay = calendar.date(from: DateComponents(year: 2026, month: 4, day: 19))!
        let bedtime = calendar.date(from: DateComponents(year: 2026, month: 4, day: 18, hour: 23, minute: 40))!
        let wake = calendar.date(from: DateComponents(year: 2026, month: 4, day: 19, hour: 7, minute: 10))!
        let record = DailyRecord(
            date: wakeDay,
            sleepRecord: SleepRecord(
                bedtimePreviousNight: bedtime,
                wakeTimeCurrentDay: wake,
                source: .manual
            ),
            meals: [],
            showers: [],
            bowelMovements: [],
            sexualActivities: [],
            sunTimes: nil
        )

        let summary = AnalyticsCalculator.build(
            records: [record],
            range: .custom,
            customRange: wakeDay.adding(days: -1)...wakeDay,
            today: wakeDay
        )

        #expect(summary.days.first?.date.storageKey() == "2026-04-18")
        #expect(summary.days.first?.bedtimeMinutes == Double(23 * 60 + 40))
        #expect(summary.days.first?.sleepHours == nil)
        #expect(summary.days.last?.date.storageKey() == "2026-04-19")
        #expect(summary.days.last?.sleepHours != nil)
        #expect(summary.days.last?.wakeMinutes == Double(7 * 60 + 10))
    }

    @Test
    func analyticsMapsRecordedTimeZoneSleepOntoLocalChartDay() throws {
        let recordedTimeZone = try #require(TimeZone(identifier: "Pacific/Kiritimati"))
        var recordedCalendar = Calendar(identifier: .gregorian)
        recordedCalendar.timeZone = recordedTimeZone
        let displayDay = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 27)))
        let bedtime = try #require(recordedCalendar.date(from: DateComponents(
            timeZone: recordedTimeZone,
            year: 2026,
            month: 3,
            day: 26,
            hour: 23,
            minute: 30
        )))
        let wake = try #require(recordedCalendar.date(from: DateComponents(
            timeZone: recordedTimeZone,
            year: 2026,
            month: 3,
            day: 27,
            hour: 7,
            minute: 30
        )))
        let record = DailyRecord(
            date: displayDay,
            sleepRecord: SleepRecord(
                bedtimePreviousNight: bedtime,
                wakeTimeCurrentDay: wake,
                source: .manual,
                timeZoneIdentifier: recordedTimeZone.identifier
            ),
            meals: [],
            showers: [],
            bowelMovements: [],
            sexualActivities: [],
            sunTimes: nil
        )

        let summary = AnalyticsCalculator.build(
            records: [record],
            range: .custom,
            customRange: displayDay...displayDay,
            today: displayDay
        )

        #expect(summary.days.first?.date.storageKey() == "2026-03-27")
        #expect(summary.days.first?.sleepHours == 8)
        #expect(summary.days.first?.wakeMinutes == Double(7 * 60 + 30))
    }

    @Test
    func analyticsComparisonUsesPreviousWindow() {
        let today = Date().startOfDay
        let currentWindow = (0..<7).map { offset in
            let date = today.adding(days: -(offset + 1))
            return DailyRecord(
                date: date,
                sleepRecord: SleepRecord(
                    bedtimePreviousNight: date.adding(days: -1).settingTime(hour: 23, minute: 0),
                    wakeTimeCurrentDay: date.settingTime(hour: 7, minute: 0),
                    source: .manual
                ),
                meals: [MealEntry(mealKind: .breakfast)],
                showers: [],
                sunTimes: nil
            )
        }
        let previousWindow = (7..<14).map { offset in
            let date = today.adding(days: -(offset + 1))
            return DailyRecord(
                date: date,
                sleepRecord: SleepRecord(
                    bedtimePreviousNight: date.settingTime(hour: 0, minute: 0),
                    wakeTimeCurrentDay: date.settingTime(hour: 6, minute: 0),
                    source: .manual
                ),
                meals: [MealEntry(mealKind: .breakfast)],
                showers: [],
                sunTimes: nil
            )
        }

        let summary = AnalyticsCalculator.build(
            records: currentWindow + previousWindow,
            range: .week,
            today: today
        )

        #expect(summary.averageSleepHours == 8)
        #expect(summary.previousAverageSleepHours == 6)
        #expect(summary.previousAverageBedtimeMinutes == 0)
    }

    @Test
    func analyticsMealCompletionCountsLoggedMealWithoutTime() {
        let day = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 10))!
        let record = DailyRecord(
            date: day,
            sleepRecord: SleepRecord(),
            meals: [
                MealEntry(mealKind: .breakfast, status: .logged),
                MealEntry(mealKind: .lunch, status: .logged, time: day.settingTime(hour: 12, minute: 30)),
                MealEntry(mealKind: .dinner, status: .empty)
            ],
            showers: [],
            bowelMovements: [],
            sexualActivities: [],
            sunTimes: nil
        )

        let summary = AnalyticsCalculator.build(
            records: [record],
            range: .custom,
            customRange: day...day,
            defaultMealSlots: MealSlot.defaults,
            today: day
        )

        let breakfastSeries = try? #require(summary.mealSeries.first(where: { $0.key == MealKind.breakfast.rawValue }))
        #expect(breakfastSeries?.completionRate == 1)
        #expect(summary.defaultMealCompletionRate == 2.0 / 3.0)
    }

    @Test
    func midnightModeShiftsEarlyMorningToPreviousDay() {
        let timestamp = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 19, hour: 2, minute: 30))!
        let preferences = UserPreferences(
            midnightMode: MidnightModeSettings(isEnabled: true, cutoffHour: 4, effectiveFrom: nil)
        )

        let logicalDate = preferences.logicalDate(for: timestamp)
        #expect(logicalDate.storageKey() == "2026-04-18")
    }

    @Test
    func habitFrequencyCalendarUsesMidnightModeLogicalDate() {
        let calendar = Calendar.current
        let logicalDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 19))!
        let afterMidnight = calendar.date(from: DateComponents(year: 2026, month: 4, day: 20, hour: 1, minute: 20))!
        let timeZoneIdentifier = TimeZone.autoupdatingCurrent.identifier
        let preferences = UserPreferences(
            midnightMode: MidnightModeSettings(isEnabled: true, cutoffHour: 4, effectiveFrom: nil)
        )
        let record = DailyRecord(
            date: logicalDate,
            sleepRecord: SleepRecord(),
            meals: [],
            showers: [
                ShowerEntry(time: afterMidnight, timeZoneIdentifier: timeZoneIdentifier)
            ],
            bowelMovements: [
                BowelMovementEntry(time: afterMidnight, timeZoneIdentifier: timeZoneIdentifier)
            ],
            sexualActivities: [
                SexualActivityEntry(date: logicalDate, time: afterMidnight, timeZoneIdentifier: timeZoneIdentifier)
            ]
        )

        let counts = HabitFrequencyDayCounts.aggregate(records: [record], preferences: preferences)
        let logicalCounts = counts[logicalDate.startOfDay]
        let actualNextDayCounts = counts[calendar.startOfDay(for: afterMidnight)]

        #expect(logicalCounts?.showers == 1)
        #expect(logicalCounts?.bowelMovements == 1)
        #expect(logicalCounts?.sexualActivities == 1)
        #expect(actualNextDayCounts == nil)
    }

    @Test
    func midnightModeUsesFixedFourAMCutoff() {
        let timestamp = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 19, hour: 3, minute: 30))!
        let preferences = UserPreferences(
            midnightMode: MidnightModeSettings(isEnabled: true, cutoffHour: 1, effectiveFrom: nil)
        )

        let logicalDate = preferences.logicalDate(for: timestamp)
        #expect(logicalDate.storageKey() == "2026-04-18")
    }

    @Test @MainActor
    func displayedClockTimeAddsNextDayMarkerInMidnightMode() {
        let referenceDate = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 19))!
        let afterMidnight = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 20, hour: 0, minute: 52))!
        let timeZoneIdentifier = TimeZone.autoupdatingCurrent.identifier
        let preferences = UserPreferences(
            midnightMode: MidnightModeSettings(isEnabled: true, cutoffHour: 4, effectiveFrom: nil)
        )
        let viewModel = AppViewModel(
            authService: MockAuthService(user: nil),
            repository: InMemoryDailyRecordRepository(records: [:]),
            preferencesStore: MockPreferencesStore(preferences: preferences),
            photoStorageService: MockPhotoStorageService(),
            videoStorageService: MockVideoStorageService(),
            sunTimesService: MockSunTimesService(),
            weatherService: MockWeatherService(),
            healthSyncAdapter: MockHealthSyncAdapter(sleepRecord: nil),
            cloudSyncService: NoopCloudSyncService(),
            aiInsightNarrativeService: MockAIInsightNarrativeService(responses: []),
            openAIKeyStore: MockOpenAIKeyStore(key: nil),
            locationService: LocationService(),
            selectedDate: referenceDate,
            dailyRecord: DailyRecord.empty(for: referenceDate, preferences: preferences),
            preferences: preferences
        )

        let rendered = viewModel.displayedClockTime(
            for: afterMidnight,
            recordedTimeZoneIdentifier: timeZoneIdentifier
        )

        #expect(rendered.contains("+1"))
    }

    @Test
    func astronomySunTimesKeepsEasternSunriseOnRequestedLocalDate() throws {
        let shanghai = try #require(TimeZone(identifier: "Asia/Shanghai"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = shanghai
        let day = try #require(calendar.date(from: DateComponents(
            timeZone: shanghai,
            year: 2026,
            month: 5,
            day: 26,
            hour: 12
        )))
        let service = AstronomySunTimesService()

        let sunTimes = try #require(service.sunTimes(
            for: day,
            coordinate: CLLocationCoordinate2D(latitude: 30.5928, longitude: 114.3055),
            timeZone: shanghai
        ))

        #expect(sunTimes.sunrise.storageKey(in: shanghai) == "2026-05-26")
        #expect(sunTimes.sunrise.displayClockTime(in: shanghai).hasPrefix("05"))
    }

    @Test @MainActor
    func resolvedEventTimestampShiftsEarlyMorningIntoNextCalendarDay() {
        let logicalDate = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 19))!
        let timeZoneIdentifier = TimeZone.autoupdatingCurrent.identifier
        let preferences = UserPreferences(
            midnightMode: MidnightModeSettings(isEnabled: true, cutoffHour: 4, effectiveFrom: nil)
        )
        let viewModel = AppViewModel(
            authService: MockAuthService(user: nil),
            repository: InMemoryDailyRecordRepository(records: [:]),
            preferencesStore: MockPreferencesStore(preferences: preferences),
            photoStorageService: MockPhotoStorageService(),
            videoStorageService: MockVideoStorageService(),
            sunTimesService: MockSunTimesService(),
            weatherService: MockWeatherService(),
            healthSyncAdapter: MockHealthSyncAdapter(sleepRecord: nil),
            cloudSyncService: NoopCloudSyncService(),
            aiInsightNarrativeService: MockAIInsightNarrativeService(responses: []),
            openAIKeyStore: MockOpenAIKeyStore(key: nil),
            locationService: LocationService(),
            selectedDate: logicalDate,
            dailyRecord: DailyRecord.empty(for: logicalDate, preferences: preferences),
            preferences: preferences
        )

        let resolved = viewModel.resolvedEventTimestamp(
            for: logicalDate,
            hour: 1,
            minute: 27,
            recordedTimeZoneIdentifier: timeZoneIdentifier
        )

        #expect(resolved.storageKey(in: .autoupdatingCurrent) == "2026-04-20")
        #expect(viewModel.displayedClockTime(for: resolved, recordedTimeZoneIdentifier: timeZoneIdentifier).contains("+1"))
    }

    @Test @MainActor
    func travelEventTimestampIgnoresMidnightModeShift() {
        let logicalDate = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 19))!
        let timeZoneIdentifier = TimeZone.autoupdatingCurrent.identifier
        let preferences = UserPreferences(
            midnightMode: MidnightModeSettings(isEnabled: true, cutoffHour: 4, effectiveFrom: nil)
        )
        let viewModel = AppViewModel(
            authService: MockAuthService(user: nil),
            repository: InMemoryDailyRecordRepository(records: [:]),
            preferencesStore: MockPreferencesStore(preferences: preferences),
            photoStorageService: MockPhotoStorageService(),
            videoStorageService: MockVideoStorageService(),
            sunTimesService: MockSunTimesService(),
            weatherService: MockWeatherService(),
            healthSyncAdapter: MockHealthSyncAdapter(sleepRecord: nil),
            cloudSyncService: NoopCloudSyncService(),
            aiInsightNarrativeService: MockAIInsightNarrativeService(responses: []),
            openAIKeyStore: MockOpenAIKeyStore(key: nil),
            locationService: LocationService(),
            selectedDate: logicalDate,
            dailyRecord: DailyRecord.empty(for: logicalDate, preferences: preferences),
            preferences: preferences
        )
        let travelContext = TravelRecordContext(planID: UUID(), segmentID: UUID(), phase: .inFlight)

        let resolved = viewModel.resolvedEventTimestamp(
            for: logicalDate,
            hour: 1,
            minute: 27,
            recordedTimeZoneIdentifier: timeZoneIdentifier,
            travelContext: travelContext
        )

        #expect(resolved.storageKey(in: .autoupdatingCurrent) == "2026-04-19")
        #expect(viewModel.displayedClockTime(for: resolved, recordedTimeZoneIdentifier: timeZoneIdentifier).contains("+1") == false)
    }

    @Test @MainActor
    func normalizedEventTimestampDropsNextDayMarkerAfterWheelMovesPastCutoff() {
        let logicalDate = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 19))!
        let nextDayShell = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 20, hour: 21, minute: 6))!
        let timeZoneIdentifier = TimeZone.autoupdatingCurrent.identifier
        let preferences = UserPreferences(
            midnightMode: MidnightModeSettings(isEnabled: true, cutoffHour: 4, effectiveFrom: nil)
        )
        let viewModel = AppViewModel(
            authService: MockAuthService(user: nil),
            repository: InMemoryDailyRecordRepository(records: [:]),
            preferencesStore: MockPreferencesStore(preferences: preferences),
            photoStorageService: MockPhotoStorageService(),
            videoStorageService: MockVideoStorageService(),
            sunTimesService: MockSunTimesService(),
            weatherService: MockWeatherService(),
            healthSyncAdapter: MockHealthSyncAdapter(sleepRecord: nil),
            cloudSyncService: NoopCloudSyncService(),
            aiInsightNarrativeService: MockAIInsightNarrativeService(responses: []),
            openAIKeyStore: MockOpenAIKeyStore(key: nil),
            locationService: LocationService(),
            selectedDate: logicalDate,
            dailyRecord: DailyRecord.empty(for: logicalDate, preferences: preferences),
            preferences: preferences
        )

        let normalized = viewModel.normalizedEventTimestamp(
            from: nextDayShell,
            baseDate: logicalDate,
            recordedTimeZoneIdentifier: timeZoneIdentifier
        )
        let rendered = viewModel.displayedClockTime(for: normalized, recordedTimeZoneIdentifier: timeZoneIdentifier)

        #expect(normalized.storageKey(in: .autoupdatingCurrent) == "2026-04-19")
        #expect(rendered.contains("+1") == false)
    }

    @Test @MainActor
    func resolvedEventTimestampKeepsOlderDatesUnshiftedWhenMidnightModeStartsLater() {
        let logicalDate = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 18))!
        let effectiveFrom = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 20, hour: 1, minute: 0))!
        let preferences = UserPreferences(
            midnightMode: MidnightModeSettings(isEnabled: true, cutoffHour: 4, effectiveFrom: effectiveFrom)
        )
        let viewModel = AppViewModel(
            authService: MockAuthService(user: nil),
            repository: InMemoryDailyRecordRepository(records: [:]),
            preferencesStore: MockPreferencesStore(preferences: preferences),
            photoStorageService: MockPhotoStorageService(),
            videoStorageService: MockVideoStorageService(),
            sunTimesService: MockSunTimesService(),
            weatherService: MockWeatherService(),
            healthSyncAdapter: MockHealthSyncAdapter(sleepRecord: nil),
            cloudSyncService: NoopCloudSyncService(),
            aiInsightNarrativeService: MockAIInsightNarrativeService(responses: []),
            openAIKeyStore: MockOpenAIKeyStore(key: nil),
            locationService: LocationService(),
            selectedDate: logicalDate,
            dailyRecord: DailyRecord.empty(for: logicalDate, preferences: preferences),
            preferences: preferences
        )

        let resolved = viewModel.resolvedEventTimestamp(
            for: logicalDate,
            hour: 1,
            minute: 27,
            recordedTimeZoneIdentifier: TimeZone.autoupdatingCurrent.identifier
        )

        #expect(resolved.storageKey(in: .autoupdatingCurrent) == "2026-04-18")
    }

    @Test @MainActor
    func aiInsightCalendarRangeExcludesLogicalToday() async throws {
        let today = Date().startOfDay
        let yesterday = today.adding(days: -1)
        let tenDaysAgo = today.adding(days: -10)
        let user = UserAccount(
            userID: "tester",
            displayName: "Tester",
            email: nil,
            authMode: .apple,
            createdAt: tenDaysAgo
        )
        let repository = InMemoryDailyRecordRepository(records: [
            yesterday.storageKey(): DailyRecord.empty(for: yesterday, preferences: UserPreferences()),
            today.storageKey(): DailyRecord.empty(for: today, preferences: UserPreferences())
        ])
        let viewModel = AppViewModel(
            authService: MockAuthService(user: user),
            repository: repository,
            preferencesStore: MockPreferencesStore(preferences: UserPreferences()),
            photoStorageService: MockPhotoStorageService(),
            videoStorageService: MockVideoStorageService(),
            sunTimesService: MockSunTimesService(),
            weatherService: MockWeatherService(),
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

        let range = try #require(viewModel.aiInsightCalendarDateRange)
        #expect(range.upperBound == yesterday)
        #expect(!range.contains(today))
    }

    @Test @MainActor
    func bootstrapMigratesLegacyHomeSectionsToShowDailyVideo() async {
        let today = Date().startOfDay
        let legacyPreferences = UserPreferences(
            visibleHomeSections: [.sleep, .meals, .showers],
            homeSectionSchemaVersion: 0
        )
        let preferencesStore = CapturingPreferencesStore(preferences: legacyPreferences)
        let viewModel = AppViewModel(
            authService: MockAuthService(user: nil),
            repository: InMemoryDailyRecordRepository(),
            preferencesStore: preferencesStore,
            photoStorageService: MockPhotoStorageService(),
            videoStorageService: MockVideoStorageService(),
            sunTimesService: MockSunTimesService(),
            weatherService: MockWeatherService(),
            healthSyncAdapter: MockHealthSyncAdapter(sleepRecord: nil),
            cloudSyncService: NoopCloudSyncService(),
            aiInsightNarrativeService: NoopAIInsightNarrativeService(),
            openAIKeyStore: MockOpenAIKeyStore(),
            locationService: LocationService(),
            selectedDate: today,
            dailyRecord: DailyRecord.empty(for: today, preferences: legacyPreferences),
            preferences: legacyPreferences
        )

        await viewModel.bootstrap()

        #expect(viewModel.preferences.visibleHomeSections.contains(.dailyVideo))
        #expect(viewModel.preferences.homeSectionSchemaVersion == UserPreferences.currentHomeSectionSchemaVersion)
        #expect(preferencesStore.savedPreferences?.visibleHomeSections.contains(.dailyVideo) == true)
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
        #expect(payload.timeline.count == 6)
        #expect(payload.scoringRubric.sampleCount == 5)
        #expect(payload.showerEnabled == false)
        #expect(payload.bowelMovementEnabled == false)
        #expect(payload.comparisonContext.trailing7Days.recordedDays == 0)
        #expect(payloadJSON.contains("\"overallScore\"") == false)
        #expect(payloadJSON.contains("\"scoreBreakdown\"") == false)
        #expect(payloadJSON.contains("\"localSummary\"") == false)
    }

    @Test
    func dailyInsightPayloadSeparatesTargetDayCountsFromHistory() throws {
        let day = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 21))!
        let priorDay = day.adding(days: -1)
        let preferences = UserPreferences(
            visibleHomeSections: [.sleep, .meals, .showers, .bowelMovements]
        )
        let record = DailyRecord(
            date: day,
            sleepRecord: SleepRecord(
                bedtimePreviousNight: day.adding(days: -1).settingTime(hour: 23, minute: 40),
                wakeTimeCurrentDay: day.settingTime(hour: 7, minute: 20),
                source: .manual
            ),
            meals: [
                MealEntry(mealKind: .breakfast, status: .logged, time: day.settingTime(hour: 8, minute: 0)),
                MealEntry(mealKind: .lunch, status: .logged, time: day.settingTime(hour: 12, minute: 30)),
                MealEntry(mealKind: .dinner, status: .logged, time: day.settingTime(hour: 19, minute: 0))
            ],
            showers: [],
            bowelMovements: [],
            sexualActivities: [],
            sunTimes: nil
        )
        let historicalRecord = DailyRecord(
            date: priorDay,
            sleepRecord: SleepRecord(
                bedtimePreviousNight: priorDay.adding(days: -1).settingTime(hour: 23, minute: 35),
                wakeTimeCurrentDay: priorDay.settingTime(hour: 7, minute: 15),
                source: .manual
            ),
            meals: [
                MealEntry(mealKind: .breakfast, status: .logged, time: priorDay.settingTime(hour: 8, minute: 0)),
                MealEntry(mealKind: .lunch, status: .logged, time: priorDay.settingTime(hour: 12, minute: 15)),
                MealEntry(mealKind: .dinner, status: .logged, time: priorDay.settingTime(hour: 19, minute: 15))
            ],
            showers: [ShowerEntry(time: priorDay.settingTime(hour: 21, minute: 0))],
            bowelMovements: [BowelMovementEntry(time: priorDay.settingTime(hour: 7, minute: 45))],
            sexualActivities: [],
            sunTimes: nil
        )

        let payload = DailyInsightAnalyzer.makePayload(
            record: record,
            preferences: preferences,
            language: .zhHans,
            locale: Locale(identifier: "zh-Hans"),
            history: [historicalRecord, record]
        )

        #expect(payload.targetDay.showerCount == 0)
        #expect(payload.targetDay.hasShowerRecord == false)
        #expect(payload.showers.isEmpty)
        #expect(payload.comparisonContext.trailing7Days.showerCount.average == 1)
        #expect(payload.comparisonContext.dailySnapshots.map(\.date) == [priorDay.storageKey()])
    }

    @Test
    func dailyInsightPayloadSignatureIsStableAcrossLanguages() throws {
        let day = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 20))!
        let preferences = UserPreferences(
            appLanguage: .en,
            visibleHomeSections: [.sleep, .meals, .showers]
        )
        let record = DailyRecord(
            date: day,
            sleepRecord: SleepRecord(
                bedtimePreviousNight: day.adding(days: -1).settingTime(hour: 0, minute: 5),
                wakeTimeCurrentDay: day.settingTime(hour: 7, minute: 10),
                source: .manual
            ),
            meals: [
                MealEntry(mealKind: .breakfast, status: .logged, time: day.settingTime(hour: 8, minute: 0)),
                MealEntry(mealKind: .lunch, status: .logged),
                MealEntry(mealKind: .dinner, status: .skipped)
            ],
            showers: [ShowerEntry(time: day.settingTime(hour: 21, minute: 0))],
            bowelMovements: [],
            sexualActivities: [],
            sunTimes: nil
        )

        let zhPayload = DailyInsightAnalyzer.makePayload(
            record: record,
            preferences: preferences,
            language: .zhHans,
            locale: Locale(identifier: "zh-Hans"),
            history: [record]
        )
        let enPayload = DailyInsightAnalyzer.makePayload(
            record: record,
            preferences: preferences,
            language: .en,
            locale: Locale(identifier: "en_US"),
            history: [record]
        )

        #expect(try zhPayload.stableSignature() == enPayload.stableSignature())
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
        let repository = InMemoryDailyRecordRepository(records: [yesterday.storageKey(): record])
        let viewModel = AppViewModel(
            authService: MockAuthService(user: user),
            repository: repository,
            preferencesStore: MockPreferencesStore(preferences: preferences),
            photoStorageService: MockPhotoStorageService(),
            videoStorageService: MockVideoStorageService(),
            sunTimesService: MockSunTimesService(),
            weatherService: MockWeatherService(),
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
    func refreshDailyInsightNarrativeUsesPersistedNarrativeWithoutRegeneratingScores() async {
        let originalLanguage = AppViewModel.persistedProcessLanguage()
        defer { restorePersistedProcessLanguage(originalLanguage) }
        AppViewModel.applyProcessLocale(.zhHans)

        let today = Date().startOfDay
        let yesterday = today.adding(days: -1)
        let recordedTimeZone = TimeZone.autoupdatingCurrent.identifier
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
            ],
            scoringVersion: DailyInsightNarrative.currentScoringVersion,
            sampleCount: 5
        )
        let unsignedRecord = DailyRecord(
            date: yesterday,
            sleepRecord: SleepRecord(
                bedtimePreviousNight: yesterday.adding(days: -1).settingTime(hour: 23, minute: 20),
                wakeTimeCurrentDay: yesterday.settingTime(hour: 7, minute: 15),
                source: .manual,
                timeZoneIdentifier: recordedTimeZone
            ),
            meals: [
                MealEntry(
                    mealKind: .breakfast,
                    status: .logged,
                    time: yesterday.settingTime(hour: 8, minute: 0),
                    timeZoneIdentifier: recordedTimeZone
                )
            ],
            showers: [],
            bowelMovements: [],
            sexualActivities: [],
            sunTimes: nil,
            aiInsightNarrative: persistedNarrative
        )
        let mergedRecordForSignature = DailyRecord(
            date: unsignedRecord.date,
            sleepRecord: SleepRecord(
                bedtimePreviousNight: unsignedRecord.sleepRecord.bedtimePreviousNight,
                wakeTimeCurrentDay: unsignedRecord.sleepRecord.wakeTimeCurrentDay,
                targetBedtime: preferences.bedtimeSchedule.target(for: unsignedRecord.date),
                source: unsignedRecord.sleepRecord.source,
                timeZoneIdentifier: recordedTimeZone
            ),
            meals: [
                unsignedRecord.meals[0],
                MealEntry(mealKind: .lunch, status: .empty),
                MealEntry(mealKind: .dinner, status: .empty)
            ],
            showers: unsignedRecord.showers,
            bowelMovements: unsignedRecord.bowelMovements,
            sexualActivities: unsignedRecord.sexualActivities,
            sunTimes: unsignedRecord.sunTimes,
            aiInsightNarrative: persistedNarrative
        )
        let payload = DailyInsightAnalyzer.makePayload(
            record: mergedRecordForSignature,
            preferences: preferences,
            language: .zhHans,
            locale: Locale(identifier: "zh-Hans"),
            history: [mergedRecordForSignature]
        )
        let signature = try! payload.stableSignature()
        var signedNarrative = persistedNarrative
        signedNarrative.payloadSignature = signature
        let record = DailyRecord(
            date: unsignedRecord.date,
            sleepRecord: unsignedRecord.sleepRecord,
            meals: unsignedRecord.meals,
            showers: unsignedRecord.showers,
            bowelMovements: unsignedRecord.bowelMovements,
            sexualActivities: unsignedRecord.sexualActivities,
            sunTimes: unsignedRecord.sunTimes,
            aiInsightNarrative: signedNarrative
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
        ], translationResponses: [
            DailyInsightNarrative.LocalizedText(
                headline: "Cached AI",
                summary: "Direct cache hit",
                bullets: ["cached bullet 1", "cached bullet 2"]
            )
        ])
        let viewModel = AppViewModel(
            authService: MockAuthService(user: user),
            repository: InMemoryDailyRecordRepository(records: [yesterday.storageKey(): record]),
            preferencesStore: MockPreferencesStore(preferences: preferences),
            photoStorageService: MockPhotoStorageService(),
            videoStorageService: MockVideoStorageService(),
            sunTimesService: MockSunTimesService(),
            weatherService: MockWeatherService(),
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
        #expect(aiService.translationCallCount == 1)
        #expect(viewModel.activeDailyInsightNarrative?.headline == "已缓存的 AI")
        #expect(viewModel.displayedDailyInsightReport?.overallScore == 90)
    }

    @Test @MainActor
    func dailyInsightLanguageSwitchUsesCachedScoreAndStoredTranslation() async {
        let originalLanguage = AppViewModel.persistedProcessLanguage()
        defer { restorePersistedProcessLanguage(originalLanguage) }
        AppViewModel.applyProcessLocale(.zhHans)

        let today = Date().startOfDay
        let yesterday = today.adding(days: -1)
        var preferences = UserPreferences(
            healthKitSyncEnabled: false,
            visibleHomeSections: [.sleep, .meals, .showers]
        )
        preferences.appLanguage = .zhHans
        let user = UserAccount(
            userID: "language-switch-user",
            displayName: "Tester",
            email: nil,
            authMode: .guest,
            createdAt: today.adding(days: -30)
        )
        let record = DailyRecord(
            date: yesterday,
            sleepRecord: SleepRecord(
                bedtimePreviousNight: yesterday.adding(days: -1).settingTime(hour: 23, minute: 20),
                wakeTimeCurrentDay: yesterday.settingTime(hour: 7, minute: 15),
                source: .manual,
                timeZoneIdentifier: TimeZone.autoupdatingCurrent.identifier
            ),
            meals: [
                MealEntry(
                    mealKind: .breakfast,
                    status: .logged,
                    time: yesterday.settingTime(hour: 8, minute: 0),
                    timeZoneIdentifier: TimeZone.autoupdatingCurrent.identifier
                )
            ],
            showers: [],
            bowelMovements: [],
            sexualActivities: [],
            sunTimes: nil
        )
        let aiService = MockAIInsightNarrativeService(
            responses: [sampleAINarrative(headline: "中文版评分", overallScore: 84)],
            translationResponses: [
                DailyInsightNarrative.LocalizedText(
                    headline: "English score",
                    summary: "English summary",
                    bullets: ["English bullet 1", "English bullet 2"]
                )
            ]
        )
        let repository = InMemoryDailyRecordRepository(records: [yesterday.storageKey(): record])
        let viewModel = AppViewModel(
            authService: MockAuthService(user: user),
            repository: repository,
            preferencesStore: MockPreferencesStore(preferences: preferences),
            photoStorageService: MockPhotoStorageService(),
            videoStorageService: MockVideoStorageService(),
            sunTimesService: MockSunTimesService(),
            weatherService: MockWeatherService(),
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
        #expect(aiService.callCount == 1)
        #expect(aiService.translationCallCount == 1)
        #expect(viewModel.activeDailyInsightNarrative?.headline == "中文版评分")

        await viewModel.updateAppLanguage(.en)
        await viewModel.refreshDailyInsightNarrative()
        #expect(aiService.callCount == 1)
        #expect(aiService.translationCallCount == 1)
        #expect(viewModel.activeDailyInsightNarrative?.headline == "English score")

        await viewModel.updateAppLanguage(.zhHans)
        await viewModel.refreshDailyInsightNarrative()
        #expect(aiService.callCount == 1)
        #expect(aiService.translationCallCount == 1)
        #expect(viewModel.activeDailyInsightNarrative?.headline == "中文版评分")
    }

    @Test @MainActor
    func refreshDailyInsightNarrativeRegeneratesWhenPersistedSignatureIsStale() async {
        let today = Date().startOfDay
        let yesterday = today.adding(days: -1)
        let preferences = UserPreferences(
            healthKitSyncEnabled: false,
            visibleHomeSections: [.sleep, .meals, .showers]
        )
        let user = UserAccount(
            userID: "stale-ai-user",
            displayName: "Tester",
            email: nil,
            authMode: .guest,
            createdAt: today.adding(days: -30)
        )
        let staleNarrative = DailyInsightNarrative(
            headline: "旧评分",
            summary: "签名已经过期",
            bullets: ["旧 1", "旧 2"],
            overallScore: 77,
            components: [
                "sleep": .init(score: 78, maxScore: 100, detail: "旧睡眠", included: true),
                "meals": .init(score: 75, maxScore: 100, detail: "旧餐食", included: true),
                "shower": .init(score: 70, maxScore: 100, detail: "旧洗澡", included: true),
                "bowelMovement": .init(score: 0, maxScore: 100, detail: "旧排便", included: false)
            ],
            scoringVersion: DailyInsightNarrative.currentScoringVersion,
            sampleCount: 5,
            payloadSignature: "stale-signature"
        )
        let record = DailyRecord(
            date: yesterday,
            sleepRecord: SleepRecord(
                bedtimePreviousNight: yesterday.adding(days: -1).settingTime(hour: 23, minute: 50),
                wakeTimeCurrentDay: yesterday.settingTime(hour: 8, minute: 10),
                source: .manual
            ),
            meals: [MealEntry(mealKind: .breakfast, status: .logged, time: yesterday.settingTime(hour: 8, minute: 40))],
            showers: [],
            bowelMovements: [],
            sexualActivities: [],
            sunTimes: nil,
            aiInsightNarrative: staleNarrative
        )
        let aiService = MockAIInsightNarrativeService(responses: [
            DailyInsightNarrative(
                headline: "新评分",
                summary: "已按新签名重新生成",
                bullets: ["新 1", "新 2"],
                overallScore: 85,
                components: [
                    "sleep": .init(score: 87, maxScore: 100, detail: "新睡眠", included: true),
                    "meals": .init(score: 84, maxScore: 100, detail: "新餐食", included: true),
                    "shower": .init(score: 78, maxScore: 100, detail: "新洗澡", included: true),
                    "bowelMovement": .init(score: 0, maxScore: 100, detail: "新排便", included: false)
                ]
            )
        ])
        let viewModel = AppViewModel(
            authService: MockAuthService(user: user),
            repository: InMemoryDailyRecordRepository(records: [yesterday.storageKey(): record]),
            preferencesStore: MockPreferencesStore(preferences: preferences),
            photoStorageService: MockPhotoStorageService(),
            videoStorageService: MockVideoStorageService(),
            sunTimesService: MockSunTimesService(),
            weatherService: MockWeatherService(),
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

        #expect(aiService.callCount == 1)
        #expect(viewModel.activeDailyInsightNarrative?.headline == "新评分")
        #expect(viewModel.displayedDailyInsightReport?.overallScore == 85)
    }

    @Test
    func openAIResponsesInsightServiceParsesDirectJSONResponse() async throws {
        let payload = sampleInsightPayload()
        let narrative = sampleAINarrative(headline: "直接 JSON", overallScore: 88)
        let data = try JSONEncoder().encode(narrative)
        let session = makeMockSession(responseData: data)
        let service = OpenAIResponsesInsightService(
            keyStore: MockOpenAIKeyStore(key: "test-key"),
            session: session,
            model: "gpt-5.4-mini"
        )

        let resolved = try await service.generateNarrative(from: payload)

        #expect(resolved.headline == "直接 JSON")
        #expect(resolved.overallScore == 88)
        #expect(resolved.sampleCount == 5)
    }

    @Test
    func openAIResponsesInsightServiceParsesStructuredParsedContent() async throws {
        let payload = sampleInsightPayload()
        let narrative = sampleAINarrative(headline: "结构化 parsed", overallScore: 91)
        let envelope = ParsedNarrativeEnvelope(
            output: [
                .init(content: [
                    .init(type: "output_text", text: nil, parsed: narrative)
                ])
            ]
        )
        let data = try JSONEncoder().encode(envelope)
        let session = makeMockSession(responseData: data)
        let service = OpenAIResponsesInsightService(
            keyStore: MockOpenAIKeyStore(key: "test-key"),
            session: session,
            model: "gpt-5.4-mini"
        )

        let resolved = try await service.generateNarrative(from: payload)

        #expect(resolved.headline == "结构化 parsed")
        #expect(resolved.overallScore == 91)
        #expect(resolved.sampleCount == 5)
    }

    @Test
    func openAIResponsesInsightServiceSurfacesUpstreamProviderMessage() async {
        let payload = sampleInsightPayload()
        let data = """
        {
          "error": {
            "message": "Rate limit reached for gpt-5.4-mini.",
            "type": "rate_limit_error",
            "code": "rate_limit_exceeded"
          }
        }
        """.data(using: .utf8)!
        let session = makeMockSession(responseData: data, statusCode: 429)
        let service = OpenAIResponsesInsightService(
            keyStore: MockOpenAIKeyStore(key: "test-key"),
            session: session,
            model: "gpt-5.4-mini"
        )

        do {
            _ = try await service.generateNarrative(from: payload)
            Issue.record("Expected provider error to be thrown.")
        } catch {
            #expect(error.localizedDescription == "Rate limit reached for gpt-5.4-mini.")
        }
    }

    @Test
    func cloudAIInsightServiceSurfacesDailyLimitError() async {
        let payload = sampleInsightPayload()
        let data = """
        {
          "error": "daily_limit_reached",
          "limit": 5,
          "dateKey": "2026-04-20"
        }
        """.data(using: .utf8)!
        let session = makeMockSession(responseData: data, statusCode: 429)
        let service = CloudAIInsightService(
            configuration: AIProxyConfiguration(endpointURL: URL(string: "https://example.com/proxy")),
            session: session,
            model: "gpt-5.4-mini",
            authTokenProvider: { "mock-token" }
        )

        do {
            _ = try await service.generateNarrative(from: payload)
            Issue.record("Expected daily limit error to be thrown.")
        } catch {
            guard case let AIInsightServiceError.dailyLimitReached(limit) = error else {
                Issue.record("Expected daily limit error, got: \(error)")
                return
            }
            #expect(limit == 5)
        }
    }

    @Test
    func cloudAIInsightServiceSurfacesUpstreamTimeoutError() async {
        let payload = sampleInsightPayload()
        let data = """
        {
          "error": "openai_upstream_timeout",
          "timeoutMs": 55000
        }
        """.data(using: .utf8)!
        let session = makeMockSession(responseData: data, statusCode: 504)
        let service = CloudAIInsightService(
            configuration: AIProxyConfiguration(endpointURL: URL(string: "https://example.com/proxy")),
            session: session,
            model: "gpt-5.4-mini",
            authTokenProvider: { "mock-token" }
        )

        do {
            _ = try await service.generateNarrative(from: payload)
            Issue.record("Expected upstream timeout error to be thrown.")
        } catch {
            #expect(error.localizedDescription == "云端 AI 响应超时，请稍后重试。")
        }
    }

    @Test @MainActor
    func refreshDailyInsightNarrativeForceBypassesValidNarrativeCache() async {
        let today = Date().startOfDay
        let yesterday = today.adding(days: -1)
        let preferences = UserPreferences(
            healthKitSyncEnabled: false,
            visibleHomeSections: [.sleep, .meals, .showers]
        )
        let user = UserAccount(
            userID: "force-ai-user",
            displayName: "Tester",
            email: nil,
            authMode: .guest,
            createdAt: today.adding(days: -30)
        )
        let record = DailyRecord(
            date: yesterday,
            sleepRecord: SleepRecord(
                bedtimePreviousNight: yesterday.adding(days: -1).settingTime(hour: 23, minute: 50),
                wakeTimeCurrentDay: yesterday.settingTime(hour: 7, minute: 15),
                source: .manual
            ),
            meals: [
                MealEntry(mealKind: .breakfast, status: .logged, time: yesterday.settingTime(hour: 8, minute: 15))
            ],
            showers: [],
            bowelMovements: [],
            sexualActivities: [],
            sunTimes: nil
        )
        let aiService = MockAIInsightNarrativeService(responses: [
            sampleAINarrative(headline: "第一次", overallScore: 81),
            sampleAINarrative(headline: "第二次", overallScore: 86)
        ])
        let viewModel = AppViewModel(
            authService: MockAuthService(user: user),
            repository: InMemoryDailyRecordRepository(records: [yesterday.storageKey(): record]),
            preferencesStore: MockPreferencesStore(preferences: preferences),
            photoStorageService: MockPhotoStorageService(),
            videoStorageService: MockVideoStorageService(),
            sunTimesService: MockSunTimesService(),
            weatherService: MockWeatherService(),
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
        #expect(aiService.callCount == 1)
        #expect(viewModel.activeDailyInsightNarrative?.headline == "第一次")

        await viewModel.refreshDailyInsightNarrative(force: true)

        #expect(aiService.callCount == 2)
        #expect(viewModel.activeDailyInsightNarrative?.headline == "第二次")
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
            videoStorageService: MockVideoStorageService(),
            sunTimesService: MockSunTimesService(),
            weatherService: MockWeatherService(),
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

        let deduplicated = AppViewModel.recordsByStorageKey([sparseRecord, richerRecord], preferences: UserPreferences())
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

        let deduplicated = AppViewModel.recordsByStorageKey([olderRecord, newerRecord], preferences: UserPreferences())
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
    func recordsByStorageKeyMergesOlderTravelEntriesIntoNewerArrivalRecord() {
        let day = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 7))!
        let planID = UUID()
        let segmentID = UUID()
        let travelContext = TravelRecordContext(planID: planID, segmentID: segmentID, phase: .inFlight)
        let travelMeal = MealEntry(
            mealKind: .custom,
            customTitle: "飞机餐",
            status: .logged,
            time: day.settingTime(hour: 13, minute: 20),
            timeZoneIdentifier: TimeZone.autoupdatingCurrent.identifier,
            travelContext: travelContext
        )
        let travelShower = ShowerEntry(
            time: day.settingTime(hour: 15, minute: 5),
            timeZoneIdentifier: TimeZone.autoupdatingCurrent.identifier,
            travelContext: travelContext
        )
        let travelBowelMovement = BowelMovementEntry(
            time: day.settingTime(hour: 16, minute: 40),
            timeZoneIdentifier: TimeZone.autoupdatingCurrent.identifier,
            travelContext: travelContext
        )

        let olderTravelRecord = DailyRecord(
            date: day,
            sleepRecord: SleepRecord(),
            meals: [travelMeal],
            showers: [travelShower],
            bowelMovements: [travelBowelMovement],
            sexualActivities: [],
            modifiedAt: day.settingTime(hour: 17, minute: 0)
        )
        let arrivalMeal = MealEntry(
            mealKind: .custom,
            customTitle: "JFK transfer",
            status: .logged,
            time: day.settingTime(hour: 20, minute: 10),
            timeZoneIdentifier: TimeZone.autoupdatingCurrent.identifier
        )
        let newerArrivalRecord = DailyRecord(
            date: day,
            sleepRecord: SleepRecord(),
            meals: [arrivalMeal],
            showers: [],
            bowelMovements: [],
            sexualActivities: [],
            modifiedAt: day.settingTime(hour: 21, minute: 0)
        )

        let deduplicated = AppViewModel.recordsByStorageKey(
            [olderTravelRecord, newerArrivalRecord],
            preferences: UserPreferences()
        )
        let merged = deduplicated[day.storageKey()]

        #expect(merged?.meals.contains { $0.id == travelMeal.id } == true)
        #expect(merged?.meals.contains { $0.id == arrivalMeal.id } == true)
        #expect(merged?.showers.contains { $0.id == travelShower.id } == true)
        #expect(merged?.bowelMovements.contains { $0.id == travelBowelMovement.id } == true)
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
        let deduplicated = AppViewModel.recordsByStorageKey([shiftedRecord, duplicate], preferences: UserPreferences())

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
    func userPreferencesStorageKeyUsesRecordedTimeZoneWhenFormatting() {
        let formatter = ISO8601DateFormatter()
        let preferences = UserPreferences()
        let londonTimestamp = formatter.date(from: "2026-03-27T07:20:00Z")!

        let key = preferences.storageKey(
            for: londonTimestamp,
            timeZoneIdentifier: "Europe/London",
            fallbackTimeZone: TimeZone(identifier: "America/New_York")!
        )

        #expect(key == "2026-03-27")
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

        let loaded = try repository.loadAllRecords(userID: userID, preferences: UserPreferences())

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
            videoStorageService: MockVideoStorageService(),
            sunTimesService: MockSunTimesService(),
            weatherService: MockWeatherService(),
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
            videoStorageService: MockVideoStorageService(),
            sunTimesService: MockSunTimesService(),
            weatherService: MockWeatherService(),
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
    func cloudRecordReconciliationDoesNotRestoreLocallyRemovedMealPhoto() {
        let today = Date().startOfDay
        let mealID = UUID()
        let securePhoto = SecureCloudPhotoReference.make(
            bucket: "dailylogs.appspot.com",
            path: "users/test-user/secure-meal-photos/\(mealID.uuidString)-0.bin"
        )

        var localRecord = DailyRecord.empty(for: today, preferences: UserPreferences())
        localRecord.meals[0].id = mealID
        localRecord.meals[0].status = .empty
        localRecord.meals[0].photoURLs = []
        localRecord.modifiedAt = today.settingTime(hour: 12, minute: 0)

        var remoteRecord = localRecord
        remoteRecord.meals[0].status = .logged
        remoteRecord.meals[0].photoURLs = [securePhoto]
        remoteRecord.modifiedAt = today.settingTime(hour: 11, minute: 0)

        let result = AppViewModel.reconcileCloudRecord(localRecord: localRecord, remoteRecord: remoteRecord)

        #expect(result.record.meals[0].photoURLs.isEmpty)
        #expect(result.record.meals[0].status == .empty)
        #expect(result.discardedRemotePhotoReferences == Set([securePhoto]))
        #expect(result.shouldPushRecord)
    }

    @Test @MainActor
    func cloudRecordReconciliationKeepsRemotePhotoWhenLocalFileIsMissing() {
        let today = Date().startOfDay
        let mealID = UUID()
        let securePhoto = SecureCloudPhotoReference.make(
            bucket: "dailylogs.appspot.com",
            path: "users/test-user/secure-meal-photos/\(mealID.uuidString)-0.bin"
        )

        var localRecord = DailyRecord.empty(for: today, preferences: UserPreferences())
        localRecord.meals[0].id = mealID
        localRecord.meals[0].status = .logged
        localRecord.meals[0].photoURLs = ["/tmp/missing-\(UUID().uuidString).jpg"]
        localRecord.modifiedAt = today.settingTime(hour: 12, minute: 0)

        var remoteRecord = localRecord
        remoteRecord.meals[0].photoURLs = [securePhoto]
        remoteRecord.modifiedAt = today.settingTime(hour: 11, minute: 0)

        let result = AppViewModel.reconcileCloudRecord(localRecord: localRecord, remoteRecord: remoteRecord)

        #expect(result.record.meals[0].photoURLs == [securePhoto])
        #expect(result.discardedRemotePhotoReferences.isEmpty)
        #expect(result.shouldPushRecord)
    }

    @Test @MainActor
    func deleteMealRemovesRemotePhotoReferenceBeforePushingRecord() async throws {
        let today = Date().startOfDay
        let mealID = UUID()
        let securePhoto = SecureCloudPhotoReference.make(
            bucket: "dailylogs.appspot.com",
            path: "users/test-user/secure-meal-photos/\(mealID.uuidString)-0.bin"
        )
        let meal = MealEntry(
            id: mealID,
            mealKind: .custom,
            customTitle: "夜宵",
            status: .logged,
            time: today.settingTime(hour: 22, minute: 15),
            photoURLs: [securePhoto]
        )
        var record = DailyRecord.empty(for: today, preferences: UserPreferences())
        record.meals.append(meal)

        let user = UserAccount(
            userID: "remote-photo-delete-user",
            displayName: "Tester",
            email: nil,
            authMode: .apple,
            createdAt: today.adding(days: -30)
        )
        let cloudSyncService = RecordingCloudSyncService()
        let viewModel = AppViewModel(
            authService: MockAuthService(user: user),
            repository: InMemoryDailyRecordRepository(records: [today.storageKey(): record]),
            preferencesStore: MockPreferencesStore(preferences: UserPreferences()),
            photoStorageService: MockPhotoStorageService(),
            videoStorageService: MockVideoStorageService(),
            sunTimesService: MockSunTimesService(),
            weatherService: MockWeatherService(),
            healthSyncAdapter: MockHealthSyncAdapter(sleepRecord: nil),
            cloudSyncService: cloudSyncService,
            aiInsightNarrativeService: NoopAIInsightNarrativeService(),
            openAIKeyStore: MockOpenAIKeyStore(),
            locationService: LocationService(),
            selectedDate: today,
            dailyRecord: DailyRecord.empty(for: today, preferences: UserPreferences()),
            preferences: UserPreferences()
        )

        await viewModel.bootstrap()
        await viewModel.deleteMeal(meal)

        let deletedPhotoReferences = await cloudSyncService.deletedPhotoReferences()
        let pushedRecords = await cloudSyncService.pushedRecords()
        let lastPushedRecord = try #require(pushedRecords.last)

        #expect(deletedPhotoReferences == [securePhoto])
        #expect(viewModel.dailyRecord.meals.contains(where: { $0.id == mealID }) == false)
        #expect(lastPushedRecord.meals.contains(where: { $0.id == mealID }) == false)
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
            videoStorageService: MockVideoStorageService(),
            sunTimesService: MockSunTimesService(),
            weatherService: MockWeatherService(),
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
    func travelCustomMealsWithSameDefaultTitleDoNotReplaceEachOther() async {
        let today = Date().startOfDay
        let segment = TravelSegment(
            flightNumber: "DL001",
            originCode: "BOS",
            destinationCode: "LHR",
            plannedDepartureTime: today.settingTime(hour: 10, minute: 0),
            plannedArrivalTime: today.settingTime(hour: 20, minute: 0),
            departureTimeZoneIdentifier: TimeZone.autoupdatingCurrent.identifier,
            arrivalTimeZoneIdentifier: TimeZone.autoupdatingCurrent.identifier
        )
        let plan = TravelPlan(
            title: "BOS-LHR",
            segments: [segment],
            status: .inFlight,
            currentSegmentID: segment.id
        )
        let user = UserAccount(
            userID: "travel-meal-user",
            displayName: "Tester",
            email: nil,
            authMode: .guest,
            createdAt: today.adding(days: -30)
        )
        let viewModel = AppViewModel(
            authService: MockAuthService(user: user),
            repository: InMemoryDailyRecordRepository(records: [today.storageKey(): DailyRecord.empty(for: today, preferences: UserPreferences())]),
            travelPlanRepository: InMemoryTravelPlanRepository(plans: [plan]),
            preferencesStore: MockPreferencesStore(preferences: UserPreferences()),
            photoStorageService: MockPhotoStorageService(),
            videoStorageService: MockVideoStorageService(),
            sunTimesService: MockSunTimesService(),
            weatherService: MockWeatherService(),
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

        await viewModel.saveMeal(MealEntry(
            mealKind: .custom,
            customTitle: "飞机餐",
            status: .logged,
            time: today.settingTime(hour: 11, minute: 20),
            photoURLs: ["/tmp/plane-meal-1.jpg"]
        ), images: [])
        await viewModel.saveMeal(MealEntry(
            mealKind: .custom,
            customTitle: "飞机餐",
            status: .logged,
            time: today.settingTime(hour: 13, minute: 10),
            photoURLs: ["/tmp/plane-meal-2.jpg"]
        ), images: [])

        let planeMeals = viewModel.dailyRecord.meals.filter { $0.customTitle == "飞机餐" }
        #expect(planeMeals.count == 2)
        #expect(Set(planeMeals.flatMap(\.photoURLs)) == Set(["/tmp/plane-meal-1.jpg", "/tmp/plane-meal-2.jpg"]))
        #expect(planeMeals.allSatisfy { $0.travelContext?.planID == plan.id })
    }

    @Test @MainActor
    func saveDailyVideoReplacesExistingVideoAndDeleteRemovesIt() async {
        let today = Date().startOfDay
        var existingRecord = DailyRecord.empty(for: today, preferences: UserPreferences())
        existingRecord.dailyVideo = DailyVideoEntry(
            videoURL: "/tmp/old-daily-video.mp4",
            duration: 10,
            createdAt: today
        )

        let user = UserAccount(
            userID: "video-user",
            displayName: "Tester",
            email: nil,
            authMode: .guest,
            createdAt: today.adding(days: -30)
        )
        let videoStorageService = TrackingVideoStorageService()
        let viewModel = AppViewModel(
            authService: MockAuthService(user: user),
            repository: InMemoryDailyRecordRepository(records: [today.storageKey(): existingRecord]),
            preferencesStore: MockPreferencesStore(preferences: UserPreferences()),
            photoStorageService: MockPhotoStorageService(),
            videoStorageService: videoStorageService,
            sunTimesService: MockSunTimesService(),
            weatherService: MockWeatherService(),
            healthSyncAdapter: MockHealthSyncAdapter(sleepRecord: nil),
            cloudSyncService: NoopCloudSyncService(),
            aiInsightNarrativeService: NoopAIInsightNarrativeService(),
            openAIKeyStore: MockOpenAIKeyStore(),
            locationService: LocationService(),
            selectedDate: today,
            dailyRecord: existingRecord,
            preferences: UserPreferences()
        )

        await viewModel.saveDailyVideo(
            from: URL(fileURLWithPath: "/tmp/source-video.mov"),
            duration: 12.7
        )

        #expect(viewModel.dailyRecord.dailyVideo?.videoURL == "/tmp/mock-daily-video-1.mp4")
        #expect(viewModel.dailyRecord.dailyVideo?.duration == 10)
        #expect(videoStorageService.deletedPaths == ["/tmp/old-daily-video.mp4"])

        await viewModel.deleteDailyVideo()

        #expect(viewModel.dailyRecord.dailyVideo == nil)
        #expect(videoStorageService.deletedPaths == [
            "/tmp/old-daily-video.mp4",
            "/tmp/mock-daily-video-1.mp4"
        ])
    }

    @Test
    func localVideoStorageResolvesStaleContainerPathByFilename() throws {
        let fileManager = FileManager.default
        let service = LocalVideoStorageService()
        let sourceURL = fileManager.temporaryDirectory
            .appendingPathComponent("daily-video-source-\(UUID().uuidString).mp4")
        try Data([0, 1, 2, 3]).write(to: sourceURL, options: .atomic)
        defer { try? fileManager.removeItem(at: sourceURL) }

        let reference = try service.saveVideo(from: sourceURL)
        let resolvedURL = try #require(LocalVideoStorageService.resolvedURL(for: reference))
        let staleContainerPath = "/private/var/mobile/Containers/Data/Application/OLD-CONTAINER/Library/Application Support/DailyLogs/Videos/\(resolvedURL.lastPathComponent)"

        let recoveredURL = try #require(LocalVideoStorageService.resolvedURL(for: staleContainerPath))
        #expect(recoveredURL == resolvedURL)

        try service.deleteVideo(at: reference)
        #expect(LocalVideoStorageService.resolvedURL(for: reference) == nil)
    }

    @Test
    func localPhotoStorageResolvesStaleContainerPathByFilename() throws {
        let service = LocalPhotoStorageService()
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }

        let reference = try service.savePhoto(image)
        let resolvedURL = try #require(LocalPhotoStorageService.resolvedURL(for: reference))
        let staleContainerPath = "/private/var/mobile/Containers/Data/Application/OLD-CONTAINER/Library/Application Support/DailyLogs/Photos/\(resolvedURL.lastPathComponent)"

        let recoveredURL = try #require(LocalPhotoStorageService.resolvedURL(for: staleContainerPath))
        #expect(recoveredURL == resolvedURL)

        try service.deletePhoto(at: reference)
        #expect(LocalPhotoStorageService.resolvedURL(for: reference) == nil)
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
            videoStorageService: MockVideoStorageService(),
            sunTimesService: MockSunTimesService(),
            weatherService: MockWeatherService(),
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
            videoStorageService: MockVideoStorageService(),
            sunTimesService: MockSunTimesService(),
            weatherService: MockWeatherService(),
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
            videoStorageService: MockVideoStorageService(),
            sunTimesService: MockSunTimesService(),
            weatherService: MockWeatherService(),
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

    @Test @MainActor
    func healthKitSleepOverlappingTravelWindowIsIgnored() async {
        let today = Date().startOfDay
        let travelDay = today.adding(days: -1)
        let segment = TravelSegment(
            flightNumber: "UA001",
            originCode: "SFO",
            destinationCode: "HND",
            plannedDepartureTime: travelDay.settingTime(hour: 9, minute: 0),
            plannedArrivalTime: travelDay.settingTime(hour: 21, minute: 0),
            departureTimeZoneIdentifier: TimeZone.autoupdatingCurrent.identifier,
            arrivalTimeZoneIdentifier: TimeZone.autoupdatingCurrent.identifier
        )
        let plan = TravelPlan(
            title: "SFO-HND",
            segments: [segment],
            status: .inFlight,
            currentSegmentID: segment.id
        )
        let healthKitSleep = SleepRecord(
            bedtimePreviousNight: travelDay.settingTime(hour: 11, minute: 0),
            wakeTimeCurrentDay: travelDay.settingTime(hour: 13, minute: 0),
            source: .healthKit
        )
        let healthSyncAdapter = MockHealthSyncAdapter(sleepRecord: healthKitSleep)
        let preferences = UserPreferences(healthKitSyncEnabled: true)
        let user = UserAccount(
            userID: "travel-health-user",
            displayName: "Tester",
            email: nil,
            authMode: .guest,
            createdAt: today.adding(days: -30)
        )
        let viewModel = AppViewModel(
            authService: MockAuthService(user: user),
            repository: InMemoryDailyRecordRepository(records: [travelDay.storageKey(): DailyRecord.empty(for: travelDay, preferences: preferences)]),
            travelPlanRepository: InMemoryTravelPlanRepository(plans: [plan]),
            preferencesStore: MockPreferencesStore(preferences: preferences),
            photoStorageService: MockPhotoStorageService(),
            videoStorageService: MockVideoStorageService(),
            sunTimesService: MockSunTimesService(),
            weatherService: MockWeatherService(),
            healthSyncAdapter: healthSyncAdapter,
            cloudSyncService: NoopCloudSyncService(),
            aiInsightNarrativeService: NoopAIInsightNarrativeService(),
            openAIKeyStore: MockOpenAIKeyStore(),
            locationService: LocationService(),
            selectedDate: travelDay,
            dailyRecord: DailyRecord.empty(for: travelDay, preferences: preferences),
            preferences: preferences
        )
        await viewModel.bootstrap()

        await viewModel.overwriteSleepWithHealthKit()

        #expect(healthSyncAdapter.fetchCount == 1)
        #expect(viewModel.dailyRecord.sleepRecord.hasSleepData == false)
    }

    @Test @MainActor
    func bootstrapKeepsStoredPastEnvironmentSnapshot() async {
        let today = Date().startOfDay
        let yesterday = today.adding(days: -1)
        let storedSunTimes = SunTimes(
            sunrise: yesterday.settingTime(hour: 6, minute: 31),
            sunset: yesterday.settingTime(hour: 19, minute: 42),
            timeZoneIdentifier: "America/New_York"
        )
        let storedWeather = WeatherSnapshot(
            conditionDescription: "Sunny",
            symbolName: "sun.max.fill",
            temperatureCelsius: 16,
            lowTemperatureCelsius: 12,
            highTemperatureCelsius: 21
        )
        let record = DailyRecord(
            date: yesterday,
            sleepRecord: SleepRecord(),
            meals: [],
            showers: [],
            bowelMovements: [],
            sexualActivities: [],
            locationName: "Boston",
            sunTimes: storedSunTimes,
            weatherSnapshot: storedWeather
        )
        let user = UserAccount(
            userID: "environment-user",
            displayName: "Tester",
            email: nil,
            authMode: .guest,
            createdAt: today.adding(days: -30)
        )
        let viewModel = AppViewModel(
            authService: MockAuthService(user: user),
            repository: InMemoryDailyRecordRepository(records: [yesterday.storageKey(): record]),
            preferencesStore: MockPreferencesStore(preferences: UserPreferences()),
            photoStorageService: MockPhotoStorageService(),
            videoStorageService: MockVideoStorageService(),
            sunTimesService: MockSunTimesService(snapshot: SunTimes(
                sunrise: yesterday.settingTime(hour: 5, minute: 0),
                sunset: yesterday.settingTime(hour: 21, minute: 0),
                timeZoneIdentifier: "America/Los_Angeles"
            )),
            weatherService: MockWeatherService(snapshot: WeatherSnapshot(
                conditionDescription: "Rain",
                symbolName: "cloud.rain.fill",
                temperatureCelsius: 5,
                lowTemperatureCelsius: 3,
                highTemperatureCelsius: 8
            )),
            healthSyncAdapter: MockHealthSyncAdapter(sleepRecord: nil),
            cloudSyncService: NoopCloudSyncService(),
            aiInsightNarrativeService: NoopAIInsightNarrativeService(),
            openAIKeyStore: MockOpenAIKeyStore(),
            locationService: LocationService(),
            selectedDate: yesterday,
            dailyRecord: DailyRecord.empty(for: yesterday, preferences: UserPreferences()),
            preferences: UserPreferences()
        )

        await viewModel.bootstrap()

        #expect(viewModel.dailyRecord.sunTimes == storedSunTimes)
        #expect(viewModel.currentLocationName == "Boston")
        #expect(viewModel.currentWeather == storedWeather)
        #expect(viewModel.currentWeatherSummary().contains("Sunny"))
    }

    @Test @MainActor
    func pastDatesWithoutStoredWeatherShowPlaceholder() async {
        let today = Date().startOfDay
        let yesterday = today.adding(days: -1)
        let user = UserAccount(
            userID: "environment-placeholder-user",
            displayName: "Tester",
            email: nil,
            authMode: .guest,
            createdAt: today.adding(days: -30)
        )
        let record = DailyRecord.empty(for: yesterday, preferences: UserPreferences())
        let viewModel = AppViewModel(
            authService: MockAuthService(user: user),
            repository: InMemoryDailyRecordRepository(records: [yesterday.storageKey(): record]),
            preferencesStore: MockPreferencesStore(preferences: UserPreferences()),
            photoStorageService: MockPhotoStorageService(),
            videoStorageService: MockVideoStorageService(),
            sunTimesService: MockSunTimesService(),
            weatherService: MockWeatherService(snapshot: WeatherSnapshot(
                conditionDescription: "Rain",
                symbolName: "cloud.rain.fill",
                temperatureCelsius: 5,
                lowTemperatureCelsius: 3,
                highTemperatureCelsius: 8
            )),
            healthSyncAdapter: MockHealthSyncAdapter(sleepRecord: nil),
            cloudSyncService: NoopCloudSyncService(),
            aiInsightNarrativeService: NoopAIInsightNarrativeService(),
            openAIKeyStore: MockOpenAIKeyStore(),
            locationService: LocationService(),
            selectedDate: yesterday,
            dailyRecord: DailyRecord.empty(for: yesterday, preferences: UserPreferences()),
            preferences: UserPreferences()
        )

        await viewModel.bootstrap()

        #expect(viewModel.currentWeather == nil)
        #expect(viewModel.currentWeatherSummary() == "--")
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

    @Test
    func mealEntryRoundTripPreservesAutomaticPhotoLocationState() throws {
        let original = MealEntry(
            mealKind: .dinner,
            status: .logged,
            locationName: "Tokyo Station",
            latitude: 35.6812,
            longitude: 139.7671,
            isLocationManuallyEdited: false
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MealEntry.self, from: data)

        #expect(decoded.locationName == original.locationName)
        #expect(decoded.latitude == original.latitude)
        #expect(decoded.longitude == original.longitude)
        #expect(decoded.isLocationManuallyEdited == false)
    }

    @Test
    func mealEntryTreatsLegacySavedLocationAsManualEdit() throws {
        let json = """
        {
          "mealKind": "breakfast",
          "status": "logged",
          "locationName": "Legacy Cafe",
          "latitude": 40.7128,
          "longitude": -74.0060
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(MealEntry.self, from: json)

        #expect(decoded.locationName == "Legacy Cafe")
        #expect(decoded.isLocationManuallyEdited == true)
    }

    @Test
    func travelPlanManualStateMachineDoesNotStoreActualTimes() throws {
        var plan = TravelPlan.sampleBOSPKX()
        let firstSegment = try #require(plan.segments.first)
        let secondSegment = try #require(plan.segments.dropFirst().first)
        let actualDeparture = firstSegment.plannedDepartureTime.addingTimeInterval(12 * 60)
        let actualArrival = firstSegment.plannedArrivalTime.addingTimeInterval(18 * 60)

        plan.advance(now: actualDeparture.addingTimeInterval(-30 * 60))
        #expect(plan.status == .preDeparture)
        #expect(plan.currentSegmentID == firstSegment.id)
        #expect(plan.segments.first?.actualDepartureTime == nil)

        plan.advance(now: actualDeparture)
        #expect(plan.status == .inFlight)
        #expect(plan.segments.first?.actualDepartureTime == nil)

        plan.advance(now: actualArrival)
        #expect(plan.status == .layover)
        #expect(plan.currentSegmentID == secondSegment.id)
        #expect(plan.segments.first?.actualArrivalTime == nil)

        plan.advance(now: secondSegment.plannedDepartureTime)
        #expect(plan.status == .inFlight)
        #expect(plan.currentSegmentID == secondSegment.id)
    }

    @Test @MainActor
    func arrivedTravelPlanRemainsActiveUntilCompleted() async throws {
        let today = Date().startOfDay
        let segment = TravelSegment(
            flightNumber: "AA001",
            originCode: "JFK",
            destinationCode: "MIA",
            plannedDepartureTime: today.settingTime(hour: 14, minute: 0),
            plannedArrivalTime: today.settingTime(hour: 17, minute: 0),
            departureTimeZoneIdentifier: TimeZone.autoupdatingCurrent.identifier,
            arrivalTimeZoneIdentifier: TimeZone.autoupdatingCurrent.identifier
        )
        let plan = TravelPlan(
            title: "JFK-MIA",
            segments: [segment],
            status: .arrived,
            currentSegmentID: segment.id
        )
        let user = UserAccount(
            userID: "arrived-traveler",
            displayName: "Traveler",
            email: nil,
            authMode: .guest,
            createdAt: today.adding(days: -30)
        )
        let viewModel = AppViewModel(
            authService: MockAuthService(user: user),
            repository: InMemoryDailyRecordRepository(records: [:]),
            travelPlanRepository: InMemoryTravelPlanRepository(plans: [plan]),
            preferencesStore: MockPreferencesStore(preferences: UserPreferences()),
            photoStorageService: MockPhotoStorageService(),
            videoStorageService: MockVideoStorageService(),
            sunTimesService: MockSunTimesService(),
            weatherService: MockWeatherService(),
            healthSyncAdapter: MockHealthSyncAdapter(sleepRecord: nil),
            cloudSyncService: NoopCloudSyncService(),
            aiInsightNarrativeService: MockAIInsightNarrativeService(responses: []),
            openAIKeyStore: MockOpenAIKeyStore(key: nil),
            locationService: LocationService(),
            selectedDate: today,
            dailyRecord: DailyRecord.empty(for: today, preferences: UserPreferences()),
            preferences: UserPreferences()
        )

        await viewModel.bootstrap()

        #expect(viewModel.activeTravelPlan(on: today)?.id == plan.id)
    }

    @Test
    func travelPlanAffectedDatesCoverFutureOverlayDays() {
        let plan = TravelPlan.sampleBOSPKX()

        #expect(plan.affectedStorageKeys.contains("2026-05-21"))
        #expect(plan.affectedStorageKeys.contains("2026-05-22"))
        #expect(plan.earliestCalendarDate?.storageKey() == "2026-05-21")
        #expect(plan.latestCalendarDate?.storageKey() == "2026-05-22")
    }

    @Test @MainActor
    func travelPlansRespectMidnightModeForEarlyMorningFlights() async throws {
        let bostonTimeZone = try #require(TimeZone(identifier: "America/New_York"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = bostonTimeZone
        let departure = try #require(calendar.date(from: DateComponents(
            timeZone: bostonTimeZone,
            year: 2026,
            month: 5,
            day: 22,
            hour: 1,
            minute: 0
        )))
        let arrival = try #require(calendar.date(from: DateComponents(
            timeZone: bostonTimeZone,
            year: 2026,
            month: 5,
            day: 22,
            hour: 3,
            minute: 10
        )))
        let plan = TravelPlan(
            title: "BOS-JFK 旅程",
            segments: [
                TravelSegment(
                    flightNumber: "DL001",
                    originCode: "BOS",
                    destinationCode: "JFK",
                    plannedDepartureTime: departure,
                    plannedArrivalTime: arrival,
                    departureTimeZoneIdentifier: "America/New_York",
                    arrivalTimeZoneIdentifier: "America/New_York"
                )
            ]
        )
        let preferences = UserPreferences(
            midnightMode: MidnightModeSettings(isEnabled: true, cutoffHour: 4, effectiveFrom: nil)
        )
        let user = UserAccount(
            userID: "midnight-traveler",
            displayName: "Traveler",
            email: nil,
            authMode: .guest,
            createdAt: departure.addingTimeInterval(-86_400)
        )
        let selectedDate = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 21)))
        let viewModel = AppViewModel(
            authService: MockAuthService(user: user),
            repository: InMemoryDailyRecordRepository(records: [:]),
            travelPlanRepository: InMemoryTravelPlanRepository(plans: [plan]),
            preferencesStore: MockPreferencesStore(preferences: preferences),
            photoStorageService: MockPhotoStorageService(),
            videoStorageService: MockVideoStorageService(),
            sunTimesService: MockSunTimesService(),
            weatherService: MockWeatherService(),
            healthSyncAdapter: MockHealthSyncAdapter(sleepRecord: nil),
            cloudSyncService: NoopCloudSyncService(),
            aiInsightNarrativeService: MockAIInsightNarrativeService(responses: []),
            openAIKeyStore: MockOpenAIKeyStore(key: nil),
            locationService: LocationService(),
            selectedDate: selectedDate,
            dailyRecord: DailyRecord.empty(for: selectedDate, preferences: preferences),
            preferences: preferences
        )

        await viewModel.bootstrap()

        #expect(plan.affectedStorageKeys(using: preferences).contains("2026-05-21"))
        #expect(plan.earliestCalendarDate(using: preferences)?.storageKey() == "2026-05-21")
        #expect(viewModel.travelPlans(on: selectedDate).contains { $0.id == plan.id })
    }

    @Test
    func airportCatalogLoadsGlobalAirportData() throws {
        #expect(AirportCatalog.airports.count > 7_000)
        #expect(AirportCatalog.airport(for: "BOS")?.timeZoneIdentifier == "America/New_York")
        #expect(AirportCatalog.airport(for: "LHR")?.timeZoneIdentifier == "Europe/London")
        #expect(AirportCatalog.airport(for: "PKX")?.timeZoneIdentifier == "Asia/Shanghai")
        #expect(AirportCatalog.search("Beijing").contains { $0.code == "PKX" })
    }

    @Test
    func timeZoneDisplayIncludesUtcOffsetForTravelAirports() throws {
        let travelDate = try #require(Calendar(identifier: .gregorian).date(from: DateComponents(
            timeZone: TimeZone(identifier: "UTC"),
            year: 2026,
            month: 5,
            day: 21,
            hour: 12
        )))

        #expect(TimeZoneDisplay.utcOffsetText(for: "America/New_York", at: travelDate) == "UTC-04:00")
        #expect(TimeZoneDisplay.utcOffsetText(for: "Europe/London", at: travelDate) == "UTC+01:00")
        #expect(TimeZoneDisplay.userFacingTimeZoneText(for: "Asia/Shanghai", at: travelDate) == "UTC+08:00 · Asia/Shanghai")
    }

    @Test @MainActor
    func travelTimeDisplayUsesFlightRelativeClock() async throws {
        let user = UserAccount(
            userID: "traveler",
            displayName: "Traveler",
            email: nil,
            authMode: .guest,
            createdAt: Date()
        )
        let plan = TravelPlan.sampleBOSPKX()
        let segment = try #require(plan.segments.first)
        let viewModel = AppViewModel(
            authService: MockAuthService(user: user),
            repository: InMemoryDailyRecordRepository(records: [:]),
            travelPlanRepository: InMemoryTravelPlanRepository(plans: [plan]),
            preferencesStore: MockPreferencesStore(preferences: UserPreferences()),
            photoStorageService: MockPhotoStorageService(),
            videoStorageService: MockVideoStorageService(),
            sunTimesService: MockSunTimesService(),
            weatherService: MockWeatherService(),
            healthSyncAdapter: MockHealthSyncAdapter(sleepRecord: nil),
            cloudSyncService: NoopCloudSyncService(),
            aiInsightNarrativeService: MockAIInsightNarrativeService(responses: []),
            openAIKeyStore: MockOpenAIKeyStore(key: nil),
            locationService: LocationService(),
            selectedDate: Date(),
            dailyRecord: DailyRecord.empty(for: Date(), preferences: UserPreferences()),
            preferences: UserPreferences()
        )
        await viewModel.bootstrap()

        let display = try #require(viewModel.travelTimeDisplay(
            for: segment.plannedDepartureTime.addingTimeInterval(65 * 60),
            context: TravelRecordContext(planID: plan.id, segmentID: segment.id, phase: .inFlight)
        ))

        #expect(display.primary.contains("BOS-LHR"))
        #expect(display.primary.contains("1h 5m"))
        #expect(display.secondary == "BOS 08:30 / LHR 13:30")
    }

    @Test @MainActor
    func travelTimeDisplayIgnoresActualDepartureForElapsedClock() async throws {
        let user = UserAccount(
            userID: "actual-flight-traveler",
            displayName: "Traveler",
            email: nil,
            authMode: .guest,
            createdAt: Date()
        )
        var plan = TravelPlan.sampleBOSPKX()
        let originalSegment = try #require(plan.segments.first)
        let actualDeparture = originalSegment.plannedDepartureTime.addingTimeInterval(35 * 60)
        plan.segments[0].actualDepartureTime = actualDeparture
        let viewModel = AppViewModel(
            authService: MockAuthService(user: user),
            repository: InMemoryDailyRecordRepository(records: [:]),
            travelPlanRepository: InMemoryTravelPlanRepository(plans: [plan]),
            preferencesStore: MockPreferencesStore(preferences: UserPreferences()),
            photoStorageService: MockPhotoStorageService(),
            videoStorageService: MockVideoStorageService(),
            sunTimesService: MockSunTimesService(),
            weatherService: MockWeatherService(),
            healthSyncAdapter: MockHealthSyncAdapter(sleepRecord: nil),
            cloudSyncService: NoopCloudSyncService(),
            aiInsightNarrativeService: MockAIInsightNarrativeService(responses: []),
            openAIKeyStore: MockOpenAIKeyStore(key: nil),
            locationService: LocationService(),
            selectedDate: Date(),
            dailyRecord: DailyRecord.empty(for: Date(), preferences: UserPreferences()),
            preferences: UserPreferences()
        )
        await viewModel.bootstrap()

        let display = try #require(viewModel.travelTimeDisplay(
            for: actualDeparture.addingTimeInterval(65 * 60),
            context: TravelRecordContext(planID: plan.id, segmentID: originalSegment.id, phase: .inFlight)
        ))

        #expect(display.primary.contains("1h 40m"))
        #expect(display.primary.contains("1h 5m") == false)
    }

    @Test @MainActor
    func travelEventTimestampUsesSegmentDepartureTimeZone() async throws {
        let departure = try zonedDate(
            year: 2026,
            month: 6,
            day: 7,
            hour: 19,
            minute: 50,
            timeZoneIdentifier: "Asia/Hong_Kong"
        )
        let arrival = try zonedDate(
            year: 2026,
            month: 6,
            day: 7,
            hour: 23,
            minute: 50,
            timeZoneIdentifier: "America/New_York"
        )
        let expected = try zonedDate(
            year: 2026,
            month: 6,
            day: 7,
            hour: 22,
            minute: 10,
            timeZoneIdentifier: "Asia/Hong_Kong"
        )
        let segment = TravelSegment(
            flightNumber: "CX844",
            originCode: "HKG",
            destinationCode: "JFK",
            plannedDepartureTime: departure,
            plannedArrivalTime: arrival,
            departureTimeZoneIdentifier: "Asia/Hong_Kong",
            arrivalTimeZoneIdentifier: "America/New_York"
        )
        let plan = TravelPlan(
            title: "HKG-JFK",
            segments: [segment],
            status: .inFlight,
            currentSegmentID: segment.id
        )
        let user = UserAccount(
            userID: "travel-timezone-input",
            displayName: "Traveler",
            email: nil,
            authMode: .guest,
            createdAt: departure.addingTimeInterval(-86_400)
        )
        let baseDate = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 7)))
        let viewModel = AppViewModel(
            authService: MockAuthService(user: user),
            repository: InMemoryDailyRecordRepository(records: [:]),
            travelPlanRepository: InMemoryTravelPlanRepository(plans: [plan]),
            preferencesStore: MockPreferencesStore(preferences: UserPreferences()),
            photoStorageService: MockPhotoStorageService(),
            videoStorageService: MockVideoStorageService(),
            sunTimesService: MockSunTimesService(),
            weatherService: MockWeatherService(),
            healthSyncAdapter: MockHealthSyncAdapter(sleepRecord: nil),
            cloudSyncService: NoopCloudSyncService(),
            aiInsightNarrativeService: MockAIInsightNarrativeService(responses: []),
            openAIKeyStore: MockOpenAIKeyStore(key: nil),
            locationService: LocationService(),
            selectedDate: baseDate,
            dailyRecord: DailyRecord.empty(for: baseDate, preferences: UserPreferences()),
            preferences: UserPreferences()
        )
        await viewModel.bootstrap()

        let resolved = viewModel.resolvedEventTimestamp(
            for: baseDate,
            hour: 22,
            minute: 10,
            recordedTimeZoneIdentifier: nil,
            travelContext: TravelRecordContext(planID: plan.id, segmentID: segment.id, phase: .inFlight)
        )

        #expect(resolved == expected)
        #expect(clockText(resolved, timeZoneIdentifier: "Asia/Hong_Kong") == "22:10")

        let arrivedResolved = viewModel.resolvedEventTimestamp(
            for: baseDate,
            hour: 22,
            minute: 10,
            recordedTimeZoneIdentifier: nil,
            travelContext: TravelRecordContext(planID: plan.id, segmentID: segment.id, phase: .arrived)
        )

        #expect(arrivedResolved == expected)
    }

    @Test @MainActor
    func travelRecordTimezoneMigrationPreservesAbsoluteTimestampWhenStoredTimeZoneIsWrong() async throws {
        let departure = try zonedDate(
            year: 2026,
            month: 6,
            day: 7,
            hour: 19,
            minute: 50,
            timeZoneIdentifier: "Asia/Hong_Kong"
        )
        let arrival = try zonedDate(
            year: 2026,
            month: 6,
            day: 7,
            hour: 23,
            minute: 50,
            timeZoneIdentifier: "America/New_York"
        )
        let intendedTime = try zonedDate(
            year: 2026,
            month: 6,
            day: 7,
            hour: 22,
            minute: 10,
            timeZoneIdentifier: "Asia/Hong_Kong"
        )
        let segment = TravelSegment(
            flightNumber: "CX844",
            originCode: "HKG",
            destinationCode: "JFK",
            plannedDepartureTime: departure,
            plannedArrivalTime: arrival,
            departureTimeZoneIdentifier: "Asia/Hong_Kong",
            arrivalTimeZoneIdentifier: "America/New_York"
        )
        let plan = TravelPlan(
            title: "HKG-JFK",
            segments: [segment],
            status: .inFlight,
            currentSegmentID: segment.id
        )
        let context = TravelRecordContext(planID: plan.id, segmentID: segment.id, phase: .inFlight)
        let day = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 7)))
        let record = DailyRecord(
            date: day,
            sleepRecord: SleepRecord(),
            meals: [
                MealEntry(
                    mealKind: .custom,
                    customTitle: "飞机餐",
                    status: .logged,
                    time: intendedTime,
                    timeZoneIdentifier: "America/New_York",
                    travelContext: context
                )
            ],
            showers: []
        )
        let user = UserAccount(
            userID: "travel-timezone-migration",
            displayName: "Traveler",
            email: nil,
            authMode: .guest,
            createdAt: departure.addingTimeInterval(-86_400)
        )
        let viewModel = AppViewModel(
            authService: MockAuthService(user: user),
            repository: InMemoryDailyRecordRepository(records: [day.storageKey(): record]),
            travelPlanRepository: InMemoryTravelPlanRepository(plans: [plan]),
            preferencesStore: MockPreferencesStore(preferences: UserPreferences()),
            photoStorageService: MockPhotoStorageService(),
            videoStorageService: MockVideoStorageService(),
            sunTimesService: MockSunTimesService(),
            weatherService: MockWeatherService(),
            healthSyncAdapter: MockHealthSyncAdapter(sleepRecord: nil),
            cloudSyncService: NoopCloudSyncService(),
            aiInsightNarrativeService: MockAIInsightNarrativeService(responses: []),
            openAIKeyStore: MockOpenAIKeyStore(key: nil),
            locationService: LocationService(),
            selectedDate: day,
            dailyRecord: DailyRecord.empty(for: day, preferences: UserPreferences()),
            preferences: UserPreferences()
        )
        await viewModel.bootstrap()

        let migratedMeal = try #require(viewModel.allRecords.flatMap { $0.meals }.first { $0.travelContext == context })
        let migratedTime = try #require(migratedMeal.time)

        #expect(migratedTime == intendedTime)
        #expect(migratedMeal.timeZoneIdentifier == "Asia/Hong_Kong")
        #expect(clockText(migratedTime, timeZoneIdentifier: "Asia/Hong_Kong") == "22:10")
    }

    @Test @MainActor
    func travelRecordTimezoneMigrationRepairsPreviousOffsetShiftOutsideFlightWindow() async throws {
        let departure = try zonedDate(
            year: 2026,
            month: 6,
            day: 7,
            hour: 19,
            minute: 50,
            timeZoneIdentifier: "Asia/Hong_Kong"
        )
        let arrival = try zonedDate(
            year: 2026,
            month: 6,
            day: 7,
            hour: 23,
            minute: 50,
            timeZoneIdentifier: "America/New_York"
        )
        let intendedTime = try zonedDate(
            year: 2026,
            month: 6,
            day: 7,
            hour: 22,
            minute: 10,
            timeZoneIdentifier: "Asia/Hong_Kong"
        )
        let shiftedTime = intendedTime.addingTimeInterval(-12 * 3600)
        let segment = TravelSegment(
            flightNumber: "CX844",
            originCode: "HKG",
            destinationCode: "JFK",
            plannedDepartureTime: departure,
            plannedArrivalTime: arrival,
            departureTimeZoneIdentifier: "Asia/Hong_Kong",
            arrivalTimeZoneIdentifier: "America/New_York"
        )
        let plan = TravelPlan(
            title: "HKG-JFK",
            segments: [segment],
            status: .inFlight,
            currentSegmentID: segment.id
        )
        let context = TravelRecordContext(planID: plan.id, segmentID: segment.id, phase: .inFlight)
        let day = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 7)))
        let record = DailyRecord(
            date: day,
            sleepRecord: SleepRecord(),
            meals: [
                MealEntry(
                    mealKind: .custom,
                    customTitle: "飞机餐",
                    status: .logged,
                    time: shiftedTime,
                    timeZoneIdentifier: "Asia/Hong_Kong",
                    travelContext: context
                )
            ],
            showers: []
        )
        let user = UserAccount(
            userID: "travel-timezone-shift-repair",
            displayName: "Traveler",
            email: nil,
            authMode: .guest,
            createdAt: departure.addingTimeInterval(-86_400)
        )
        let viewModel = AppViewModel(
            authService: MockAuthService(user: user),
            repository: InMemoryDailyRecordRepository(records: [day.storageKey(): record]),
            travelPlanRepository: InMemoryTravelPlanRepository(plans: [plan]),
            preferencesStore: MockPreferencesStore(preferences: UserPreferences()),
            photoStorageService: MockPhotoStorageService(),
            videoStorageService: MockVideoStorageService(),
            sunTimesService: MockSunTimesService(),
            weatherService: MockWeatherService(),
            healthSyncAdapter: MockHealthSyncAdapter(sleepRecord: nil),
            cloudSyncService: NoopCloudSyncService(),
            aiInsightNarrativeService: MockAIInsightNarrativeService(responses: []),
            openAIKeyStore: MockOpenAIKeyStore(key: nil),
            locationService: LocationService(),
            selectedDate: day,
            dailyRecord: DailyRecord.empty(for: day, preferences: UserPreferences()),
            preferences: UserPreferences()
        )
        await viewModel.bootstrap()

        let migratedMeal = try #require(viewModel.allRecords.flatMap { $0.meals }.first { $0.travelContext == context })
        let migratedTime = try #require(migratedMeal.time)

        #expect(migratedTime == intendedTime)
        #expect(migratedMeal.timeZoneIdentifier == "Asia/Hong_Kong")
    }

    @Test
    func travelSegmentDraftPreservesAirportZonedDatePickerSelection() throws {
        let departure = try zonedDate(
            year: 2026,
            month: 6,
            day: 7,
            hour: 3,
            minute: 50,
            timeZoneIdentifier: "Asia/Hong_Kong"
        )
        let arrival = try zonedDate(
            year: 2026,
            month: 6,
            day: 7,
            hour: 7,
            minute: 50,
            timeZoneIdentifier: "America/New_York"
        )

        let draft = TravelSegmentDraft(
            flightNumber: "CX844",
            originCode: "HKG",
            destinationCode: "JFK",
            departureDate: departure,
            arrivalDate: arrival,
            departureTimeZoneIdentifier: "Asia/Hong_Kong",
            arrivalTimeZoneIdentifier: "America/New_York"
        )
        let segment = draft.makeSegment()

        #expect(segment.plannedDepartureTime == departure)
        #expect(segment.plannedArrivalTime == arrival)
        #expect(segment.plannedDuration == 16 * 3600)
        #expect(clockText(segment.plannedDepartureTime, timeZoneIdentifier: "Asia/Hong_Kong") == "03:50")
        #expect(clockText(segment.plannedArrivalTime, timeZoneIdentifier: "America/New_York") == "07:50")
    }

    @Test
    func travelSegmentNormalizationRepairsLegacyDoubleShiftedArrival() throws {
        let departure = try zonedDate(
            year: 2026,
            month: 6,
            day: 7,
            hour: 3,
            minute: 50,
            timeZoneIdentifier: "Asia/Hong_Kong"
        )
        let expectedArrival = try zonedDate(
            year: 2026,
            month: 6,
            day: 7,
            hour: 7,
            minute: 50,
            timeZoneIdentifier: "America/New_York"
        )
        let legacyDoubleShiftedArrival = expectedArrival.addingTimeInterval(12 * 3600)
        let segment = TravelSegment(
            flightNumber: "CX844",
            originCode: "HKG",
            destinationCode: "JFK",
            plannedDepartureTime: departure,
            plannedArrivalTime: legacyDoubleShiftedArrival,
            departureTimeZoneIdentifier: "Asia/Hong_Kong",
            arrivalTimeZoneIdentifier: "America/New_York"
        )

        let normalized = segment.normalizedForChronology()

        #expect(segment.plannedArrivalTime == legacyDoubleShiftedArrival)
        #expect(segment.plannedDuration == 16 * 3600)
        #expect(segment.effectiveDuration == 16 * 3600)
        #expect(normalized.plannedArrivalTime == expectedArrival)
        #expect(normalized.plannedDuration == 16 * 3600)
        #expect(clockText(normalized.plannedArrivalTime, timeZoneIdentifier: "America/New_York") == "07:50")
    }

    @Test
    func travelSegmentDurationFallsBackToPlanWhenActualTimesCollapseToZero() throws {
        let departure = try zonedDate(
            year: 2026,
            month: 6,
            day: 7,
            hour: 19,
            minute: 50,
            timeZoneIdentifier: "Asia/Hong_Kong"
        )
        let intendedArrival = departure.addingTimeInterval(15 * 3600 + 35 * 60)
        let legacyDoubleShiftedArrival = intendedArrival.addingTimeInterval(12 * 3600)
        let segment = TravelSegment(
            flightNumber: "CX844",
            originCode: "HKG",
            destinationCode: "JFK",
            plannedDepartureTime: departure,
            plannedArrivalTime: legacyDoubleShiftedArrival,
            departureTimeZoneIdentifier: "Asia/Hong_Kong",
            arrivalTimeZoneIdentifier: "America/New_York",
            actualDepartureTime: departure,
            actualArrivalTime: departure
        )

        let normalized = segment.normalizedForChronology()

        #expect(segment.actualDuration == nil)
        #expect(normalized.actualDuration == nil)
        #expect(normalized.plannedDuration == 15 * 3600 + 35 * 60)
        #expect(normalized.effectiveDuration == 15 * 3600 + 35 * 60)
    }

    @Test
    func travelSegmentNormalizationRepairsArrivalStoredOnDepartureDate() throws {
        let departure = try zonedDate(
            year: 2026,
            month: 6,
            day: 6,
            hour: 22,
            minute: 9,
            timeZoneIdentifier: "Asia/Shanghai"
        )
        let arrivalStoredOnWrongDay = try zonedDate(
            year: 2026,
            month: 6,
            day: 6,
            hour: 1,
            minute: 43,
            timeZoneIdentifier: "Asia/Hong_Kong"
        )
        let actualArrival = try zonedDate(
            year: 2026,
            month: 6,
            day: 7,
            hour: 1,
            minute: 43,
            timeZoneIdentifier: "Asia/Hong_Kong"
        )
        let segment = TravelSegment(
            flightNumber: "CX931",
            originCode: "WUH",
            destinationCode: "HKG",
            plannedDepartureTime: departure,
            plannedArrivalTime: arrivalStoredOnWrongDay,
            departureTimeZoneIdentifier: "Asia/Shanghai",
            arrivalTimeZoneIdentifier: "Asia/Hong_Kong",
            actualDepartureTime: departure,
            actualArrivalTime: actualArrival
        )

        let normalized = segment.normalizedForChronology()

        #expect(normalized.plannedDuration == 3 * 3600 + 34 * 60)
        #expect(segment.effectiveDuration == 3 * 3600 + 34 * 60)
        #expect(clockText(normalized.plannedArrivalTime, timeZoneIdentifier: "Asia/Hong_Kong") == "01:43")
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

    func saveRecord(_ record: DailyRecord, preferences: UserPreferences, userID: String) throws {
        records[record.date.storageKey()] = record
    }

    func loadAllRecords(userID: String, preferences: UserPreferences) throws -> [DailyRecord] {
        Array(records.values)
    }
}

private final class InMemoryTravelPlanRepository: TravelPlanRepository {
    private var plans: [TravelPlan]

    init(plans: [TravelPlan] = []) {
        self.plans = plans
    }

    func loadTravelPlans(userID: String) throws -> [TravelPlan] {
        plans
    }

    func saveTravelPlan(_ plan: TravelPlan, userID: String) throws {
        if let index = plans.firstIndex(where: { $0.id == plan.id }) {
            plans[index] = plan
        } else {
            plans.append(plan)
        }
    }

    func deleteTravelPlan(_ plan: TravelPlan, userID: String) throws {
        plans.removeAll { $0.id == plan.id }
    }
}

private func zonedDate(
    year: Int,
    month: Int,
    day: Int,
    hour: Int,
    minute: Int,
    timeZoneIdentifier: String
) throws -> Date {
    let timeZone = try #require(TimeZone(identifier: timeZoneIdentifier))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return try #require(calendar.date(from: DateComponents(
        timeZone: timeZone,
        year: year,
        month: month,
        day: day,
        hour: hour,
        minute: minute
    )))
}

private func clockText(_ date: Date, timeZoneIdentifier: String) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: timeZoneIdentifier)
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
}

private func sampleInsightPayload() -> DailyInsightPayload {
    let day = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 19))!
    let preferences = UserPreferences(healthKitSyncEnabled: false)
    let record = DailyRecord(
        date: day,
        sleepRecord: SleepRecord(
            bedtimePreviousNight: day.adding(days: -1).settingTime(hour: 23, minute: 40),
            wakeTimeCurrentDay: day.settingTime(hour: 7, minute: 20),
            source: .manual
        ),
        meals: [
            MealEntry(mealKind: .breakfast, status: .logged, time: day.settingTime(hour: 8, minute: 10))
        ],
        showers: [ShowerEntry(time: day.settingTime(hour: 21, minute: 5))],
        bowelMovements: [BowelMovementEntry(time: day.settingTime(hour: 8, minute: 0))],
        sexualActivities: [],
        sunTimes: nil
    )

    return DailyInsightAnalyzer.makePayload(
        record: record,
        preferences: preferences,
        language: preferences.appLanguage,
        locale: Locale(identifier: "en_US_POSIX"),
        history: [record]
    )
}

@MainActor
private func restorePersistedProcessLanguage(_ language: AppLanguage?) {
    if let language {
        AppViewModel.applyProcessLocale(language)
    } else {
        UserDefaults.standard.removeObject(forKey: "dailylogs.appLanguage")
        UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        UserDefaults.standard.removeObject(forKey: "AppleLocale")
        UserDefaults.standard.synchronize()
    }
}

private func sampleAINarrative(headline: String, overallScore: Int) -> DailyInsightNarrative {
    DailyInsightNarrative(
        headline: headline,
        summary: "sample summary",
        bullets: ["sample bullet 1", "sample bullet 2"],
        overallScore: overallScore,
        components: [
            "sleep": .init(score: 40, maxScore: 45, detail: "sleep", included: true),
            "meals": .init(score: 30, maxScore: 35, detail: "meals", included: true),
            "shower": .init(score: 9, maxScore: 10, detail: "shower", included: true),
            "bowelMovement": .init(score: 9, maxScore: 10, detail: "bowel", included: true)
        ]
    )
}

private func makeMockSession(responseData: Data, statusCode: Int = 200) -> URLSession {
    MockURLProtocol.handler = { request in
        let response = HTTPURLResponse(
            url: try #require(request.url),
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, responseData)
    }

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: configuration)
}

private struct ParsedNarrativeEnvelope: Encodable {
    struct OutputItem: Encodable {
        struct ContentItem: Encodable {
            let type: String
            let text: String?
            let parsed: DailyInsightNarrative?
        }

        let content: [ContentItem]
    }

    let output: [OutputItem]
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private struct MockWeatherService: WeatherService {
    var snapshot: WeatherSnapshot? = nil

    func weather(at coordinate: CLLocationCoordinate2D) async throws -> WeatherSnapshot? {
        snapshot
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
    private let translationResponses: [DailyInsightNarrative.LocalizedText]
    private var nextIndex = 0
    private var nextTranslationIndex = 0
    private var storedCallCount = 0
    private var storedTranslationCallCount = 0

    init(
        responses: [DailyInsightNarrative],
        translationResponses: [DailyInsightNarrative.LocalizedText] = []
    ) {
        self.responses = responses
        self.translationResponses = translationResponses
    }

    var callCount: Int {
        lock.withLock { storedCallCount }
    }

    var translationCallCount: Int {
        lock.withLock { storedTranslationCallCount }
    }

    var isConfigured: Bool { true }

    func generateNarrative(from payload: DailyInsightPayload) async throws -> DailyInsightNarrative {
        try lock.withLock {
            storedCallCount += 1
            guard !responses.isEmpty else {
                throw MockAIInsightNarrativeError.noResponses
            }
            let response = responses[min(nextIndex, responses.count - 1)]
            if nextIndex < responses.count - 1 {
                nextIndex += 1
            }
            return response
        }
    }

    func translateNarrative(_ narrative: DailyInsightNarrative, to language: AppLanguage) async throws -> DailyInsightNarrative.LocalizedText {
        lock.withLock {
            storedTranslationCallCount += 1
            guard !translationResponses.isEmpty else {
                return DailyInsightNarrative.LocalizedText(
                    headline: narrative.headline,
                    summary: narrative.summary,
                    bullets: narrative.bullets
                )
            }
            let response = translationResponses[min(nextTranslationIndex, translationResponses.count - 1)]
            if nextTranslationIndex < translationResponses.count - 1 {
                nextTranslationIndex += 1
            }
            return response
        }
    }
}

private enum MockAIInsightNarrativeError: Error {
    case noResponses
}

private struct MockPreferencesStore: PreferencesStore {
    var preferences: UserPreferences

    func loadPreferences(userID: String?) throws -> UserPreferences {
        preferences
    }

    func savePreferences(_ preferences: UserPreferences, userID: String?) throws {}
}

private final class CapturingPreferencesStore: PreferencesStore {
    var preferences: UserPreferences
    private(set) var savedPreferences: UserPreferences?

    init(preferences: UserPreferences) {
        self.preferences = preferences
    }

    func loadPreferences(userID: String?) throws -> UserPreferences {
        preferences
    }

    func savePreferences(_ preferences: UserPreferences, userID: String?) throws {
        savedPreferences = preferences
    }
}

private struct MockPhotoStorageService: PhotoStorageService {
    func savePhoto(_ image: UIImage) throws -> String {
        "/tmp/mock.jpg"
    }

    func deletePhoto(at path: String) throws {}
}

private struct MockVideoStorageService: VideoStorageService {
    func saveVideo(from sourceURL: URL) throws -> String {
        sourceURL.path
    }

    func deleteVideo(at path: String) throws {}
}

private final class TrackingVideoStorageService: VideoStorageService {
    private(set) var savedPaths: [String] = []
    private(set) var deletedPaths: [String] = []

    func saveVideo(from sourceURL: URL) throws -> String {
        let path = "/tmp/mock-daily-video-\(savedPaths.count + 1).mp4"
        savedPaths.append(path)
        return path
    }

    func deleteVideo(at path: String) throws {
        deletedPaths.append(path)
    }
}

private struct MockSunTimesService: SunTimesService {
    var snapshot: SunTimes? = nil

    func sunTimes(for date: Date, coordinate: CLLocationCoordinate2D, timeZone: TimeZone) -> SunTimes? {
        snapshot
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

    func deletePhotoReference(_ photoReference: String, user: UserAccount) async throws {}

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

private actor RecordingCloudSyncState {
    private var pushed: [DailyRecord] = []
    private var deleted: [String] = []

    func appendPushedRecord(_ record: DailyRecord) {
        pushed.append(record)
    }

    func appendDeletedPhotoReference(_ photoReference: String) {
        deleted.append(photoReference)
    }

    func pushedRecords() -> [DailyRecord] {
        pushed
    }

    func deletedPhotoReferences() -> [String] {
        deleted
    }
}

private final class RecordingCloudSyncService: CloudSyncService, @unchecked Sendable {
    private let payload: CloudBootstrapPayload
    private let state = RecordingCloudSyncState()

    init(payload: CloudBootstrapPayload = CloudBootstrapPayload(profile: nil, preferences: nil, records: [])) {
        self.payload = payload
    }

    var isAvailable: Bool { true }

    func bootstrap(user: UserAccount, localPreferences: UserPreferences, localRecords: [DailyRecord]) async throws -> CloudBootstrapPayload {
        payload
    }

    func pushPreferences(_ preferences: UserPreferences, user: UserAccount) async throws {}

    func pushRecord(_ record: DailyRecord, user: UserAccount) async throws {
        await state.appendPushedRecord(record)
    }

    func pushProfile(_ user: UserAccount) async throws {}

    func deletePhotoReference(_ photoReference: String, user: UserAccount) async throws {
        await state.appendDeletedPhotoReference(photoReference)
    }

    func protectionSnapshot(for user: UserAccount) async throws -> CloudProtectionSnapshot {
        CloudProtectionSnapshot(mode: .disabled, localKeyAvailable: false)
    }

    func enableAutomaticEndToEndEncryption(
        user: UserAccount,
        localPreferences: UserPreferences,
        localRecords: [DailyRecord],
        progress: @escaping @Sendable (CloudMigrationProgress) async -> Void
    ) async throws {}

    func pushedRecords() async -> [DailyRecord] {
        await state.pushedRecords()
    }

    func deletedPhotoReferences() async -> [String] {
        await state.deletedPhotoReferences()
    }
}

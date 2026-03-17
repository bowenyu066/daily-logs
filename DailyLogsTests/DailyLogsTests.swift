import Foundation
import Testing
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

        let summary = AnalyticsCalculator.build(records: [record], range: .month)

        #expect(summary.averageSleepHours == 8)
        #expect(summary.defaultMealCompletionRate == 2.0 / 3.0)
        #expect(summary.averageShowers == 1)
        #expect(summary.days.first?.loggedMeals == 2)
        #expect(summary.days.first?.trackedMeals == 3)
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

        #expect(deduplicated.count == 1)
        #expect(deduplicated[day.storageKey()] == DailyRecord(
            date: day.startOfDay,
            sleepRecord: richerRecord.sleepRecord,
            meals: richerRecord.meals,
            showers: richerRecord.showers,
            sunTimes: richerRecord.sunTimes
        ))
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
}

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
        #expect(summary.mealCompletionRate == 2.0 / 3.0)
        #expect(summary.averageShowers == 1)
        #expect(summary.points.first?.loggedMeals == 2)
        #expect(summary.points.first?.skippedMeals == 1)
    }
}

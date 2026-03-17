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

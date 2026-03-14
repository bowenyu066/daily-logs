import AuthenticationServices
import CoreLocation
import Foundation
import SwiftUI
import UIKit

@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var user: UserAccount?
    @Published var selectedDate: Date
    @Published private(set) var dailyRecord: DailyRecord
    @Published private(set) var allRecords: [DailyRecord] = []
    @Published private(set) var preferences: UserPreferences
    @Published var analyticsRange: AnalyticsRange = .week
    @Published private(set) var isBootstrapped = false
    @Published var errorMessage: String?

    let locationService: LocationService

    private let authService: AuthService
    private let repository: DailyRecordRepository
    private let preferencesStore: PreferencesStore
    private let photoStorageService: PhotoStorageService
    private let sunTimesService: SunTimesService
    private let healthSyncAdapter: HealthSyncAdapter

    static func live() -> AppViewModel {
        let store = LocalJSONStore()
        let preferences = UserPreferences()
        return AppViewModel(
            authService: LocalAuthService(store: store),
            repository: LocalDailyRecordRepository(store: store),
            preferencesStore: LocalPreferencesStore(store: store),
            photoStorageService: LocalPhotoStorageService(),
            sunTimesService: AstronomySunTimesService(),
            healthSyncAdapter: PlaceholderHealthSyncAdapter(),
            locationService: LocationService(),
            selectedDate: .now.startOfDay,
            dailyRecord: DailyRecord.empty(for: .now, preferences: preferences),
            preferences: preferences
        )
    }

    init(
        authService: AuthService,
        repository: DailyRecordRepository,
        preferencesStore: PreferencesStore,
        photoStorageService: PhotoStorageService,
        sunTimesService: SunTimesService,
        healthSyncAdapter: HealthSyncAdapter,
        locationService: LocationService,
        selectedDate: Date,
        dailyRecord: DailyRecord,
        preferences: UserPreferences
    ) {
        self.authService = authService
        self.repository = repository
        self.preferencesStore = preferencesStore
        self.photoStorageService = photoStorageService
        self.sunTimesService = sunTimesService
        self.healthSyncAdapter = healthSyncAdapter
        self.locationService = locationService
        self.selectedDate = selectedDate.startOfDay
        self.dailyRecord = dailyRecord
        self.preferences = preferences
    }

    var isAuthenticated: Bool {
        user != nil
    }

    var canEditSelectedDate: Bool {
        selectedDate.startOfDay <= Date().startOfDay
    }

    var availableStartDate: Date {
        user?.createdAt.startOfDay ?? Date().startOfDay
    }

    var availableDateRange: ClosedRange<Date> {
        availableStartDate...Date().startOfDay
    }

    var analyticsSummary: AnalyticsSummary {
        AnalyticsCalculator.build(records: allRecords, range: analyticsRange)
    }

    func bootstrap() async {
        guard !isBootstrapped else { return }
        isBootstrapped = true
        user = authService.restoreSession()
        do {
            preferences = try preferencesStore.loadPreferences(userID: user?.userID)
            if let user {
                selectedDate = max(selectedDate, user.createdAt.startOfDay)
                try seedDemoDataIfNeeded(for: user.userID)
                try loadAllRecords(for: user.userID)
                try loadSelectedRecord()
                updateSunTimesIfPossible()
            }
        } catch {
            errorMessage = "初始化失败：\(error.localizedDescription)"
        }
    }

    func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        do {
            user = try authService.handleAppleSignIn(result: result)
            preferences = try preferencesStore.loadPreferences(userID: user?.userID)
            selectedDate = max(Date().startOfDay, availableStartDate)
            try seedDemoDataIfNeeded(for: user?.userID ?? "")
            try loadAllRecords(for: user?.userID ?? "")
            try loadSelectedRecord()
        } catch {
            errorMessage = "登录失败：\(error.localizedDescription)"
        }
    }

    func continueAsGuest() async {
        do {
            user = try authService.continueAsGuest()
            preferences = try preferencesStore.loadPreferences(userID: user?.userID)
            selectedDate = max(Date().startOfDay, availableStartDate)
            try seedDemoDataIfNeeded(for: user?.userID ?? "")
            try loadAllRecords(for: user?.userID ?? "")
            try loadSelectedRecord()
        } catch {
            errorMessage = "进入游客模式失败：\(error.localizedDescription)"
        }
    }

    func signOut() async {
        do {
            try authService.signOut()
            user = nil
            allRecords = []
            selectedDate = .now.startOfDay
            dailyRecord = DailyRecord.empty(for: selectedDate, preferences: preferences)
        } catch {
            errorMessage = "退出失败：\(error.localizedDescription)"
        }
    }

    func selectDate(_ date: Date) async {
        let clamped = min(max(date.startOfDay, availableStartDate), Date().startOfDay)
        selectedDate = clamped
        do {
            try loadSelectedRecord()
        } catch {
            errorMessage = "加载记录失败：\(error.localizedDescription)"
        }
    }

    func updateSleep(bedtime: Date?, wakeTime: Date?) async {
        guard canEditSelectedDate else { return }
        dailyRecord.sleepRecord.bedtimePreviousNight = bedtime
        dailyRecord.sleepRecord.wakeTimeCurrentDay = wakeTime
        persistCurrentRecord()
    }

    func updateBedtimeSchedule(_ schedule: BedtimeSchedule) async {
        preferences.bedtimeSchedule = schedule
        dailyRecord.sleepRecord.targetBedtime = schedule.target(for: selectedDate)
        persistPreferences()
        persistCurrentRecord()
    }

    func saveMeal(_ entry: MealEntry, image: UIImage?) async {
        guard canEditSelectedDate else { return }
        var updatedEntry = entry
        do {
            let existingEntry = dailyRecord.meals.first(where: { $0.id == updatedEntry.id })
            if let image {
                if let path = existingEntry?.photoURL {
                    try photoStorageService.deletePhoto(at: path)
                }
                updatedEntry.photoURL = try photoStorageService.savePhoto(image)
            } else if let oldPhotoURL = existingEntry?.photoURL, updatedEntry.photoURL == nil {
                try photoStorageService.deletePhoto(at: oldPhotoURL)
            }

            if updatedEntry.time != nil || updatedEntry.hasPhoto {
                updatedEntry.status = .logged
            }
            if let index = dailyRecord.meals.firstIndex(where: { $0.id == updatedEntry.id }) {
                dailyRecord.meals[index] = updatedEntry
            } else {
                dailyRecord.meals.append(updatedEntry)
            }
            persistCurrentRecord()
        } catch {
            errorMessage = "保存餐食失败：\(error.localizedDescription)"
        }
    }

    func deleteMeal(_ entry: MealEntry) async {
        guard canEditSelectedDate, entry.mealKind == .custom else { return }
        do {
            if let photoURL = entry.photoURL {
                try photoStorageService.deletePhoto(at: photoURL)
            }
            dailyRecord.meals.removeAll { $0.id == entry.id }
            persistCurrentRecord()
        } catch {
            errorMessage = "删除餐食失败：\(error.localizedDescription)"
        }
    }

    func skipMeal(_ entry: MealEntry) async {
        guard canEditSelectedDate else { return }
        do {
            if let photoURL = entry.photoURL {
                try photoStorageService.deletePhoto(at: photoURL)
            }
            var updatedEntry = entry
            updatedEntry.status = .skipped
            updatedEntry.time = nil
            updatedEntry.photoURL = nil
            if let index = dailyRecord.meals.firstIndex(where: { $0.id == updatedEntry.id }) {
                dailyRecord.meals[index] = updatedEntry
            } else {
                dailyRecord.meals.append(updatedEntry)
            }
            persistCurrentRecord()
        } catch {
            errorMessage = "更新餐食失败：\(error.localizedDescription)"
        }
    }

    func saveShower(_ shower: ShowerEntry) async {
        guard canEditSelectedDate else { return }
        if let index = dailyRecord.showers.firstIndex(where: { $0.id == shower.id }) {
            dailyRecord.showers[index] = shower
        } else {
            dailyRecord.showers.append(shower)
            dailyRecord.showers.sort { $0.time < $1.time }
        }
        persistCurrentRecord()
    }

    func deleteShower(_ shower: ShowerEntry) async {
        guard canEditSelectedDate else { return }
        dailyRecord.showers.removeAll { $0.id == shower.id }
        persistCurrentRecord()
    }

    func addDefaultMealSlot(title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !preferences.defaultMealSlots.contains(where: { $0.title.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) else {
            return
        }
        preferences.defaultMealSlots.append(MealSlot(kind: .custom, title: trimmed))
        mergeMealsWithPreferences()
        persistPreferences()
        persistCurrentRecord()
    }

    func deleteDefaultMealSlot(_ slot: MealSlot) async {
        guard !slot.isDefault else { return }
        preferences.defaultMealSlots.removeAll { $0.id == slot.id }
        dailyRecord.meals.removeAll { $0.mealKind == .custom && $0.customTitle == slot.title && $0.status == .empty }
        persistPreferences()
        persistCurrentRecord()
    }

    func requestLocationAccess() {
        locationService.requestAccess()
        preferences.locationPermissionState = locationService.permissionState
        Task {
            persistPreferences()
            try? await Task.sleep(for: .seconds(1))
            await refreshSunTimes()
        }
    }

    func refreshSunTimes() async {
        updateSunTimesIfPossible()
        persistCurrentRecord()
        persistPreferences()
    }

    func formattedTargetBedtime() -> String {
        preferences.bedtimeSchedule.target(for: selectedDate)?.displayTime ?? "--:--"
    }

    func bedtimeScheduleSummary() -> String {
        preferences.bedtimeSchedule.summary()
    }

    private func loadSelectedRecord() throws {
        guard let user else {
            dailyRecord = DailyRecord.empty(for: selectedDate, preferences: preferences)
            return
        }
        let sourceHint = healthSyncAdapter.latestSleepSourceHint()
        var record = try repository.loadRecord(for: selectedDate, preferences: preferences, userID: user.userID)
        if let sourceHint {
            record.sleepRecord.source = sourceHint
        }
        record.sleepRecord.targetBedtime = preferences.bedtimeSchedule.target(for: selectedDate)
        dailyRecord = mergedRecord(record, with: preferences)
        updateSunTimesIfPossible()
    }

    private func loadAllRecords(for userID: String) throws {
        allRecords = try repository.loadAllRecords(userID: userID)
            .filter { $0.date >= availableStartDate }
    }

    private func seedDemoDataIfNeeded(for userID: String) throws {
        #if DEBUG
        guard !userID.isEmpty else { return }
        let existing = try repository.loadAllRecords(userID: userID)
        guard existing.isEmpty else { return }

        let today = Date().startOfDay
        for offset in stride(from: 44, through: 0, by: -1) {
            let date = today.adding(days: -offset)
            var record = DailyRecord.empty(for: date, preferences: preferences)

            let bedtimeHour = 22 + ((offset % 5 == 0 || offset % 6 == 0) ? 1 : 0)
            let bedtimeMinute = [10, 20, 30, 40, 50, 0, 15][offset % 7]
            let wakeHour = 6 + (offset % 4 == 0 ? 1 : 0) + (offset % 9 == 0 ? 1 : 0)
            let wakeMinute = [5, 15, 20, 30, 40, 45, 55][offset % 7]
            record.sleepRecord.bedtimePreviousNight = date.adding(days: -1).settingTime(hour: bedtimeHour, minute: bedtimeMinute)
            record.sleepRecord.wakeTimeCurrentDay = date.settingTime(hour: min(wakeHour, 9), minute: wakeMinute)
            record.sleepRecord.targetBedtime = preferences.bedtimeSchedule.target(for: date)

            for index in record.meals.indices {
                switch record.meals[index].mealKind {
                case .breakfast:
                    if offset % 7 == 0 {
                        record.meals[index].status = .skipped
                    } else {
                        record.meals[index].status = .logged
                        record.meals[index].time = date.settingTime(hour: 7 + (offset % 2), minute: [12, 18, 24, 31, 40][offset % 5])
                    }
                case .lunch:
                    if offset % 9 == 0 {
                        record.meals[index].status = .skipped
                    } else {
                        record.meals[index].status = .logged
                        record.meals[index].time = date.settingTime(hour: 12 + (offset % 2), minute: [5, 12, 20, 28, 36][offset % 5])
                    }
                case .dinner:
                    if offset % 11 == 0 {
                        record.meals[index].status = .empty
                    } else {
                        record.meals[index].status = .logged
                        record.meals[index].time = date.settingTime(hour: 18 + (offset % 2), minute: [0, 10, 18, 26, 35][offset % 5])
                    }
                case .custom:
                    break
                }
            }

            if offset % 4 == 0 {
                record.meals.append(
                    MealEntry(
                        mealKind: .custom,
                        customTitle: offset % 8 == 0 ? "夜宵" : "加餐",
                        status: .logged,
                        time: date.settingTime(hour: offset % 8 == 0 ? 22 : 15, minute: [8, 16, 25, 32][offset % 4]),
                        photoURL: nil
                    )
                )
            }

            let showerTimes: [Date]
            if offset % 6 == 0 {
                showerTimes = [
                    date.settingTime(hour: 8, minute: 10),
                    date.settingTime(hour: 21, minute: 40)
                ]
            } else if offset % 2 == 0 {
                showerTimes = [date.settingTime(hour: 21, minute: 25)]
            } else {
                showerTimes = [date.settingTime(hour: 7, minute: 50)]
            }
            record.showers = showerTimes.map { ShowerEntry(time: $0) }

            try repository.saveRecord(record, userID: userID)
        }
        #endif
    }

    private func persistCurrentRecord() {
        guard let user, canEditSelectedDate else { return }
        do {
            dailyRecord.date = selectedDate.startOfDay
            dailyRecord.sleepRecord.targetBedtime = preferences.bedtimeSchedule.target(for: selectedDate)
            dailyRecord = mergedRecord(dailyRecord, with: preferences)
            try repository.saveRecord(dailyRecord, userID: user.userID)
            try loadAllRecords(for: user.userID)
        } catch {
            errorMessage = "保存记录失败：\(error.localizedDescription)"
        }
    }

    private func persistPreferences() {
        do {
            preferences.locationPermissionState = locationService.permissionState
            try preferencesStore.savePreferences(preferences, userID: user?.userID)
        } catch {
            errorMessage = "保存偏好失败：\(error.localizedDescription)"
        }
    }

    private func mergeMealsWithPreferences() {
        dailyRecord = mergedRecord(dailyRecord, with: preferences)
    }

    private func mergedRecord(_ record: DailyRecord, with preferences: UserPreferences) -> DailyRecord {
        var updated = record
        updated.sleepRecord.targetBedtime = preferences.bedtimeSchedule.target(for: updated.date)
        for slot in preferences.defaultMealSlots {
            let exists = updated.meals.contains {
                if slot.kind == .custom {
                    return $0.mealKind == .custom && $0.customTitle == slot.title
                }
                return $0.mealKind == slot.kind
            }
            if !exists {
                updated.meals.append(
                    MealEntry(
                        mealKind: slot.kind,
                        customTitle: slot.kind == .custom ? slot.title : nil,
                        status: .empty,
                        time: nil,
                        photoURL: nil
                    )
                )
            }
        }
        updated.meals.sort { lhs, rhs in
            let order: [MealKind: Int] = [.breakfast: 0, .lunch: 1, .dinner: 2, .custom: 3]
            if lhs.mealKind == rhs.mealKind {
                return lhs.displayTitle < rhs.displayTitle
            }
            return (order[lhs.mealKind] ?? 99) < (order[rhs.mealKind] ?? 99)
        }
        return updated
    }

    private func updateSunTimesIfPossible() {
        preferences.locationPermissionState = locationService.permissionState
        guard let coordinate = locationService.latestLocation?.coordinate else {
            dailyRecord.sunTimes = nil
            return
        }
        let timeZone = locationService.detectedTimeZone ?? TimeZone.autoupdatingCurrent
        dailyRecord.sunTimes = sunTimesService.sunTimes(for: selectedDate, coordinate: coordinate, timeZone: timeZone)
    }
}

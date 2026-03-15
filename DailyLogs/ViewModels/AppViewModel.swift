import AuthenticationServices
import CoreLocation
import FirebaseAuth
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
    @Published var analyticsCustomDateRange: ClosedRange<Date> = Date().startOfDay.adding(days: -29)...Date().startOfDay
    @Published private(set) var isBootstrapped = false
    @Published var errorMessage: String?

    let locationService: LocationService

    private let authService: AuthService
    private let repository: DailyRecordRepository
    private let preferencesStore: PreferencesStore
    private let photoStorageService: PhotoStorageService
    private let sunTimesService: SunTimesService
    private var healthSyncAdapter: HealthSyncAdapter
    private let cloudSyncService: CloudSyncService

    static func live() -> AppViewModel {
        let store = LocalJSONStore()
        let preferences = UserPreferences()
        return AppViewModel(
            authService: LocalAuthService(store: store),
            repository: LocalDailyRecordRepository(store: store),
            preferencesStore: LocalPreferencesStore(store: store),
            photoStorageService: LocalPhotoStorageService(),
            sunTimesService: AstronomySunTimesService(),
            healthSyncAdapter: HealthKitService(),
            cloudSyncService: FirebaseCloudSyncService(),
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
        cloudSyncService: CloudSyncService,
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
        self.cloudSyncService = cloudSyncService
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
        AnalyticsCalculator.build(
            records: allRecords,
            range: analyticsRange,
            customRange: analyticsRange == .custom ? analyticsCustomDateRange : nil,
            defaultMealSlots: preferences.defaultMealSlots
        )
    }

    var preferredColorScheme: ColorScheme? {
        switch preferences.appearanceMode {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }

    func bootstrap() async {
        guard !isBootstrapped else { return }
        isBootstrapped = true
        user = authService.restoreSession()
        do {
            preferences = try preferencesStore.loadPreferences(userID: user?.userID)
            if let user {
                selectedDate = max(selectedDate, user.createdAt.startOfDay)
                analyticsCustomDateRange = defaultAnalyticsCustomRange(startingAt: user.createdAt)
                try loadAllRecords(for: user.userID)
                await refreshFromCloudIfNeeded(for: user)
                try loadSelectedRecord()
                updateSunTimesIfPossible()
            }
        } catch {
            errorMessage = String(localized: "初始化失败：") + error.localizedDescription
        }
    }

    func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        do {
            user = try await authService.handleAppleSignIn(result: result)
            preferences = try preferencesStore.loadPreferences(userID: user?.userID)
            selectedDate = max(Date().startOfDay, availableStartDate)
            analyticsCustomDateRange = defaultAnalyticsCustomRange(startingAt: availableStartDate)
            try loadAllRecords(for: user?.userID ?? "")
            if let user {
                await refreshFromCloudIfNeeded(for: user)
            }
            try loadSelectedRecord()
        } catch {
            errorMessage = loginErrorMessage(from: error)
        }
    }

    func prepareAppleSignIn(_ request: ASAuthorizationAppleIDRequest) {
        authService.prepareAppleSignIn(request)
    }

    func continueAsGuest() async {
        do {
            user = try authService.continueAsGuest()
            preferences = try preferencesStore.loadPreferences(userID: user?.userID)
            selectedDate = max(Date().startOfDay, availableStartDate)
            analyticsCustomDateRange = defaultAnalyticsCustomRange(startingAt: availableStartDate)
            try loadAllRecords(for: user?.userID ?? "")
            if let user {
                await refreshFromCloudIfNeeded(for: user)
            }
            try loadSelectedRecord()
        } catch {
            errorMessage = String(localized: "进入游客模式失败：") + error.localizedDescription
        }
    }

    func updateDisplayName(_ name: String) async {
        guard let user else { return }
        do {
            self.user = try authService.updateDisplayName(name, for: user)
            if let updatedUser = self.user, !updatedUser.isGuest, cloudSyncService.isAvailable {
                try await cloudSyncService.pushProfile(updatedUser)
            }
        } catch {
            errorMessage = String(localized: "修改昵称失败：") + error.localizedDescription
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
            errorMessage = String(localized: "退出失败：") + error.localizedDescription
        }
    }

    private func loginErrorMessage(from error: Error) -> String {
        let nsError = error as NSError
        let loweredDescription = nsError.localizedDescription.lowercased()

        #if DEBUG
        print("Apple sign-in failed:", nsError)
        print("Apple sign-in userInfo:", nsError.userInfo)
        #endif

        if nsError.domain == AuthErrorDomain {
            switch AuthErrorCode(rawValue: nsError.code) {
            case .internalError:
                return String(localized: "登录失败：Firebase Auth 已收到 Apple 登录结果，但服务端配置还不完整。请检查 Firebase Authentication 里是否启用了 Apple，并确认 Apple Team ID、Key ID、Private Key 都已配置。")
            case .invalidCredential:
                return String(localized: "登录失败：Apple 登录凭证无效，请重新试一次。")
            case .missingOrInvalidNonce:
                return String(localized: "登录失败：登录请求已过期，请重新点一次 Apple 登录。")
            case .appNotAuthorized:
                return String(localized: "登录失败：当前 App 还没有在 Firebase / Apple 侧完成授权配置。")
            case .operationNotAllowed:
                return String(localized: "登录失败：Firebase Authentication 里还没有启用 Apple 登录。")
            default:
                break
            }
        }

        if loweredDescription.contains("internal error has occurred") {
            return String(localized: "登录失败：Firebase 已初始化，但 Apple 登录的 Firebase Authentication 配置还不完整。请到 Firebase Console 的 Authentication -> Sign-in method -> Apple，确认已启用，并填写 Apple Team ID、Key ID 和 Private Key。")
        }

        return String(localized: "登录失败：") + error.localizedDescription
    }

    func selectDate(_ date: Date) async {
        let clamped = min(max(date.startOfDay, availableStartDate), Date().startOfDay)
        selectedDate = clamped
        do {
            try loadSelectedRecord()
        } catch {
            errorMessage = String(localized: "加载记录失败：") + error.localizedDescription
        }
    }

    func updateSleep(bedtime: Date?, wakeTime: Date?) async {
        guard canEditSelectedDate else { return }
        dailyRecord.sleepRecord.bedtimePreviousNight = bedtime
        dailyRecord.sleepRecord.wakeTimeCurrentDay = wakeTime
        dailyRecord.sleepRecord.source = .manual
        persistCurrentRecord()
    }

    func updateBedtime(_ bedtime: Date?) async {
        await updateSleep(
            bedtime: bedtime,
            wakeTime: dailyRecord.sleepRecord.wakeTimeCurrentDay
        )
    }

    func updateWakeTime(_ wakeTime: Date?) async {
        await updateSleep(
            bedtime: dailyRecord.sleepRecord.bedtimePreviousNight,
            wakeTime: wakeTime
        )
    }

    func updateBedtimeSchedule(_ schedule: BedtimeSchedule) async {
        preferences.bedtimeSchedule = schedule
        dailyRecord.sleepRecord.targetBedtime = schedule.target(for: selectedDate)
        persistPreferences()
        persistCurrentRecord()
        await syncPreferencesToCloudIfNeeded()
    }

    func updateAppLanguage(_ language: AppLanguage) async {
        preferences.appLanguage = language
        persistPreferences()
        await syncPreferencesToCloudIfNeeded()
    }

    func updateAppearanceMode(_ mode: AppearanceMode) async {
        preferences.appearanceMode = mode
        persistPreferences()
        await syncPreferencesToCloudIfNeeded()
    }

    func updateAnalyticsCustomization(_ customization: AnalyticsCustomization) async {
        preferences.analyticsCustomization = customization
        persistPreferences()
        await syncPreferencesToCloudIfNeeded()
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
            await syncCurrentRecordToCloudIfNeeded()
        } catch {
            errorMessage = String(localized: "保存餐食失败：") + error.localizedDescription
        }
    }

    func canDeleteMealEntry(_ entry: MealEntry) -> Bool {
        !isDefaultMealEntry(entry)
    }

    func deleteMeal(_ entry: MealEntry) async {
        guard canEditSelectedDate, canDeleteMealEntry(entry) else { return }
        do {
            if let photoURL = entry.photoURL {
                try photoStorageService.deletePhoto(at: photoURL)
            }
            dailyRecord.meals.removeAll { $0.id == entry.id }
            persistCurrentRecord()
            await syncCurrentRecordToCloudIfNeeded()
        } catch {
            errorMessage = String(localized: "删除餐食失败：") + error.localizedDescription
        }
    }

    func clearMealRecord(_ entry: MealEntry) async {
        guard canEditSelectedDate else { return }
        do {
            if let photoURL = entry.photoURL {
                try photoStorageService.deletePhoto(at: photoURL)
            }
            if canDeleteMealEntry(entry) {
                dailyRecord.meals.removeAll { $0.id == entry.id }
                persistCurrentRecord()
                await syncCurrentRecordToCloudIfNeeded()
                return
            }
            var updatedEntry = entry
            updatedEntry.status = .empty
            updatedEntry.time = nil
            updatedEntry.photoURL = nil
            if let index = dailyRecord.meals.firstIndex(where: { $0.id == updatedEntry.id }) {
                dailyRecord.meals[index] = updatedEntry
            } else {
                dailyRecord.meals.append(updatedEntry)
            }
            persistCurrentRecord()
            await syncCurrentRecordToCloudIfNeeded()
        } catch {
            errorMessage = String(localized: "删除记录失败：") + error.localizedDescription
        }
    }

    func removeMealPhoto(_ entry: MealEntry) async {
        guard canEditSelectedDate else { return }
        do {
            if let photoURL = entry.photoURL {
                try photoStorageService.deletePhoto(at: photoURL)
            }
            var updatedEntry = entry
            updatedEntry.photoURL = nil
            updatedEntry.status = updatedEntry.time == nil ? .empty : .logged
            if let index = dailyRecord.meals.firstIndex(where: { $0.id == updatedEntry.id }) {
                dailyRecord.meals[index] = updatedEntry
            } else {
                dailyRecord.meals.append(updatedEntry)
            }
            persistCurrentRecord()
            await syncCurrentRecordToCloudIfNeeded()
        } catch {
            errorMessage = String(localized: "删除照片失败：") + error.localizedDescription
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
            await syncCurrentRecordToCloudIfNeeded()
        } catch {
            errorMessage = String(localized: "更新餐食失败：") + error.localizedDescription
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
        await syncCurrentRecordToCloudIfNeeded()
    }

    func deleteShower(_ shower: ShowerEntry) async {
        guard canEditSelectedDate else { return }
        dailyRecord.showers.removeAll { $0.id == shower.id }
        persistCurrentRecord()
        await syncCurrentRecordToCloudIfNeeded()
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
        await syncPreferencesToCloudIfNeeded()
        await syncCurrentRecordToCloudIfNeeded()
    }

    func deleteDefaultMealSlot(_ slot: MealSlot) async {
        guard !slot.isDefault else { return }
        preferences.defaultMealSlots.removeAll { $0.id == slot.id }
        dailyRecord.meals.removeAll { $0.mealKind == .custom && $0.customTitle == slot.title && $0.status == .empty }
        persistPreferences()
        persistCurrentRecord()
        await syncPreferencesToCloudIfNeeded()
        await syncCurrentRecordToCloudIfNeeded()
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
        await syncCurrentRecordToCloudIfNeeded()
        await syncPreferencesToCloudIfNeeded()
    }

    func toggleHealthKitSync(_ enabled: Bool) async {
        if enabled {
            do {
                try await healthSyncAdapter.requestAuthorization()
                preferences.healthKitSyncEnabled = true
                persistPreferences()
                await syncPreferencesToCloudIfNeeded()
                await syncHealthKitForCurrentDate()
            } catch {
                errorMessage = String(localized: "HealthKit 授权失败：") + error.localizedDescription
            }
        } else {
            preferences.healthKitSyncEnabled = false
            persistPreferences()
            await syncPreferencesToCloudIfNeeded()
        }
    }

    func syncHealthKitForCurrentDate() async {
        guard preferences.healthKitSyncEnabled, let user else { return }
        // Don't overwrite user's manual edits
        guard dailyRecord.sleepRecord.source != .manual else { return }
        do {
            guard let hkSleep = try await healthSyncAdapter.fetchSleepData(
                for: selectedDate,
                after: user.createdAt
            ) else { return }

            dailyRecord.sleepRecord.bedtimePreviousNight = hkSleep.bedtimePreviousNight
            dailyRecord.sleepRecord.wakeTimeCurrentDay = hkSleep.wakeTimeCurrentDay
            dailyRecord.sleepRecord.stageIntervals = hkSleep.stageIntervals
            dailyRecord.sleepRecord.source = .healthKit
            persistCurrentRecord()
        } catch {
            errorMessage = String(localized: "HealthKit 同步失败：") + error.localizedDescription
        }
    }

    func formattedTargetBedtime() -> String {
        preferences.bedtimeSchedule.target(for: selectedDate)?.displayTime ?? "--:--"
    }

    func updateAnalyticsRange(_ range: AnalyticsRange) {
        analyticsRange = range
    }

    func updateAnalyticsCustomDateRange(_ range: ClosedRange<Date>) {
        let lower = max(range.lowerBound.startOfDay, availableStartDate)
        let upper = min(range.upperBound.startOfDay, Date().startOfDay)
        analyticsCustomDateRange = min(lower, upper)...max(lower, upper)
        analyticsRange = .custom
    }

    func bedtimeScheduleSummary() -> String {
        preferences.bedtimeSchedule.summary()
    }

    private func isDefaultMealEntry(_ entry: MealEntry) -> Bool {
        preferences.defaultMealSlots.contains { slot in
            if slot.kind == .custom {
                return entry.mealKind == .custom && entry.customTitle == slot.title
            }
            return entry.mealKind == slot.kind
        }
    }

    private func loadSelectedRecord() throws {
        guard let user else {
            dailyRecord = DailyRecord.empty(for: selectedDate, preferences: preferences)
            return
        }
        var record = try repository.loadRecord(for: selectedDate, preferences: preferences, userID: user.userID)
        record.sleepRecord.targetBedtime = preferences.bedtimeSchedule.target(for: selectedDate)
        dailyRecord = mergedRecord(record, with: preferences)
        updateSunTimesIfPossible()
        Task { await syncHealthKitForCurrentDate() }
    }

    private func loadAllRecords(for userID: String) throws {
        allRecords = try repository.loadAllRecords(userID: userID)
            .filter { $0.date >= availableStartDate }
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
            errorMessage = String(localized: "保存记录失败：") + error.localizedDescription
        }
    }

    private func persistPreferences() {
        do {
            preferences.locationPermissionState = locationService.permissionState
            try preferencesStore.savePreferences(preferences, userID: user?.userID)
        } catch {
            errorMessage = String(localized: "保存偏好失败：") + error.localizedDescription
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

    private func refreshFromCloudIfNeeded(for user: UserAccount) async {
        guard !user.isGuest, cloudSyncService.isAvailable else { return }
        do {
            let payload = try await cloudSyncService.bootstrap(
                user: user,
                localPreferences: preferences,
                localRecords: allRecords
            )

            if let remotePreferences = payload.preferences {
                preferences = remotePreferences
                try preferencesStore.savePreferences(remotePreferences, userID: user.userID)
            }

            if !payload.records.isEmpty {
                let store = LocalJSONStore()
                var database = try store.load()
                let localRecordMap = database.recordsByUser[user.userID] ?? [:]
                let remoteRecordMap = Dictionary(
                    uniqueKeysWithValues: payload.records.map { ($0.date.storageKey(), $0) }
                )
                var merged = remoteRecordMap
                for (key, localRecord) in localRecordMap {
                    guard let remoteRecord = merged[key] else {
                        merged[key] = localRecord
                        continue
                    }
                    // Keep local record if it has local photo paths that cloud doesn't have
                    var mergedRecord = remoteRecord
                    for i in mergedRecord.meals.indices {
                        if mergedRecord.meals[i].photoURL == nil,
                           let localMeal = localRecord.meals.first(where: { $0.id == mergedRecord.meals[i].id }),
                           let localPhoto = localMeal.photoURL,
                           FileManager.default.fileExists(atPath: localPhoto) {
                            mergedRecord.meals[i].photoURL = localPhoto
                        }
                    }
                    merged[key] = mergedRecord
                }
                database.recordsByUser[user.userID] = merged
                try store.save(database)
                allRecords = merged.values.sorted { $0.date < $1.date }
            }
        } catch {
            errorMessage = String(localized: "云端同步失败：") + error.localizedDescription
        }
    }

    private func syncPreferencesToCloudIfNeeded() async {
        guard let user, !user.isGuest, cloudSyncService.isAvailable else { return }
        do {
            try await cloudSyncService.pushPreferences(preferences, user: user)
        } catch {
            errorMessage = String(localized: "云端偏好同步失败：") + error.localizedDescription
        }
    }

    private func syncCurrentRecordToCloudIfNeeded() async {
        guard let user, !user.isGuest, cloudSyncService.isAvailable else { return }
        do {
            try await cloudSyncService.pushRecord(dailyRecord, user: user)
        } catch {
            errorMessage = String(localized: "云端记录同步失败：") + error.localizedDescription
        }
    }

    private func defaultAnalyticsCustomRange(startingAt start: Date) -> ClosedRange<Date> {
        let lower = max(start.startOfDay, Date().startOfDay.adding(days: -29))
        return lower...Date().startOfDay
    }
}

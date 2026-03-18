import AuthenticationServices
import Combine
import CoreLocation
import FirebaseAuth
import Foundation
import SwiftUI
import UIKit

@MainActor
final class AppViewModel: ObservableObject {
    private static let minimumAnalyticsRecordStreak = 7
    private static let didMigrateTimeDisplayModeDefaultKey = "dailylogs.didMigrateTimeDisplayModeDefault"

    enum CloudEncryptionState: Equatable {
        case unavailable
        case disabled
        case locked
        case unlocked
    }

    @Published private(set) var user: UserAccount?
    @Published var selectedDate: Date
    @Published private(set) var dailyRecord: DailyRecord
    @Published private(set) var allRecords: [DailyRecord] = []
    @Published private(set) var preferences: UserPreferences
    @Published var analyticsRange: AnalyticsRange = .week
    @Published var analyticsCustomDateRange: ClosedRange<Date> = Date().startOfDay.adding(days: -29)...Date().startOfDay
    @Published private(set) var isBootstrapped = false
    @Published var errorMessage: String?
    @Published var languageRefreshID = UUID()
    @Published private(set) var cloudEncryptionState: CloudEncryptionState = .unavailable
    @Published var shouldPresentCloudUnlock = false

    let locationService: LocationService

    private let authService: AuthService
    private let repository: DailyRecordRepository
    private let preferencesStore: PreferencesStore
    private let photoStorageService: PhotoStorageService
    private let sunTimesService: SunTimesService
    private var healthSyncAdapter: HealthSyncAdapter
    private let cloudSyncService: CloudSyncService
    private var cancellables = Set<AnyCancellable>()

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
        bindLocationService()
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

    var canDisplayAnalytics: Bool {
        longestAnalyticsRecordStreak >= Self.minimumAnalyticsRecordStreak
    }

    var longestAnalyticsRecordStreak: Int {
        Self.longestRecordStreak(in: allRecords)
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
            preferences = hydratedPreferences(from: try preferencesStore.loadPreferences(userID: user?.userID))
            persistPreferences()
            applyCurrentLanguage()
            if let user {
                selectedDate = max(selectedDate, user.createdAt.startOfDay)
                analyticsCustomDateRange = defaultAnalyticsCustomRange(startingAt: user.createdAt)
                try loadAllRecords(for: user.userID)
                await refreshFromCloudIfNeeded(for: user)
                await refreshCloudEncryptionState()
                try loadSelectedRecord()
                updateSunTimesIfPossible()
                refreshLocationIfAuthorized()
            }
        } catch {
            errorMessage = NSLocalizedString("初始化失败：", comment: "") + error.localizedDescription
        }
    }

    func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        do {
            user = try await authService.handleAppleSignIn(result: result)
            preferences = hydratedPreferences(from: try preferencesStore.loadPreferences(userID: user?.userID))
            persistPreferences()
            applyCurrentLanguage()
            selectedDate = max(Date().startOfDay, availableStartDate)
            analyticsCustomDateRange = defaultAnalyticsCustomRange(startingAt: availableStartDate)
            try loadAllRecords(for: user?.userID ?? "")
            if let user {
                await refreshFromCloudIfNeeded(for: user)
                await refreshCloudEncryptionState()
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
            preferences = hydratedPreferences(from: try preferencesStore.loadPreferences(userID: user?.userID))
            persistPreferences()
            applyCurrentLanguage()
            selectedDate = max(Date().startOfDay, availableStartDate)
            analyticsCustomDateRange = defaultAnalyticsCustomRange(startingAt: availableStartDate)
            try loadAllRecords(for: user?.userID ?? "")
            if let user {
                await refreshFromCloudIfNeeded(for: user)
                await refreshCloudEncryptionState()
            }
            try loadSelectedRecord()
        } catch {
            errorMessage = NSLocalizedString("进入游客模式失败：", comment: "") + error.localizedDescription
        }
    }

    func updateDisplayName(_ name: String) async {
        guard let user else { return }
        do {
            self.user = try authService.updateDisplayName(name, for: user)
            if let updatedUser = self.user, !updatedUser.isGuest, cloudSyncService.isAvailable {
                try await cloudSyncService.pushProfile(updatedUser)
                await refreshCloudEncryptionState()
            }
        } catch {
            errorMessage = NSLocalizedString("修改昵称失败：", comment: "") + error.localizedDescription
        }
    }

    func enableEndToEndEncryption(passphrase: String) async {
        guard let user, !user.isGuest else { return }
        let trimmed = passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            try await cloudSyncService.enableEndToEndEncryption(
                passphrase: trimmed,
                user: user,
                localPreferences: preferences,
                localRecords: allRecords
            )
            cloudEncryptionState = .unlocked
            shouldPresentCloudUnlock = false
        } catch {
            errorMessage = NSLocalizedString("启用加密同步失败：", comment: "") + error.localizedDescription
        }
    }

    func unlockEndToEndEncryption(passphrase: String) async {
        guard let user, !user.isGuest else { return }
        let trimmed = passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            try await cloudSyncService.unlockEndToEndEncryption(passphrase: trimmed, user: user)
            shouldPresentCloudUnlock = false
            await refreshCloudEncryptionState()
            await refreshFromCloudIfNeeded(for: user)
            try loadSelectedRecord()
        } catch {
            errorMessage = NSLocalizedString("解锁加密同步失败：", comment: "") + error.localizedDescription
        }
    }

    func lockEndToEndEncryptionLocally() async {
        guard let user, !user.isGuest else { return }
        cloudSyncService.lockEndToEndEncryption(for: user)
        cloudEncryptionState = .locked
    }

    func signOut() async {
        do {
            try authService.signOut()
            user = nil
            allRecords = []
            selectedDate = .now.startOfDay
            dailyRecord = DailyRecord.empty(for: selectedDate, preferences: preferences)
            cloudEncryptionState = .unavailable
            shouldPresentCloudUnlock = false
            Task { await refreshRemotePhotoCache() }
        } catch {
            errorMessage = NSLocalizedString("退出失败：", comment: "") + error.localizedDescription
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
                return NSLocalizedString("登录失败：Firebase Auth 已收到 Apple 登录结果，但服务端配置还不完整。请检查 Firebase Authentication 里是否启用了 Apple，并确认 Apple Team ID、Key ID、Private Key 都已配置。", comment: "")
            case .invalidCredential:
                return NSLocalizedString("登录失败：Apple 登录凭证无效，请重新试一次。", comment: "")
            case .missingOrInvalidNonce:
                return NSLocalizedString("登录失败：登录请求已过期，请重新点一次 Apple 登录。", comment: "")
            case .appNotAuthorized:
                return NSLocalizedString("登录失败：当前 App 还没有在 Firebase / Apple 侧完成授权配置。", comment: "")
            case .operationNotAllowed:
                return NSLocalizedString("登录失败：Firebase Authentication 里还没有启用 Apple 登录。", comment: "")
            default:
                break
            }
        }

        if loweredDescription.contains("internal error has occurred") {
            return NSLocalizedString("登录失败：Firebase 已初始化，但 Apple 登录的 Firebase Authentication 配置还不完整。请到 Firebase Console 的 Authentication -> Sign-in method -> Apple，确认已启用，并填写 Apple Team ID、Key ID 和 Private Key。", comment: "")
        }

        return NSLocalizedString("登录失败：", comment: "") + error.localizedDescription
    }

    func selectDate(_ date: Date) async {
        let clamped = min(max(date.startOfDay, availableStartDate), Date().startOfDay)
        selectedDate = clamped
        do {
            try loadSelectedRecord()
        } catch {
            errorMessage = NSLocalizedString("加载记录失败：", comment: "") + error.localizedDescription
        }
    }

    func updateSleep(bedtime: Date?, wakeTime: Date?) async {
        guard canEditSelectedDate else { return }
        dailyRecord.sleepRecord.bedtimePreviousNight = bedtime
        dailyRecord.sleepRecord.wakeTimeCurrentDay = wakeTime
        dailyRecord.sleepRecord.source = .manual
        dailyRecord.sleepRecord.timeZoneIdentifier = (bedtime != nil || wakeTime != nil)
            ? editedTimeZoneIdentifier(for: dailyRecord.sleepRecord.timeZoneIdentifier)
            : nil
        persistCurrentRecord()
        await syncCurrentRecordToCloudIfNeeded()
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

    func updateSleepNote(_ note: String?) async {
        guard canEditSelectedDate else { return }
        dailyRecord.sleepRecord.note = trimmedNote(note)
        persistCurrentRecord()
        await syncCurrentRecordToCloudIfNeeded()
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
        applyCurrentLanguage()
        persistPreferences()
        await syncPreferencesToCloudIfNeeded()
    }

    static func applyProcessLocale(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: "dailylogs.appLanguage")
        if let codes = language.appleLanguageCode {
            UserDefaults.standard.set(codes, forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
        if let localeIdentifier = language.appleLocaleIdentifier {
            UserDefaults.standard.set(localeIdentifier, forKey: "AppleLocale")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLocale")
        }
        UserDefaults.standard.synchronize()
    }

    static func restoreProcessLocale() {
        guard let raw = UserDefaults.standard.string(forKey: "dailylogs.appLanguage"),
              let lang = AppLanguage(rawValue: raw) else { return }
        applyProcessLocale(lang)
        Bundle.configureLanguageOverride(for: lang)
    }

    static func persistedProcessLanguage() -> AppLanguage? {
        guard let raw = UserDefaults.standard.string(forKey: "dailylogs.appLanguage") else { return nil }
        return AppLanguage(rawValue: raw)
    }

    private func applyCurrentLanguage(refreshUI: Bool = true) {
        Self.applyProcessLocale(preferences.appLanguage)
        Bundle.configureLanguageOverride(for: preferences.appLanguage)
        if refreshUI {
            languageRefreshID = UUID()
        }
    }

    private func hydratedPreferences(from loaded: UserPreferences) -> UserPreferences {
        var preferences = loaded
        if let processLanguage = Self.persistedProcessLanguage() {
            preferences.appLanguage = processLanguage
        }
        if !UserDefaults.standard.bool(forKey: Self.didMigrateTimeDisplayModeDefaultKey) {
            preferences.timeDisplayMode = .recorded
            UserDefaults.standard.set(true, forKey: Self.didMigrateTimeDisplayModeDefaultKey)
        }
        return preferences
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

    func updateTimeDisplayMode(_ mode: TimeDisplayMode) async {
        guard preferences.timeDisplayMode != mode else { return }
        preferences.timeDisplayMode = mode
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
                    try deletePhotoIfLocal(at: path)
                }
                updatedEntry.photoURL = try photoStorageService.savePhoto(image)
            } else if let oldPhotoURL = existingEntry?.photoURL, updatedEntry.photoURL == nil {
                try deletePhotoIfLocal(at: oldPhotoURL)
            }

            if updatedEntry.time != nil || updatedEntry.hasPhoto {
                updatedEntry.status = .logged
                updatedEntry.timeZoneIdentifier = editedTimeZoneIdentifier(for: existingEntry?.timeZoneIdentifier ?? updatedEntry.timeZoneIdentifier)
            }
            if let index = dailyRecord.meals.firstIndex(where: { $0.id == updatedEntry.id }) {
                dailyRecord.meals[index] = updatedEntry
            } else {
                dailyRecord.meals.append(updatedEntry)
            }
            persistCurrentRecord()
            await syncCurrentRecordToCloudIfNeeded()
        } catch {
            errorMessage = NSLocalizedString("保存餐食失败：", comment: "") + error.localizedDescription
        }
    }

    func canDeleteMealEntry(_ entry: MealEntry) -> Bool {
        !isDefaultMealEntry(entry)
    }

    func deleteMeal(_ entry: MealEntry) async {
        guard canEditSelectedDate, canDeleteMealEntry(entry) else { return }
        do {
            if let photoURL = entry.photoURL {
                try deletePhotoIfLocal(at: photoURL)
            }
            dailyRecord.meals.removeAll { $0.id == entry.id }
            persistCurrentRecord()
            await syncCurrentRecordToCloudIfNeeded()
        } catch {
            errorMessage = NSLocalizedString("删除餐食失败：", comment: "") + error.localizedDescription
        }
    }

    func clearMealRecord(_ entry: MealEntry) async {
        guard canEditSelectedDate else { return }
        do {
            if let photoURL = entry.photoURL {
                try deletePhotoIfLocal(at: photoURL)
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
            updatedEntry.timeZoneIdentifier = nil
            if let index = dailyRecord.meals.firstIndex(where: { $0.id == updatedEntry.id }) {
                dailyRecord.meals[index] = updatedEntry
            } else {
                dailyRecord.meals.append(updatedEntry)
            }
            persistCurrentRecord()
            await syncCurrentRecordToCloudIfNeeded()
        } catch {
            errorMessage = NSLocalizedString("删除记录失败：", comment: "") + error.localizedDescription
        }
    }

    func removeMealPhoto(_ entry: MealEntry) async {
        guard canEditSelectedDate else { return }
        do {
            if let photoURL = entry.photoURL {
                try deletePhotoIfLocal(at: photoURL)
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
            errorMessage = NSLocalizedString("删除照片失败：", comment: "") + error.localizedDescription
        }
    }

    func skipMeal(_ entry: MealEntry) async {
        guard canEditSelectedDate else { return }
        do {
            if let photoURL = entry.photoURL {
                try deletePhotoIfLocal(at: photoURL)
            }
            var updatedEntry = entry
            updatedEntry.status = .skipped
            updatedEntry.time = nil
            updatedEntry.photoURL = nil
            updatedEntry.timeZoneIdentifier = nil
            if let index = dailyRecord.meals.firstIndex(where: { $0.id == updatedEntry.id }) {
                dailyRecord.meals[index] = updatedEntry
            } else {
                dailyRecord.meals.append(updatedEntry)
            }
            persistCurrentRecord()
            await syncCurrentRecordToCloudIfNeeded()
        } catch {
            errorMessage = NSLocalizedString("更新餐食失败：", comment: "") + error.localizedDescription
        }
    }

    func saveShower(_ shower: ShowerEntry) async {
        guard canEditSelectedDate else { return }
        var updatedShower = shower
        updatedShower.timeZoneIdentifier = editedTimeZoneIdentifier(for: shower.timeZoneIdentifier)
        updatedShower.note = trimmedNote(shower.note)
        if let index = dailyRecord.showers.firstIndex(where: { $0.id == shower.id }) {
            dailyRecord.showers[index] = updatedShower
        } else {
            dailyRecord.showers.append(updatedShower)
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

    func saveBowelMovement(_ entry: BowelMovementEntry) async {
        guard canEditSelectedDate else { return }
        var updated = entry
        updated.timeZoneIdentifier = editedTimeZoneIdentifier(for: entry.timeZoneIdentifier)
        updated.note = trimmedNote(entry.note)
        if let index = dailyRecord.bowelMovements.firstIndex(where: { $0.id == entry.id }) {
            dailyRecord.bowelMovements[index] = updated
        } else {
            dailyRecord.bowelMovements.append(updated)
            dailyRecord.bowelMovements.sort { $0.time < $1.time }
        }
        persistCurrentRecord()
        await syncCurrentRecordToCloudIfNeeded()
    }

    func deleteBowelMovement(_ entry: BowelMovementEntry) async {
        guard canEditSelectedDate else { return }
        dailyRecord.bowelMovements.removeAll { $0.id == entry.id }
        persistCurrentRecord()
        await syncCurrentRecordToCloudIfNeeded()
    }

    func saveSexualActivity(_ entry: SexualActivityEntry) async {
        guard canEditSelectedDate else { return }
        var updated = entry
        updated.note = trimmedNote(entry.note)
        if updated.time != nil {
            updated.timeZoneIdentifier = editedTimeZoneIdentifier(for: entry.timeZoneIdentifier)
        }
        if let index = dailyRecord.sexualActivities.firstIndex(where: { $0.id == entry.id }) {
            dailyRecord.sexualActivities[index] = updated
        } else {
            dailyRecord.sexualActivities.append(updated)
        }
        persistCurrentRecord()
        await syncCurrentRecordToCloudIfNeeded()
    }

    func deleteSexualActivity(_ entry: SexualActivityEntry) async {
        guard canEditSelectedDate else { return }
        dailyRecord.sexualActivities.removeAll { $0.id == entry.id }
        persistCurrentRecord()
        await syncCurrentRecordToCloudIfNeeded()
    }

    func updateVisibleHomeSections(_ sections: [HomeSectionKind]) async {
        preferences.visibleHomeSections = sections
        persistPreferences()
        await syncPreferencesToCloudIfNeeded()
    }

    func updateShowMasturbationOption(_ enabled: Bool) async {
        preferences.showMasturbationOption = enabled
        persistPreferences()
        await syncPreferencesToCloudIfNeeded()
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
        preferences.defaultMealSlots.removeAll { $0.id == slot.id }
        dailyRecord.meals.removeAll {
            mealEntry($0, matches: slot) && $0.status == .empty
        }
        persistPreferences()
        persistCurrentRecord()
        await syncPreferencesToCloudIfNeeded()
        await syncCurrentRecordToCloudIfNeeded()
    }

    func requestLocationAccess() {
        locationService.requestAccess()
        preferences.locationPermissionState = locationService.permissionState
        persistPreferences()
    }

    func refreshSunTimes() async {
        refreshLocationIfAuthorized()
        updateSunTimesIfPossible()
        persistCurrentRecord()
        persistPreferences()
        await syncCurrentRecordToCloudIfNeeded()
        await syncPreferencesToCloudIfNeeded()
    }

    func refreshHomeData() async {
        if let user {
            await refreshFromCloudIfNeeded(for: user)
        }
        do {
            try loadSelectedRecord()
        } catch {
            errorMessage = NSLocalizedString("刷新记录失败：", comment: "") + error.localizedDescription
        }
        refreshLocationIfAuthorized()
        await syncHealthKitForCurrentDate()
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
                errorMessage = NSLocalizedString("HealthKit 授权失败：", comment: "") + error.localizedDescription
            }
        } else {
            preferences.healthKitSyncEnabled = false
            persistPreferences()
            await syncPreferencesToCloudIfNeeded()
        }
    }

    func syncHealthKitForCurrentDate(overwritingExistingData: Bool = false) async {
        guard preferences.healthKitSyncEnabled, let user else { return }
        guard overwritingExistingData || !dailyRecord.sleepRecord.blocksHealthKitSync else { return }
        do {
            guard let hkSleep = try await healthSyncAdapter.fetchSleepData(
                for: selectedDate,
                after: user.createdAt
            ) else { return }

            dailyRecord.sleepRecord.bedtimePreviousNight = hkSleep.bedtimePreviousNight
            dailyRecord.sleepRecord.wakeTimeCurrentDay = hkSleep.wakeTimeCurrentDay
            dailyRecord.sleepRecord.stageIntervals = hkSleep.stageIntervals
            dailyRecord.sleepRecord.source = .healthKit
            dailyRecord.sleepRecord.timeZoneIdentifier = TimeZone.autoupdatingCurrent.identifier
            persistCurrentRecord()
            await syncCurrentRecordToCloudIfNeeded()
        } catch {
            errorMessage = NSLocalizedString("HealthKit 同步失败：", comment: "") + error.localizedDescription
        }
    }

    func overwriteSleepWithHealthKit() async {
        await syncHealthKitForCurrentDate(overwritingExistingData: true)
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
        preferences.defaultMealSlots.contains { mealEntry(entry, matches: $0) }
    }

    private func trimmedNote(_ note: String?) -> String? {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private func loadSelectedRecord() throws {
        guard let user else {
            dailyRecord = DailyRecord.empty(for: selectedDate, preferences: preferences)
            return
        }
        var record = try repository.loadRecord(for: selectedDate, preferences: preferences, userID: user.userID)
        record = record.backfillingRecordedTimeZones(TimeZone.autoupdatingCurrent.identifier)
        record.sleepRecord.targetBedtime = preferences.bedtimeSchedule.target(for: selectedDate)
        dailyRecord = mergedRecord(record, with: preferences)
        updateSunTimesIfPossible()
        refreshLocationIfAuthorized()
        Task { await syncHealthKitForCurrentDate() }
    }

    private func loadAllRecords(for userID: String) throws {
        let records = try repository.loadAllRecords(userID: userID)
            .filter { $0.date >= availableStartDate }
        allRecords = try migrateRecordedTimeZonesIfNeeded(in: records, userID: userID)
        Task { await refreshRemotePhotoCache() }
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
            errorMessage = NSLocalizedString("保存记录失败：", comment: "") + error.localizedDescription
        }
    }

    private func persistPreferences() {
        do {
            preferences.locationPermissionState = locationService.permissionState
            try preferencesStore.savePreferences(preferences, userID: user?.userID)
        } catch {
            errorMessage = NSLocalizedString("保存偏好失败：", comment: "") + error.localizedDescription
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

            if let remoteProfile = payload.profile,
               let remoteDisplayName = remoteProfile.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !remoteDisplayName.isEmpty,
               remoteDisplayName != user.displayName {
                self.user = try authService.updateDisplayName(remoteDisplayName, for: user)
            }

            if let remotePreferences = payload.preferences {
                preferences = hydratedPreferences(from: remotePreferences)
                applyCurrentLanguage()
                try preferencesStore.savePreferences(preferences, userID: user.userID)
            }

            if !payload.records.isEmpty {
                let store = LocalJSONStore()
                var database = try store.load()
                let localRecordMap = database.recordsByUser[user.userID] ?? [:]
                let remoteRecordMap = Self.recordsByStorageKey(payload.records)
                var merged = remoteRecordMap
                for (key, localRecord) in localRecordMap {
                    guard let remoteRecord = merged[key] else {
                        merged[key] = localRecord
                        continue
                    }
                    // Prefer the local record on conflicts so newer offline edits
                    // aren't overwritten by stale cloud data. Backfill remote photo
                    // URLs when the local copy doesn't have one yet.
                    var mergedRecord = localRecord
                    for i in mergedRecord.meals.indices {
                        if let localPhoto = mergedRecord.meals[i].photoURL,
                           FileManager.default.fileExists(atPath: localPhoto) {
                            continue
                        }

                        if let remoteMeal = remoteRecord.meals.first(where: { $0.id == mergedRecord.meals[i].id }),
                           let remotePhoto = remoteMeal.photoURL {
                            mergedRecord.meals[i].photoURL = remotePhoto
                        }
                    }
                    merged[key] = mergedRecord.backfillingRecordedTimeZones(TimeZone.autoupdatingCurrent.identifier)
                }
                database.recordsByUser[user.userID] = merged.mapValues {
                    $0.backfillingRecordedTimeZones(TimeZone.autoupdatingCurrent.identifier)
                }
                try store.save(database)
                allRecords = database.recordsByUser[user.userID]?.values.sorted { $0.date < $1.date } ?? []
                await refreshRemotePhotoCache()
            }
            shouldPresentCloudUnlock = false
        } catch {
            if let securityError = error as? CloudSyncSecurityError,
               securityError == .encryptedSyncLocked {
                cloudEncryptionState = .locked
                shouldPresentCloudUnlock = true
            } else {
                errorMessage = NSLocalizedString("云端同步失败：", comment: "") + error.localizedDescription
            }
        }
    }

    private func syncPreferencesToCloudIfNeeded() async {
        guard let user, !user.isGuest, cloudSyncService.isAvailable else { return }
        do {
            try await cloudSyncService.pushPreferences(preferences, user: user)
        } catch {
            if let securityError = error as? CloudSyncSecurityError,
               securityError == .encryptedSyncLocked {
                cloudEncryptionState = .locked
                shouldPresentCloudUnlock = true
            } else {
                errorMessage = NSLocalizedString("云端偏好同步失败：", comment: "") + error.localizedDescription
            }
        }
    }

    private func syncCurrentRecordToCloudIfNeeded() async {
        guard let user, !user.isGuest, cloudSyncService.isAvailable else { return }
        do {
            try await cloudSyncService.pushRecord(dailyRecord, user: user)
        } catch {
            if let securityError = error as? CloudSyncSecurityError,
               securityError == .encryptedSyncLocked {
                cloudEncryptionState = .locked
                shouldPresentCloudUnlock = true
            } else {
                errorMessage = NSLocalizedString("云端记录同步失败：", comment: "") + error.localizedDescription
            }
        }
    }

    func refreshCloudEncryptionState() async {
        guard let user, !user.isGuest else {
            cloudEncryptionState = cloudSyncService.isAvailable ? .disabled : .unavailable
            return
        }

        do {
            let snapshot = try await cloudSyncService.protectionSnapshot(for: user)
            switch snapshot.mode {
            case .unavailable:
                cloudEncryptionState = .unavailable
            case .disabled:
                cloudEncryptionState = .disabled
            case .enabled:
                cloudEncryptionState = snapshot.localKeyAvailable ? .unlocked : .locked
            }
            shouldPresentCloudUnlock = cloudEncryptionState == .locked
        } catch {
            cloudEncryptionState = .unavailable
        }
    }

    private func defaultAnalyticsCustomRange(startingAt start: Date) -> ClosedRange<Date> {
        let lower = max(start.startOfDay, Date().startOfDay.adding(days: -29))
        return lower...Date().startOfDay
    }

    private static func longestRecordStreak(in records: [DailyRecord]) -> Int {
        let uniqueDates = Array(Set(records.map { $0.date.startOfDay })).sorted()
        guard let firstDate = uniqueDates.first else { return 0 }

        var longest = 1
        var current = 1
        var previousDate = firstDate
        let calendar = Calendar.current

        for date in uniqueDates.dropFirst() {
            let dayGap = calendar.dateComponents([.day], from: previousDate, to: date).day ?? 0
            current = dayGap == 1 ? current + 1 : 1
            longest = max(longest, current)
            previousDate = date
        }

        return longest
    }

    private func refreshRemotePhotoCache() async {
        await RemotePhotoCache.shared.syncRetention(with: recentRemotePhotoURLs())
    }

    private func recentRemotePhotoURLs() -> [String] {
        let lowerBound = Date().startOfDay.adding(days: -6)
        let urls = allRecords
            .filter { $0.date >= lowerBound }
            .flatMap { record in
                record.meals
                    .compactMap(\.photoURL)
                    .filter(Self.isRemotePhotoURL)
            }

        return Array(Set(urls))
    }

    private static func isRemotePhotoURL(_ urlString: String) -> Bool {
        urlString.hasPrefix("http://")
            || urlString.hasPrefix("https://")
            || SecureCloudPhotoReference.isSecureReference(urlString)
    }

    nonisolated static func recordsByStorageKey(_ records: [DailyRecord]) -> [String: DailyRecord] {
        records.reduce(into: [:]) { partialResult, record in
            let normalized = normalizedRecord(record)
            let key = normalized.date.storageKey()

            if let existing = partialResult[key] {
                partialResult[key] = preferredRecord(between: existing, and: normalized)
            } else {
                partialResult[key] = normalized
            }
        }
    }

    private nonisolated static func normalizedRecord(_ record: DailyRecord) -> DailyRecord {
        var normalized = record
        normalized.date = record.date.startOfDay
        return normalized
    }

    private nonisolated static func preferredRecord(between lhs: DailyRecord, and rhs: DailyRecord) -> DailyRecord {
        let lhsScore = completenessScore(for: lhs)
        let rhsScore = completenessScore(for: rhs)

        if lhsScore != rhsScore {
            return lhsScore > rhsScore ? lhs : rhs
        }

        return lhs.date >= rhs.date ? lhs : rhs
    }

    private nonisolated static func completenessScore(for record: DailyRecord) -> Int {
        var score = 0

        if record.sleepRecord.bedtimePreviousNight != nil {
            score += 2
        }
        if record.sleepRecord.wakeTimeCurrentDay != nil {
            score += 2
        }
        score += record.sleepRecord.stageIntervals.count * 2
        score += record.showers.count
        score += record.bowelMovements.count
        score += record.sexualActivities.count

        for meal in record.meals {
            switch meal.status {
            case .logged:
                score += 2
            case .skipped:
                score += 1
            case .empty:
                break
            }

            if meal.time != nil {
                score += 1
            }
            if meal.photoURL?.isEmpty == false {
                score += 1
            }
        }

        if record.sunTimes != nil {
            score += 1
        }

        return score
    }

    private func bindLocationService() {
        Publishers.CombineLatest3(
            locationService.$latestLocation,
            locationService.$detectedTimeZone,
            locationService.$permissionState
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _, _, permissionState in
            guard let self else { return }
            self.preferences.locationPermissionState = permissionState
            guard permissionState == .authorized else {
                self.dailyRecord.sunTimes = nil
                return
            }
            self.updateSunTimesIfPossible()
        }
        .store(in: &cancellables)
    }

    private func refreshLocationIfAuthorized() {
        guard locationService.permissionState == .authorized else { return }
        locationService.refreshCurrentLocation()
    }

    private func migrateRecordedTimeZonesIfNeeded(in records: [DailyRecord], userID: String) throws -> [DailyRecord] {
        let identifier = TimeZone.autoupdatingCurrent.identifier
        let migrated = records.map { $0.backfillingRecordedTimeZones(identifier) }
        guard migrated != records else { return migrated.sorted { $0.date < $1.date } }
        for record in migrated {
            try repository.saveRecord(record, userID: userID)
        }
        return migrated.sorted { $0.date < $1.date }
    }

    private func mealEntry(_ entry: MealEntry, matches slot: MealSlot) -> Bool {
        if slot.kind == .custom {
            return entry.mealKind == .custom && entry.customTitle == slot.title
        }
        return entry.mealKind == slot.kind
    }

    private func deletePhotoIfLocal(at path: String) throws {
        guard !Self.isRemotePhotoURL(path) else { return }
        try photoStorageService.deletePhoto(at: path)
    }

    func displayedTimeZone(for recordedTimeZoneIdentifier: String?) -> TimeZone {
        switch preferences.timeDisplayMode {
        case .current:
            return .autoupdatingCurrent
        case .recorded:
            if let recordedTimeZoneIdentifier,
               let timeZone = TimeZone(identifier: recordedTimeZoneIdentifier) {
                return timeZone
            }
            return .autoupdatingCurrent
        }
    }

    func displayedClockTime(for date: Date?, recordedTimeZoneIdentifier: String?) -> String {
        guard let date else { return "--:--" }
        return date.displayClockTime(in: displayedTimeZone(for: recordedTimeZoneIdentifier))
    }

    func displayedShortTime(for date: Date, recordedTimeZoneIdentifier: String?) -> String {
        date.displayShortTime(in: displayedTimeZone(for: recordedTimeZoneIdentifier))
    }

    private func editedTimeZoneIdentifier(for recordedTimeZoneIdentifier: String?) -> String {
        switch preferences.timeDisplayMode {
        case .current:
            return TimeZone.autoupdatingCurrent.identifier
        case .recorded:
            return recordedTimeZoneIdentifier ?? TimeZone.autoupdatingCurrent.identifier
        }
    }
}

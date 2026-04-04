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
    @Published var shouldPresentCloudMigration = false
    @Published private(set) var isCloudMigrationInProgress = false
    @Published private(set) var cloudMigrationProgress: Double = 0
    @Published private(set) var cloudMigrationMessage: String?
    @Published private(set) var cloudMigrationError: String?
    @Published private(set) var dailyInsightNarrative: DailyInsightNarrative?
    @Published private(set) var dailyInsightNarrativeDate: Date?
    @Published private(set) var isGeneratingDailyInsightNarrative = false
    @Published private(set) var canGenerateAIInsights = false
    @Published private(set) var isUsingCloudAIProxy = false
    @Published private(set) var aiInsightErrorMessage: String?

    let locationService: LocationService

    private let authService: AuthService
    private let repository: DailyRecordRepository
    private let preferencesStore: PreferencesStore
    private let photoStorageService: PhotoStorageService
    private let sunTimesService: SunTimesService
    private var healthSyncAdapter: HealthSyncAdapter
    private let cloudSyncService: CloudSyncService
    private let aiInsightNarrativeService: AIInsightNarrativeGenerating
    private let openAIKeyStore: OpenAIKeyStoring
    private var cancellables = Set<AnyCancellable>()

    static func live() -> AppViewModel {
        let store = LocalJSONStore()
        let preferences = UserPreferences()
        let openAIKeyStore = OpenAIKeychainStore()
        let cloudAIService = CloudAIInsightService()
        return AppViewModel(
            authService: LocalAuthService(store: store),
            repository: LocalDailyRecordRepository(store: store),
            preferencesStore: LocalPreferencesStore(store: store),
            photoStorageService: LocalPhotoStorageService(),
            sunTimesService: AstronomySunTimesService(),
            healthSyncAdapter: HealthKitService(),
            cloudSyncService: FirebaseCloudSyncService(),
            aiInsightNarrativeService: cloudAIService,
            openAIKeyStore: openAIKeyStore,
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
        aiInsightNarrativeService: AIInsightNarrativeGenerating,
        openAIKeyStore: OpenAIKeyStoring,
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
        self.aiInsightNarrativeService = aiInsightNarrativeService
        self.openAIKeyStore = openAIKeyStore
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

    var dailyInsightTargetDate: Date? {
        let today = Date().startOfDay
        let yesterday = today.adding(days: -1)
        if availableStartDate <= yesterday {
            return yesterday
        }
        return availableStartDate <= today ? today : nil
    }

    var activeDailyInsightNarrative: DailyInsightNarrative? {
        guard let targetDate = dailyInsightTargetDate else { return nil }
        if dailyInsightNarrativeDate?.startOfDay == targetDate.startOfDay,
           let dailyInsightNarrative {
            return dailyInsightNarrative
        }
        return record(for: targetDate)?.aiInsightNarrative
    }

    var dailyInsightReport: DailyInsightReport? {
        guard let targetDate = dailyInsightTargetDate else { return nil }
        let record = record(for: targetDate)
            ?? DailyRecord.empty(for: targetDate, preferences: preferences)
        let locale = preferences.appLanguage.locale ?? Locale.autoupdatingCurrent
        return DailyInsightAnalyzer.buildReport(
            for: mergedRecord(record, with: preferences),
            preferences: preferences,
            locale: locale
        )
    }

    var displayedDailyInsightReport: DailyInsightReport? {
        guard let baseReport = dailyInsightReport,
              activeDailyInsightNarrative?.hasAIScoring == true else {
            return dailyInsightReport
        }
        return baseReport.applyingAIOverrides(activeDailyInsightNarrative)
    }

    var isDisplayingAIScoredInsight: Bool {
        activeDailyInsightNarrative?.hasAIScoring == true
    }

    func bootstrap() async {
        guard !isBootstrapped else { return }
        isBootstrapped = true
        user = authService.restoreSession()
        refreshOpenAIConfigurationState()
        do {
            preferences = hydratedPreferences(from: try preferencesStore.loadPreferences(userID: user?.userID))
            persistPreferences()
            applyCurrentLanguage()
            if let user {
                selectedDate = max(selectedDate, user.createdAt.startOfDay)
                analyticsCustomDateRange = defaultAnalyticsCustomRange(startingAt: user.createdAt)
                try loadAllRecords(for: user.userID)
                try loadSelectedRecord()
                await refreshFromCloudIfNeeded(for: user)
                await refreshCloudEncryptionState()
                await ensureAutomaticCloudEncryptionIfNeeded()
                try loadSelectedRecord()
                updateSunTimesIfPossible()
                refreshLocationIfAuthorized()
            }
            await ensureAutomaticYesterdayInsightIfNeeded()
        } catch {
            errorMessage = NSLocalizedString("初始化失败：", comment: "") + error.localizedDescription
        }
    }

    func refreshOpenAIConfigurationState() {
        if openAIKeyStore.hasAPIKey {
            openAIKeyStore.deleteAPIKey()
        }

        if aiInsightNarrativeService is CloudAIInsightService {
            isUsingCloudAIProxy = canUseCloudAIProxy
            canGenerateAIInsights = canUseCloudAIProxy
        } else {
            isUsingCloudAIProxy = false
            canGenerateAIInsights = aiInsightNarrativeService.isConfigured
        }
    }

    func handleAppBecomingActive() async {
        refreshOpenAIConfigurationState()
        await ensureAutomaticYesterdayInsightIfNeeded()
    }

    func refreshDailyInsightNarrative(force: Bool = false) async {
        guard dailyInsightReport != nil,
              let targetDate = dailyInsightTargetDate else { return }
        await generateDailyInsightNarrative(for: targetDate, force: force, isAutomatic: false)
    }

    private func generateDailyInsightNarrative(
        for targetDate: Date,
        force: Bool,
        isAutomatic: Bool
    ) async {
        guard report(for: targetDate) != nil else { return }
        guard canGenerateAIInsights else {
            aiInsightErrorMessage = nil
            return
        }
        if isGeneratingDailyInsightNarrative {
            return
        }
        if !force,
           activeNarrative(for: targetDate)?.hasAIScoring == true {
            dailyInsightNarrative = activeNarrative(for: targetDate)
            dailyInsightNarrativeDate = targetDate.startOfDay
            return
        }

        let record = record(for: targetDate)
            ?? DailyRecord.empty(for: targetDate, preferences: preferences)
        let locale = preferences.appLanguage.locale ?? Locale.autoupdatingCurrent
        let payload = DailyInsightAnalyzer.makePayload(
            record: mergedRecord(record, with: preferences),
            preferences: preferences,
            language: preferences.appLanguage,
            locale: locale,
            history: allRecords.map { mergedRecord($0, with: preferences) }
        )

        isGeneratingDailyInsightNarrative = true
        if !isAutomatic {
            aiInsightErrorMessage = nil
        }
        do {
            let narrative = try await aiInsightNarrativeService.generateNarrative(from: payload)
            try persistDailyInsightNarrative(narrative, for: targetDate)
            dailyInsightNarrative = narrative
            dailyInsightNarrativeDate = targetDate.startOfDay
        } catch {
            if !isAutomatic {
                aiInsightErrorMessage = NSLocalizedString("AI 解读生成失败：", comment: "") + error.localizedDescription
            }
        }
        isGeneratingDailyInsightNarrative = false
    }

    func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        do {
            user = try await authService.handleAppleSignIn(result: result)
            refreshOpenAIConfigurationState()
            preferences = hydratedPreferences(from: try preferencesStore.loadPreferences(userID: user?.userID))
            persistPreferences()
            applyCurrentLanguage()
            selectedDate = max(Date().startOfDay, availableStartDate)
            analyticsCustomDateRange = defaultAnalyticsCustomRange(startingAt: availableStartDate)
            try loadAllRecords(for: user?.userID ?? "")
            try loadSelectedRecord()
            if let user {
                await refreshFromCloudIfNeeded(for: user)
                await refreshCloudEncryptionState()
                await ensureAutomaticCloudEncryptionIfNeeded()
            }
            try loadSelectedRecord()
            await ensureAutomaticYesterdayInsightIfNeeded()
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
            refreshOpenAIConfigurationState()
            preferences = hydratedPreferences(from: try preferencesStore.loadPreferences(userID: user?.userID))
            persistPreferences()
            applyCurrentLanguage()
            selectedDate = max(Date().startOfDay, availableStartDate)
            analyticsCustomDateRange = defaultAnalyticsCustomRange(startingAt: availableStartDate)
            try loadAllRecords(for: user?.userID ?? "")
            try loadSelectedRecord()
            if let user {
                await refreshFromCloudIfNeeded(for: user)
                await refreshCloudEncryptionState()
                await ensureAutomaticCloudEncryptionIfNeeded()
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

    func beginAutomaticCloudMigration() async {
        guard let user, !user.isGuest else { return }

        isCloudMigrationInProgress = true
        cloudMigrationProgress = 0
        cloudMigrationError = nil
        cloudMigrationMessage = NSLocalizedString("正在准备…", comment: "")

        do {
            try await cloudSyncService.enableAutomaticEndToEndEncryption(
                user: user,
                localPreferences: preferences,
                localRecords: allRecords
            ) { [weak self] progress in
                await MainActor.run {
                    self?.cloudMigrationProgress = progress.fractionCompleted
                    self?.cloudMigrationMessage = progress.message
                }
            }
            isCloudMigrationInProgress = false
            cloudMigrationProgress = 1
            cloudMigrationMessage = NSLocalizedString("迁移完成。", comment: "")
            await refreshCloudEncryptionState()
            await refreshFromCloudIfNeeded(for: user)
            try? loadSelectedRecord()
            shouldPresentCloudMigration = false
        } catch {
            isCloudMigrationInProgress = false
            cloudMigrationError = error.localizedDescription
            cloudMigrationMessage = NSLocalizedString("迁移失败，请重试。", comment: "")
            errorMessage = NSLocalizedString("启用加密同步失败：", comment: "") + error.localizedDescription
        }
    }

    func signOut() async {
        do {
            try authService.signOut()
            user = nil
            refreshOpenAIConfigurationState()
            allRecords = []
            selectedDate = .now.startOfDay
            dailyRecord = DailyRecord.empty(for: selectedDate, preferences: preferences)
            cloudEncryptionState = .unavailable
            shouldPresentCloudMigration = false
            isCloudMigrationInProgress = false
            cloudMigrationProgress = 0
            cloudMigrationMessage = nil
            cloudMigrationError = nil
            invalidateDailyInsightNarrative()
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

    func saveMeal(_ entry: MealEntry, images: [UIImage]) async {
        guard canEditSelectedDate else { return }
        var updatedEntry = entry
        do {
            let existingMatch = existingMealMatch(for: updatedEntry)
            let existingEntry = existingMatch?.entry
            if let existingEntry, existingEntry.id != updatedEntry.id {
                updatedEntry.id = existingEntry.id
            }

            let existingPhotoURLs = existingEntry?.photoURLs ?? []
            let retainedPhotoURLs = updatedEntry.photoURLs
            let removedPhotoURLs = Set(existingPhotoURLs).subtracting(retainedPhotoURLs)
            for photoURL in removedPhotoURLs {
                try deletePhotoIfLocal(at: photoURL)
            }
            let savedNewPhotoURLs = try images.map { try photoStorageService.savePhoto($0) }
            updatedEntry.photoURLs = retainedPhotoURLs + savedNewPhotoURLs

            if updatedEntry.status == .logged || updatedEntry.time != nil || updatedEntry.hasPhoto {
                updatedEntry.status = .logged
                updatedEntry.timeZoneIdentifier = updatedEntry.time != nil
                    ? editedTimeZoneIdentifier(for: existingEntry?.timeZoneIdentifier ?? updatedEntry.timeZoneIdentifier)
                    : nil
            }
            if let index = existingMatch?.index {
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
            let existingEntry = existingMealMatch(for: entry)?.entry ?? entry
            try deleteMealPhotosIfLocal(existingEntry.photoURLs)
            removeMealEntry(entry)
            persistCurrentRecord()
            await syncCurrentRecordToCloudIfNeeded()
        } catch {
            errorMessage = NSLocalizedString("删除餐食失败：", comment: "") + error.localizedDescription
        }
    }

    func clearMealRecord(_ entry: MealEntry) async {
        guard canEditSelectedDate else { return }
        do {
            let existingMatch = existingMealMatch(for: entry)
            let existingEntry = existingMatch?.entry ?? entry
            try deleteMealPhotosIfLocal(existingEntry.photoURLs)
            if canDeleteMealEntry(entry) {
                removeMealEntry(entry)
                persistCurrentRecord()
                await syncCurrentRecordToCloudIfNeeded()
                return
            }
            var updatedEntry = existingEntry
            updatedEntry.status = .empty
            updatedEntry.time = nil
            updatedEntry.photoURLs = []
            updatedEntry.timeZoneIdentifier = nil
            if let index = existingMatch?.index {
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

    func removeMealPhoto(_ entry: MealEntry, photoURL: String? = nil) async {
        guard canEditSelectedDate else { return }
        do {
            let existingMatch = existingMealMatch(for: entry)
            let existingEntry = existingMatch?.entry ?? entry
            let photoURLsToDelete = photoURL.map { [$0] } ?? existingEntry.photoURLs
            try deleteMealPhotosIfLocal(photoURLsToDelete)
            var updatedEntry = existingEntry
            if let photoURL {
                updatedEntry.photoURLs.removeAll { $0 == photoURL }
            } else {
                updatedEntry.photoURLs = []
            }
            updatedEntry.status = (existingEntry.status == .logged || updatedEntry.time != nil) ? .logged : .empty
            if let index = existingMatch?.index {
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
            let existingMatch = existingMealMatch(for: entry)
            let existingEntry = existingMatch?.entry ?? entry
            try deleteMealPhotosIfLocal(existingEntry.photoURLs)
            var updatedEntry = existingEntry
            updatedEntry.status = .skipped
            updatedEntry.time = nil
            updatedEntry.photoURLs = []
            updatedEntry.timeZoneIdentifier = nil
            if let index = existingMatch?.index {
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
        updatedShower.timeZoneIdentifier = shower.time != nil ? editedTimeZoneIdentifier(for: shower.timeZoneIdentifier) : nil
        updatedShower.note = trimmedNote(shower.note)
        if let index = dailyRecord.showers.firstIndex(where: { $0.id == shower.id }) {
            dailyRecord.showers[index] = updatedShower
        } else {
            dailyRecord.showers.append(updatedShower)
        }
        dailyRecord.showers.sort { sortOptionalTimes($0.time, $1.time) }
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
        updated.timeZoneIdentifier = entry.time != nil ? editedTimeZoneIdentifier(for: entry.timeZoneIdentifier) : nil
        updated.note = trimmedNote(entry.note)
        if let index = dailyRecord.bowelMovements.firstIndex(where: { $0.id == entry.id }) {
            dailyRecord.bowelMovements[index] = updated
        } else {
            dailyRecord.bowelMovements.append(updated)
        }
        dailyRecord.bowelMovements.sort { sortOptionalTimes($0.time, $1.time) }
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
        do {
            try loadSelectedRecord()
        } catch {
            errorMessage = NSLocalizedString("刷新记录失败：", comment: "") + error.localizedDescription
        }
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
        guard overwritingExistingData || shouldAttemptAutomaticHealthKitSync() else { return }
        do {
            guard let hkSleep = try await healthSyncAdapter.fetchSleepData(
                for: selectedDate,
                after: user.createdAt
            ) else { return }

            dailyRecord.sleepRecord.bedtimePreviousNight = hkSleep.bedtimePreviousNight
            dailyRecord.sleepRecord.wakeTimeCurrentDay = hkSleep.wakeTimeCurrentDay
            dailyRecord.sleepRecord.stageIntervals = hkSleep.stageIntervals
            dailyRecord.sleepRecord.source = .healthKit
            dailyRecord.sleepRecord.timeZoneIdentifier = hkSleep.timeZoneIdentifier ?? TimeZone.autoupdatingCurrent.identifier
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
            dailyRecord.aiInsightNarrative = nil
            dailyRecord.modifiedAt = .now
            try repository.saveRecord(dailyRecord, userID: user.userID)
            try loadAllRecords(for: user.userID)
            invalidateDailyInsightNarrative()
        } catch {
            errorMessage = NSLocalizedString("保存记录失败：", comment: "") + error.localizedDescription
        }
    }

    private func persistPreferences() {
        do {
            preferences.locationPermissionState = locationService.permissionState
            try preferencesStore.savePreferences(preferences, userID: user?.userID)
            invalidateDailyInsightNarrative()
        } catch {
            errorMessage = NSLocalizedString("保存偏好失败：", comment: "") + error.localizedDescription
        }
    }

    private func invalidateDailyInsightNarrative() {
        dailyInsightNarrative = nil
        dailyInsightNarrativeDate = nil
        aiInsightErrorMessage = nil
    }

    private func activeNarrative(for date: Date) -> DailyInsightNarrative? {
        if dailyInsightNarrativeDate?.startOfDay == date.startOfDay,
           let dailyInsightNarrative {
            return dailyInsightNarrative
        }
        return record(for: date)?.aiInsightNarrative
    }

    private func record(for date: Date) -> DailyRecord? {
        if dailyRecord.date.startOfDay == date.startOfDay {
            return dailyRecord
        }
        return allRecords.first(where: { $0.date.startOfDay == date.startOfDay })
    }

    private func report(for date: Date) -> DailyInsightReport? {
        let locale = preferences.appLanguage.locale ?? Locale.autoupdatingCurrent
        let resolvedRecord = record(for: date) ?? DailyRecord.empty(for: date, preferences: preferences)
        return DailyInsightAnalyzer.buildReport(
            for: mergedRecord(resolvedRecord, with: preferences),
            preferences: preferences,
            locale: locale
        )
    }

    private func persistDailyInsightNarrative(_ narrative: DailyInsightNarrative, for date: Date) throws {
        guard let user else { return }

        var storedRecord = try repository.loadRecord(
            for: date,
            preferences: preferences,
            userID: user.userID
        )
        storedRecord = storedRecord.backfillingRecordedTimeZones(TimeZone.autoupdatingCurrent.identifier)
        storedRecord = mergedRecord(storedRecord, with: preferences)
        storedRecord.aiInsightNarrative = narrative
        storedRecord.modifiedAt = .now

        try repository.saveRecord(storedRecord, userID: user.userID)
        try loadAllRecords(for: user.userID)

        if selectedDate.startOfDay == date.startOfDay {
            try loadSelectedRecord()
        }
    }

    private var automaticInsightTargetDate: Date? {
        let yesterday = Date().startOfDay.adding(days: -1)
        guard availableStartDate <= yesterday else { return nil }
        return yesterday
    }

    private func ensureAutomaticYesterdayInsightIfNeeded() async {
        guard let targetDate = automaticInsightTargetDate else { return }
        guard activeNarrative(for: targetDate)?.hasAIScoring != true else { return }
        await generateDailyInsightNarrative(for: targetDate, force: false, isAutomatic: true)
    }

    private var canUseCloudAIProxy: Bool {
        guard let user, !user.isGuest else { return false }
        guard AIProxyConfiguration().isConfigured else { return false }
        FirebaseBootstrap.configureIfPossible()
        guard FirebaseBootstrap.isConfigured else { return false }
        return Auth.auth().currentUser != nil
    }

    private func mergeMealsWithPreferences() {
        dailyRecord = mergedRecord(dailyRecord, with: preferences)
    }

    private func mergedRecord(_ record: DailyRecord, with preferences: UserPreferences) -> DailyRecord {
        var updated = record
        updated.sleepRecord.targetBedtime = preferences.bedtimeSchedule.target(for: updated.date)
        updated.meals = deduplicatedMeals(updated.meals)
        for slot in preferences.defaultMealSlots {
            let exists = updated.meals.contains { mealEntry($0, matches: slot) }
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

            let registrationCutoffKey = user.createdAt.storageKey()
            let store = LocalJSONStore()
            var database = try store.load()
            let prunedLocalRecordMap = Self.recordsByStorageKey(
                (database.recordsByUser[user.userID] ?? [:]).compactMap { entry in
                    guard entry.key >= registrationCutoffKey else { return nil }
                    return entry.value.anchoredToStorageKey(entry.key)
                }
            )

            if payload.records.isEmpty {
                if database.recordsByUser[user.userID] != prunedLocalRecordMap {
                    database.recordsByUser[user.userID] = prunedLocalRecordMap
                    try store.save(database)
                }
                allRecords = prunedLocalRecordMap.values.sorted { $0.date < $1.date }
                await refreshRemotePhotoCache()
            }

            if !payload.records.isEmpty {
                let localRecordMap = prunedLocalRecordMap
                let remoteRecordMap = Self.recordsByStorageKey(payload.records)
                var merged = remoteRecordMap
                var recordsToPush: [DailyRecord] = []
                for (key, localRecord) in localRecordMap {
                    guard let remoteRecord = merged[key] else {
                        merged[key] = localRecord
                        recordsToPush.append(localRecord)
                        continue
                    }
                    var mergedRecord = Self.preferredRecord(between: localRecord, and: remoteRecord)
                    if mergedRecord == localRecord {
                        if localRecord != remoteRecord {
                            recordsToPush.append(localRecord)
                        }
                        // Keep remote photo references when the preferred local
                        // copy doesn't currently have an accessible image.
                        for i in mergedRecord.meals.indices {
                            let localPhotos = mergedRecord.meals[i].photoURLs
                            let missingLocalPhotos = localPhotos.filter {
                                !Self.isRemotePhotoURL($0) && !FileManager.default.fileExists(atPath: $0)
                            }
                            guard !missingLocalPhotos.isEmpty || localPhotos.isEmpty else {
                                continue
                            }

                            if let remoteMeal = remoteRecord.meals.first(where: { $0.id == mergedRecord.meals[i].id }),
                               !remoteMeal.photoURLs.isEmpty {
                                mergedRecord.meals[i].photoURLs = remoteMeal.photoURLs
                            }
                        }
                    }
                    merged[key] = mergedRecord.backfillingRecordedTimeZones(TimeZone.autoupdatingCurrent.identifier)
                }
                database.recordsByUser[user.userID] = merged
                    .filter { $0.key >= registrationCutoffKey }
                    .mapValues {
                    $0.backfillingRecordedTimeZones(TimeZone.autoupdatingCurrent.identifier)
                }
                try store.save(database)
                allRecords = database.recordsByUser[user.userID]?
                    .values
                    .filter { $0.date >= user.createdAt.startOfDay }
                    .sorted { $0.date < $1.date } ?? []
                await refreshRemotePhotoCache()

                for record in deduplicatedPendingUploads(recordsToPush) {
                    try await cloudSyncService.pushRecord(record, user: user)
                }
            }
        } catch {
            if isConnectivityError(error) {
                return
            }
            if let securityError = error as? CloudSyncSecurityError,
               securityError == .encryptedSyncLocked {
                cloudEncryptionState = .locked
                errorMessage = securityError.localizedDescription
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
            if isConnectivityError(error) {
                return
            }
            if let securityError = error as? CloudSyncSecurityError,
               securityError == .encryptedSyncLocked {
                cloudEncryptionState = .locked
                errorMessage = securityError.localizedDescription
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
            if isConnectivityError(error) {
                return
            }
            if let securityError = error as? CloudSyncSecurityError,
               securityError == .encryptedSyncLocked {
                cloudEncryptionState = .locked
                errorMessage = securityError.localizedDescription
            } else {
                errorMessage = NSLocalizedString("云端记录同步失败：", comment: "") + error.localizedDescription
            }
        }
    }

    func refreshCloudEncryptionState() async {
        guard let user, !user.isGuest else {
            cloudEncryptionState = cloudSyncService.isAvailable ? .disabled : .unavailable
            shouldPresentCloudMigration = false
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
            shouldPresentCloudMigration = snapshot.requiresMigration && !isCloudMigrationInProgress
        } catch {
            cloudEncryptionState = .unavailable
            shouldPresentCloudMigration = false
        }
    }

    private func ensureAutomaticCloudEncryptionIfNeeded() async {
        guard let user, !user.isGuest, cloudSyncService.isAvailable else { return }
        guard !isCloudMigrationInProgress else { return }

        do {
            let snapshot = try await cloudSyncService.protectionSnapshot(for: user)
            guard snapshot.mode == .disabled, !snapshot.hasLegacyPlaintextData else { return }

            try await cloudSyncService.enableAutomaticEndToEndEncryption(
                user: user,
                localPreferences: preferences,
                localRecords: allRecords
            ) { _ in }
            await refreshCloudEncryptionState()
        } catch {
            errorMessage = NSLocalizedString("启用加密同步失败：", comment: "") + error.localizedDescription
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
                    .flatMap(\.photoURLs)
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
            let key = normalized.canonicalStorageKey(fallback: normalized.date.storageKey())

            if let existing = partialResult[key] {
                partialResult[key] = preferredRecord(between: existing, and: normalized)
            } else {
                partialResult[key] = normalized
            }
        }
    }

    private nonisolated static func normalizedRecord(_ record: DailyRecord) -> DailyRecord {
        let key = record.canonicalStorageKey(fallback: record.date.storageKey())
        return record.anchoredToStorageKey(key)
    }

    private nonisolated static func preferredRecord(between lhs: DailyRecord, and rhs: DailyRecord) -> DailyRecord {
        if lhs.effectiveModifiedAt != rhs.effectiveModifiedAt {
            return lhs.effectiveModifiedAt > rhs.effectiveModifiedAt ? lhs : rhs
        }

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
            if meal.hasPhoto {
                score += 1
            }
        }

        if record.aiInsightNarrative?.hasAIScoring == true {
            score += 2
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
        guard entry.mealKind == slot.kind else { return false }
        guard slot.kind == .custom else { return true }
        return normalizedCustomMealTitle(entry.customTitle) == normalizedCustomMealTitle(slot.title)
    }

    private func existingMealMatch(for entry: MealEntry) -> (index: Int, entry: MealEntry)? {
        if let index = dailyRecord.meals.firstIndex(where: { $0.id == entry.id }) {
            return (index, dailyRecord.meals[index])
        }
        guard let slotKey = logicalMealSlotKey(for: entry) else { return nil }
        guard let index = dailyRecord.meals.firstIndex(where: { logicalMealSlotKey(for: $0) == slotKey }) else {
            return nil
        }
        return (index, dailyRecord.meals[index])
    }

    private func removeMealEntry(_ entry: MealEntry) {
        if let index = existingMealMatch(for: entry)?.index {
            dailyRecord.meals.remove(at: index)
            return
        }
        dailyRecord.meals.removeAll { $0.id == entry.id }
    }

    private func deduplicatedMeals(_ meals: [MealEntry]) -> [MealEntry] {
        var bySlot: [String: MealEntry] = [:]
        var extras: [MealEntry] = []

        for meal in meals {
            guard let slotKey = logicalMealSlotKey(for: meal) else {
                extras.append(meal)
                continue
            }

            if let existing = bySlot[slotKey] {
                bySlot[slotKey] = preferredMealEntry(between: existing, and: meal)
            } else {
                bySlot[slotKey] = meal
            }
        }

        return Array(bySlot.values) + extras
    }

    private func preferredMealEntry(between lhs: MealEntry, and rhs: MealEntry) -> MealEntry {
        let lhsScore = mealCompletenessScore(lhs)
        let rhsScore = mealCompletenessScore(rhs)
        if lhsScore != rhsScore {
            return lhsScore > rhsScore ? lhs : rhs
        }

        if lhs.id == rhs.id {
            return lhs
        }

        return lhs.id.uuidString < rhs.id.uuidString ? lhs : rhs
    }

    private func mealCompletenessScore(_ meal: MealEntry) -> Int {
        var score = 0
        switch meal.status {
        case .logged:
            score += 3
        case .skipped:
            score += 2
        case .empty:
            break
        }
        if meal.time != nil { score += 2 }
        if meal.hasPhoto { score += 1 }
        if trimmedNote(meal.note) != nil { score += 1 }
        if meal.locationName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false { score += 1 }
        if meal.latitude != nil || meal.longitude != nil { score += 1 }
        return score
    }

    private func logicalMealSlotKey(for entry: MealEntry) -> String? {
        switch entry.mealKind {
        case .breakfast, .lunch, .dinner:
            return entry.mealKind.rawValue
        case .custom:
            guard let title = normalizedCustomMealTitle(entry.customTitle) else { return nil }
            return "custom:\(title)"
        }
    }

    private func normalizedCustomMealTitle(_ title: String?) -> String? {
        let normalized = title?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        guard let normalized, !normalized.isEmpty else { return nil }
        return normalized
    }

    private func deletePhotoIfLocal(at path: String) throws {
        guard !Self.isRemotePhotoURL(path) else { return }
        try photoStorageService.deletePhoto(at: path)
    }

    private func deleteMealPhotosIfLocal(_ photoURLs: [String]) throws {
        for photoURL in photoURLs {
            try deletePhotoIfLocal(at: photoURL)
        }
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

    private func shouldAttemptAutomaticHealthKitSync() -> Bool {
        guard selectedDate.startOfDay == Date().startOfDay else { return false }
        return !dailyRecord.sleepRecord.hasSleepData
    }

    private func sortOptionalTimes(_ lhs: Date?, _ rhs: Date?) -> Bool {
        switch (lhs, rhs) {
        case let (.some(lhs), .some(rhs)):
            return lhs < rhs
        case (.none, .some):
            return false
        case (.some, .none):
            return true
        case (.none, .none):
            return false
        }
    }

    private func deduplicatedPendingUploads(_ records: [DailyRecord]) -> [DailyRecord] {
        let deduplicated = Self.recordsByStorageKey(records)
        return deduplicated.values.sorted { $0.date < $1.date }
    }

    private func isConnectivityError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            let connectivityCodes: Set<Int> = [
                URLError.notConnectedToInternet.rawValue,
                URLError.networkConnectionLost.rawValue,
                URLError.cannotConnectToHost.rawValue,
                URLError.cannotFindHost.rawValue,
                URLError.timedOut.rawValue,
                URLError.internationalRoamingOff.rawValue,
                URLError.callIsActive.rawValue,
                URLError.dataNotAllowed.rawValue
            ]
            return connectivityCodes.contains(nsError.code)
        }

        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
           isConnectivityError(underlying) {
            return true
        }

        let message = nsError.localizedDescription.lowercased()
        return message.contains("offline") || message.contains("network") || message.contains("internet")
    }
}

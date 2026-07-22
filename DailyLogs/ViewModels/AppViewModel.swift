import AuthenticationServices
import Combine
import CoreLocation
import FirebaseAuth
import Foundation
import SwiftUI
import UIKit

struct CloudRecordReconciliationResult: Equatable {
    var record: DailyRecord
    var shouldPushRecord: Bool
    var discardedRemotePhotoReferences: Set<String>
}

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
    @Published private(set) var travelPlans: [TravelPlan] = []
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
    @Published private(set) var currentWeather: WeatherSnapshot?
    @Published private(set) var currentLocationName: String?

    let locationService: LocationService

    private let authService: AuthService
    private let repository: DailyRecordRepository
    private let travelPlanRepository: TravelPlanRepository
    private let preferencesStore: PreferencesStore
    private let photoStorageService: PhotoStorageService
    private let videoStorageService: VideoStorageService
    private let sunTimesService: SunTimesService
    private let weatherService: WeatherService
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
            travelPlanRepository: LocalTravelPlanRepository(store: store),
            preferencesStore: LocalPreferencesStore(store: store),
            photoStorageService: LocalPhotoStorageService(),
            videoStorageService: LocalVideoStorageService(),
            sunTimesService: AstronomySunTimesService(),
            weatherService: OpenMeteoWeatherService(),
            healthSyncAdapter: HealthKitService(),
            cloudSyncService: FirebaseCloudSyncService(),
            aiInsightNarrativeService: cloudAIService,
            openAIKeyStore: openAIKeyStore,
            locationService: LocationService(),
            selectedDate: preferences.currentLogicalDate(),
            dailyRecord: DailyRecord.empty(for: .now, preferences: preferences),
            preferences: preferences
        )
    }

    init(
        authService: AuthService,
        repository: DailyRecordRepository,
        travelPlanRepository: TravelPlanRepository = NoopTravelPlanRepository(),
        preferencesStore: PreferencesStore,
        photoStorageService: PhotoStorageService,
        videoStorageService: VideoStorageService,
        sunTimesService: SunTimesService,
        weatherService: WeatherService,
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
        self.travelPlanRepository = travelPlanRepository
        self.preferencesStore = preferencesStore
        self.photoStorageService = photoStorageService
        self.videoStorageService = videoStorageService
        self.sunTimesService = sunTimesService
        self.weatherService = weatherService
        self.healthSyncAdapter = healthSyncAdapter
        self.cloudSyncService = cloudSyncService
        self.aiInsightNarrativeService = aiInsightNarrativeService
        self.openAIKeyStore = openAIKeyStore
        self.locationService = locationService
        self.selectedDate = selectedDate.startOfDay == Date().startOfDay
            ? preferences.currentLogicalDate()
            : selectedDate.startOfDay
        self.dailyRecord = dailyRecord
        self.preferences = preferences
        bindLocationService()
    }

    var isAuthenticated: Bool {
        user != nil
    }

    var logicalToday: Date {
        preferences.currentLogicalDate()
    }

    var canEditSelectedDate: Bool {
        selectableDateRange.contains(selectedDate.startOfDay)
    }

    var availableStartDate: Date {
        [
            user?.createdAt.startOfDay,
            allRecords.map(\.date.startOfDay).min()
        ]
        .compactMap { $0 }
        .min() ?? logicalToday
    }

    var availableDateRange: ClosedRange<Date> {
        availableStartDate...logicalToday
    }

    var selectableDateRange: ClosedRange<Date> {
        let startedPlans = travelPlans.filter { $0.status != .planned }
        let travelStart = startedPlans.compactMap { $0.earliestCalendarDate(using: preferences) }.min()
        let travelEnd = startedPlans.compactMap { $0.latestCalendarDate(using: preferences) }.max()
        return min(availableStartDate, travelStart ?? availableStartDate)...max(logicalToday, travelEnd ?? logicalToday)
    }

    var travelOverlayDateRange: ClosedRange<Date> {
        let travelStart = travelPlans.compactMap { $0.earliestCalendarDate(using: preferences) }.min() ?? availableStartDate
        let travelEnd = travelPlans.compactMap { $0.latestCalendarDate(using: preferences) }.max() ?? logicalToday
        return min(availableStartDate, travelStart)...max(logicalToday, travelEnd)
    }

    var aiInsightCalendarDateRange: ClosedRange<Date>? {
        let upperBound = logicalToday.adding(days: -1)
        guard availableStartDate <= upperBound else { return nil }
        return availableStartDate...upperBound
    }

    var analyticsSummary: AnalyticsSummary {
        AnalyticsCalculator.build(
            records: allRecords,
            range: analyticsRange,
            customRange: analyticsRange == .custom ? analyticsCustomDateRange : nil,
            defaultMealSlots: preferences.defaultMealSlots,
            today: logicalToday
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
        let today = logicalToday
        let yesterday = today.adding(days: -1)
        if availableStartDate <= yesterday {
            return yesterday
        }
        return availableStartDate <= today ? today : nil
    }

    var activeDailyInsightNarrative: DailyInsightNarrative? {
        guard let targetDate = dailyInsightTargetDate else { return nil }
        return localizedNarrative(validatedNarrative(for: targetDate))
    }

    var dailyInsightReport: DailyInsightReport? {
        guard let targetDate = dailyInsightTargetDate else { return nil }
        return insightReport(for: targetDate)
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

    var scoredAIInsightDates: [Date] {
        allRecords
            .filter { validatedNarrative(for: $0.date) != nil }
            .map(\.date.startOfDay)
            .sorted(by: >)
    }

    func activeDailyInsightNarrative(for date: Date) -> DailyInsightNarrative? {
        localizedNarrative(validatedNarrative(for: date))
    }

    func insightReport(for date: Date) -> DailyInsightReport? {
        let locale = preferences.appLanguage.locale ?? Locale.autoupdatingCurrent
        let resolvedRecord = record(for: date) ?? DailyRecord.empty(for: date, preferences: preferences)
        return DailyInsightAnalyzer.buildReport(
            for: mergedRecord(resolvedRecord, with: preferences),
            preferences: preferences,
            locale: locale
        )
    }

    func displayedDailyInsightReport(for date: Date) -> DailyInsightReport? {
        guard let baseReport = insightReport(for: date),
              let narrative = localizedNarrative(validatedNarrative(for: date)),
              narrative.hasAIScoring else {
            return insightReport(for: date)
        }
        return baseReport.applyingAIOverrides(narrative)
    }

    func isDisplayingAIScoredInsight(for date: Date) -> Bool {
        validatedNarrative(for: date)?.hasAIScoring == true
    }

    func bootstrap() async {
        guard !isBootstrapped else { return }
        isBootstrapped = true
        user = authService.restoreSession()
        refreshOpenAIConfigurationState()
        do {
            let loadedPreferences = try preferencesStore.loadPreferences(userID: user?.userID)
            let shouldMigrateMidnightModeKeys = loadedPreferences.midnightMode.isEnabled
                && loadedPreferences.midnightMode.cutoffHour != MidnightModeSettings.fixedCutoffHour
            preferences = hydratedPreferences(from: loadedPreferences)
            persistPreferences()
            applyCurrentLanguage()
            if let user {
                selectedDate = min(max(selectedDate, user.createdAt.startOfDay), logicalToday)
                analyticsCustomDateRange = defaultAnalyticsCustomRange(startingAt: user.createdAt)
                try loadAllRecords(for: user.userID)
                try loadTravelPlans(for: user.userID)
                if shouldMigrateMidnightModeKeys {
                    try rekeyAllRecords(for: user.userID)
                }
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
        await normalizeSelectedDateForCurrentDayBoundaryIfNeeded()
        await ensureAutomaticYesterdayInsightIfNeeded()
    }

    func refreshDailyInsightNarrative(force: Bool = false) async {
        guard dailyInsightReport != nil,
              let targetDate = dailyInsightTargetDate else { return }
        await refreshDailyInsightNarrative(for: targetDate, force: force)
    }

    func refreshDailyInsightNarrative(for date: Date, force: Bool = false) async {
        await generateDailyInsightNarrative(for: date.startOfDay, force: force, isAutomatic: false)
    }

    private func generateDailyInsightNarrative(
        for targetDate: Date,
        force: Bool,
        isAutomatic: Bool
    ) async {
        guard insightReport(for: targetDate) != nil else { return }
        guard canGenerateAIInsights else {
            aiInsightErrorMessage = nil
            return
        }
        if isGeneratingDailyInsightNarrative {
            return
        }
        if !force, let cachedNarrative = validatedNarrative(for: targetDate) {
            let resolvedNarrative = await backfillEnglishTranslationIfNeeded(for: cachedNarrative, date: targetDate)
            dailyInsightNarrative = resolvedNarrative
            dailyInsightNarrativeDate = targetDate.startOfDay
            return
        }

        guard let payload = canonicalInsightPayload(for: targetDate) else { return }

        isGeneratingDailyInsightNarrative = true
        if !isAutomatic {
            aiInsightErrorMessage = nil
        }
        do {
            var narrative = try await aiInsightNarrativeService.generateNarrative(from: payload)
            narrative.sourceLanguageCode = AppLanguage.zhHans.aiNarrativeLanguageCode()
            narrative.payloadSignature = try payload.stableSignature()
            narrative.scoringVersion = DailyInsightNarrative.currentScoringVersion
            narrative = await backfillEnglishTranslationIfNeeded(for: narrative, date: targetDate)
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
            selectedDate = max(logicalToday, availableStartDate)
            analyticsCustomDateRange = defaultAnalyticsCustomRange(startingAt: availableStartDate)
            try loadAllRecords(for: user?.userID ?? "")
            try loadTravelPlans(for: user?.userID ?? "")
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
            selectedDate = max(logicalToday, availableStartDate)
            analyticsCustomDateRange = defaultAnalyticsCustomRange(startingAt: availableStartDate)
            try loadAllRecords(for: user?.userID ?? "")
            try loadTravelPlans(for: user?.userID ?? "")
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
            travelPlans = []
            selectedDate = logicalToday
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
        let range = selectableDateRange
        let clamped = min(max(date.startOfDay, range.lowerBound), range.upperBound)
        selectedDate = clamped
        do {
            try loadSelectedRecord()
        } catch {
            errorMessage = NSLocalizedString("加载记录失败：", comment: "") + error.localizedDescription
        }
    }

    func travelPlans(on date: Date) -> [TravelPlan] {
        let key = date.startOfDay.storageKey()
        return travelPlans.filter { $0.affectedStorageKeys(using: preferences).contains(key) }
    }

    func activeTravelPlan(on date: Date) -> TravelPlan? {
        travelPlans(on: date).first {
            switch $0.status {
            case .planned, .completed:
                false
            case .preDeparture, .inFlight, .layover, .arrived:
                true
            }
        }
    }

    func saveTravelPlan(_ plan: TravelPlan) async {
        guard let user else { return }
        var updated = plan
        updated.modifiedAt = .now
        do {
            try travelPlanRepository.saveTravelPlan(updated, userID: user.userID)
            try loadTravelPlans(for: user.userID)
        } catch {
            errorMessage = NSLocalizedString("保存旅行计划失败：", comment: "") + error.localizedDescription
        }
    }

    func deleteTravelPlan(_ plan: TravelPlan) async {
        guard let user else { return }
        do {
            try travelPlanRepository.deleteTravelPlan(plan, userID: user.userID)
            try loadTravelPlans(for: user.userID)
        } catch {
            errorMessage = NSLocalizedString("删除旅行计划失败：", comment: "") + error.localizedDescription
        }
    }

    func saveTravelSleepSession(_ session: TravelSleepSession, in plan: TravelPlan) async {
        guard let user, var updated = travelPlans.first(where: { $0.id == plan.id }) else { return }
        var normalized = session
        if normalized.endTime < normalized.startTime {
            normalized.endTime = normalized.startTime
        }
        if let index = updated.sleepSessions.firstIndex(where: { $0.id == normalized.id }) {
            updated.sleepSessions[index] = normalized
        } else {
            updated.sleepSessions.append(normalized)
        }
        updated.sleepSessions.sort { $0.startTime < $1.startTime }
        updated.modifiedAt = .now
        do {
            try travelPlanRepository.saveTravelPlan(updated, userID: user.userID)
            try loadTravelPlans(for: user.userID)
        } catch {
            errorMessage = NSLocalizedString("保存旅行睡眠失败：", comment: "") + error.localizedDescription
        }
    }

    func deleteTravelSleepSession(_ session: TravelSleepSession, in plan: TravelPlan) async {
        guard let user, var updated = travelPlans.first(where: { $0.id == plan.id }) else { return }
        updated.sleepSessions.removeAll { $0.id == session.id }
        updated.modifiedAt = .now
        do {
            try travelPlanRepository.saveTravelPlan(updated, userID: user.userID)
            try loadTravelPlans(for: user.userID)
        } catch {
            errorMessage = NSLocalizedString("删除旅行睡眠失败：", comment: "") + error.localizedDescription
        }
    }

    func addSampleTravelPlan() async {
        await saveTravelPlan(TravelPlan.sampleBOSPKX())
    }

#if DEBUG
    func startDebugHypotheticalTravel() async {
        guard let user else { return }
        do {
            for plan in travelPlans where plan.title.hasPrefix(Self.debugTravelPlanTitlePrefix) {
                try travelPlanRepository.deleteTravelPlan(plan, userID: user.userID)
            }
            try travelPlanRepository.saveTravelPlan(Self.makeDebugHypotheticalTravelPlan(now: .now), userID: user.userID)
            try loadTravelPlans(for: user.userID)
            selectedDate = logicalToday
            try loadSelectedRecord()
        } catch {
            errorMessage = NSLocalizedString("启动假想旅行失败：", comment: "") + error.localizedDescription
        }
    }

    func clearDebugHypotheticalTravel() async {
        guard let user else { return }
        do {
            for plan in travelPlans where plan.title.hasPrefix(Self.debugTravelPlanTitlePrefix) {
                try travelPlanRepository.deleteTravelPlan(plan, userID: user.userID)
            }
            try loadTravelPlans(for: user.userID)
        } catch {
            errorMessage = NSLocalizedString("清除假想旅行失败：", comment: "") + error.localizedDescription
        }
    }

    private static let debugTravelPlanTitlePrefix = "[DEBUG]"

    private static func makeDebugHypotheticalTravelPlan(now: Date) -> TravelPlan {
        let bosTimeZone = "America/New_York"
        let lhrTimeZone = "Europe/London"
        let pkxTimeZone = "Asia/Shanghai"
        let firstDeparture = now.addingTimeInterval(10 * 60)
        let firstArrival = now.addingTimeInterval(45 * 60)
        let secondDeparture = now.addingTimeInterval(65 * 60)
        let secondArrival = now.addingTimeInterval(120 * 60)
        return TravelPlan(
            title: debugTravelPlanTitlePrefix + " " + NSLocalizedString("假想旅行", comment: ""),
            segments: [
                TravelSegment(
                    flightNumber: "DBG001",
                    originCode: "BOS",
                    destinationCode: "LHR",
                    plannedDepartureTime: firstDeparture,
                    plannedArrivalTime: firstArrival,
                    departureTimeZoneIdentifier: bosTimeZone,
                    arrivalTimeZoneIdentifier: lhrTimeZone
                ),
                TravelSegment(
                    flightNumber: "DBG002",
                    originCode: "LHR",
                    destinationCode: "PKX",
                    plannedDepartureTime: secondDeparture,
                    plannedArrivalTime: secondArrival,
                    departureTimeZoneIdentifier: lhrTimeZone,
                    arrivalTimeZoneIdentifier: pkxTimeZone
                )
            ],
            status: .planned,
            createdAt: now
        )
    }
#endif

    func advanceTravelPlan(_ plan: TravelPlan) async {
        guard let user, var updated = travelPlans.first(where: { $0.id == plan.id }) else { return }
        updated.advance()
        do {
            try travelPlanRepository.saveTravelPlan(updated, userID: user.userID)
            try loadTravelPlans(for: user.userID)
        } catch {
            errorMessage = NSLocalizedString("更新旅行状态失败：", comment: "") + error.localizedDescription
        }
    }

    func retreatTravelPlan(_ plan: TravelPlan) async {
        guard let user, var updated = travelPlans.first(where: { $0.id == plan.id }) else { return }
        updated.retreat()
        do {
            try travelPlanRepository.saveTravelPlan(updated, userID: user.userID)
            try loadTravelPlans(for: user.userID)
        } catch {
            errorMessage = NSLocalizedString("更新旅行状态失败：", comment: "") + error.localizedDescription
        }
    }

    func travelContextForCurrentRecording() -> TravelRecordContext? {
        guard let plan = activeTravelPlan(on: selectedDate) else { return nil }
        return TravelRecordContext(
            planID: plan.id,
            segmentID: plan.currentSegment?.id,
            phase: plan.status
        )
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
        persistPreferences(invalidateInsights: false)
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
        if preferences.homeSectionSchemaVersion < UserPreferences.currentHomeSectionSchemaVersion {
            if !preferences.visibleHomeSections.contains(.dailyVideo) {
                preferences.visibleHomeSections.append(.dailyVideo)
            }
            preferences.homeSectionSchemaVersion = UserPreferences.currentHomeSectionSchemaVersion
        }
        preferences.midnightMode.cutoffHour = MidnightModeSettings.fixedCutoffHour
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

    func updateTemperatureUnit(_ unit: TemperatureUnitPreference) async {
        guard preferences.temperatureUnit != unit else { return }
        preferences.temperatureUnit = unit
        persistPreferences()
        await syncPreferencesToCloudIfNeeded()
    }

    func configureMidnightMode(enabled: Bool, applyToExistingRecords: Bool) async {
        if enabled {
            preferences.midnightMode = MidnightModeSettings(
                isEnabled: true,
                cutoffHour: MidnightModeSettings.fixedCutoffHour,
                effectiveFrom: applyToExistingRecords ? nil : .now
            )
        } else {
            preferences.midnightMode = MidnightModeSettings(
                isEnabled: false,
                cutoffHour: MidnightModeSettings.fixedCutoffHour,
                effectiveFrom: nil
            )
        }

        persistPreferences()

        do {
            if let user, applyToExistingRecords {
                try rekeyAllRecords(for: user.userID)
            } else if let user {
                try loadAllRecords(for: user.userID)
            }

            selectedDate = min(max(selectedDate, availableStartDate), logicalToday)
            try loadSelectedRecord()
        } catch {
            errorMessage = NSLocalizedString("更新午夜模式失败：", comment: "") + error.localizedDescription
        }

        await syncPreferencesToCloudIfNeeded()
        await syncCurrentRecordToCloudIfNeeded()
    }

    func saveMeal(_ entry: MealEntry, images: [UIImage]) async {
        guard canEditSelectedDate else { return }
        var updatedEntry = entry
        do {
            let existingLocation = preferredMealEntryLocation(for: updatedEntry)
            let existingMatch = existingMealMatch(for: updatedEntry)
            let existingEntry = existingLocation?.entry ?? existingMatch?.entry
            if let existingEntry, existingEntry.id != updatedEntry.id {
                updatedEntry.id = existingEntry.id
            }
            updatedEntry.travelContext = updatedEntry.travelContext
                ?? existingEntry?.travelContext
                ?? travelContextForCurrentRecording()

            let existingPhotoURLs = existingEntry?.photoURLs ?? []
            let retainedPhotoURLs = updatedEntry.photoURLs
            let removedPhotoURLs = Set(existingPhotoURLs).subtracting(retainedPhotoURLs)
            try await deleteMealPhotos(Array(removedPhotoURLs))
            let savedNewPhotoURLs = try images.map { try photoStorageService.savePhoto($0) }
            updatedEntry.photoURLs = retainedPhotoURLs + savedNewPhotoURLs

            if updatedEntry.status == .logged || updatedEntry.time != nil || updatedEntry.hasPhoto {
                updatedEntry.status = .logged
                updatedEntry.travelContext = updatedEntry.travelContext ?? existingEntry?.travelContext ?? travelContextForCurrentRecording()
                updatedEntry.timeZoneIdentifier = updatedEntry.time != nil
                    ? editedTimeZoneIdentifier(
                        for: existingEntry?.timeZoneIdentifier ?? updatedEntry.timeZoneIdentifier,
                        travelContext: updatedEntry.travelContext
                    )
                    : nil
            }
            if let existingLocation {
                var record = existingLocation.record
                record.meals[existingLocation.index] = updatedEntry
                let savedRecord = try persistRecord(record)
                await syncRecordToCloudIfNeeded(savedRecord)
            } else if let index = existingMatch?.index {
                dailyRecord.meals[index] = updatedEntry
                persistCurrentRecord()
                await syncCurrentRecordToCloudIfNeeded()
            } else {
                dailyRecord.meals.append(updatedEntry)
                persistCurrentRecord()
                await syncCurrentRecordToCloudIfNeeded()
            }
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
            let locations = mealEntryLocations(id: entry.id)
            if locations.isEmpty {
                let existingEntry = existingMealMatch(for: entry)?.entry ?? entry
                try await deleteMealPhotos(existingEntry.photoURLs)
                removeMealEntry(entry)
                persistCurrentRecord()
                await syncCurrentRecordToCloudIfNeeded()
                return
            }
            try await deleteMealPhotos(Array(Set(locations.flatMap { $0.entry.photoURLs })))
            for location in locations {
                var record = location.record
                record.meals.removeAll { $0.id == entry.id }
                let savedRecord = try persistRecord(record)
                await syncRecordToCloudIfNeeded(savedRecord)
            }
        } catch {
            errorMessage = NSLocalizedString("删除餐食失败：", comment: "") + error.localizedDescription
        }
    }

    func clearMealRecord(_ entry: MealEntry) async {
        guard canEditSelectedDate else { return }
        do {
            let existingMatch = existingMealMatch(for: entry)
            let existingEntry = existingMatch?.entry ?? entry
            try await deleteMealPhotos(existingEntry.photoURLs)
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
            updatedEntry.locationName = nil
            updatedEntry.latitude = nil
            updatedEntry.longitude = nil
            updatedEntry.isLocationManuallyEdited = false
            updatedEntry.travelContext = nil
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
            try await deleteMealPhotos(photoURLsToDelete)
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
            try await deleteMealPhotos(existingEntry.photoURLs)
            var updatedEntry = existingEntry
            updatedEntry.status = .skipped
            updatedEntry.time = nil
            updatedEntry.photoURLs = []
            updatedEntry.timeZoneIdentifier = nil
            updatedEntry.locationName = nil
            updatedEntry.latitude = nil
            updatedEntry.longitude = nil
            updatedEntry.isLocationManuallyEdited = false
            updatedEntry.travelContext = travelContextForCurrentRecording()
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

    func saveDailyVideo(from sourceURL: URL, duration: TimeInterval) async {
        guard canEditSelectedDate else { return }
        do {
            let existingVideoURL = dailyRecord.dailyVideo?.videoURL
            let savedVideoURL = try videoStorageService.saveVideo(from: sourceURL)
            if let existingVideoURL {
                try deleteVideoIfLocal(at: existingVideoURL)
            }
            dailyRecord.dailyVideo = DailyVideoEntry(
                videoURL: savedVideoURL,
                duration: min(max(duration, 0), 10),
                createdAt: .now
            )
            persistCurrentRecord()
            await syncCurrentRecordToCloudIfNeeded()
        } catch {
            errorMessage = NSLocalizedString("保存视频失败：", comment: "") + error.localizedDescription
        }
    }

    func deleteDailyVideo() async {
        guard canEditSelectedDate, let dailyVideo = dailyRecord.dailyVideo else { return }
        do {
            try deleteVideoIfLocal(at: dailyVideo.videoURL)
            dailyRecord.dailyVideo = nil
            persistCurrentRecord()
            await syncCurrentRecordToCloudIfNeeded()
        } catch {
            errorMessage = NSLocalizedString("删除视频失败：", comment: "") + error.localizedDescription
        }
    }

    func saveShower(_ shower: ShowerEntry) async {
        guard canEditSelectedDate else { return }
        var updatedShower = shower
        let existingLocation = preferredShowerEntryLocation(for: shower)
        let existingEntry = existingLocation?.entry
        updatedShower.note = trimmedNote(shower.note)
        updatedShower.travelContext = shower.travelContext
            ?? existingEntry?.travelContext
            ?? travelContextForCurrentRecording()
        updatedShower.timeZoneIdentifier = shower.time != nil
            ? editedTimeZoneIdentifier(for: shower.timeZoneIdentifier, travelContext: updatedShower.travelContext)
            : nil
        do {
            if let existingLocation {
                var record = existingLocation.record
                record.showers[existingLocation.index] = updatedShower
                record.showers.sort { sortOptionalTimes($0.time, $1.time) }
                let savedRecord = try persistRecord(record)
                await syncRecordToCloudIfNeeded(savedRecord)
            } else if let index = dailyRecord.showers.firstIndex(where: { $0.id == shower.id }) {
                dailyRecord.showers[index] = updatedShower
                dailyRecord.showers.sort { sortOptionalTimes($0.time, $1.time) }
                persistCurrentRecord()
                await syncCurrentRecordToCloudIfNeeded()
            } else {
                dailyRecord.showers.append(updatedShower)
                dailyRecord.showers.sort { sortOptionalTimes($0.time, $1.time) }
                persistCurrentRecord()
                await syncCurrentRecordToCloudIfNeeded()
            }
        } catch {
            errorMessage = NSLocalizedString("保存洗澡失败：", comment: "") + error.localizedDescription
        }
    }

    func deleteShower(_ shower: ShowerEntry) async {
        guard canEditSelectedDate else { return }
        do {
            let locations = showerEntryLocations(id: shower.id)
            if locations.isEmpty {
                dailyRecord.showers.removeAll { $0.id == shower.id }
                persistCurrentRecord()
                await syncCurrentRecordToCloudIfNeeded()
                return
            }
            for location in locations {
                var record = location.record
                record.showers.removeAll { $0.id == shower.id }
                let savedRecord = try persistRecord(record)
                await syncRecordToCloudIfNeeded(savedRecord)
            }
        } catch {
            errorMessage = NSLocalizedString("删除洗澡失败：", comment: "") + error.localizedDescription
        }
    }

    func saveBowelMovement(_ entry: BowelMovementEntry) async {
        guard canEditSelectedDate else { return }
        var updated = entry
        let existingLocation = preferredBowelMovementEntryLocation(for: entry)
        let existingEntry = existingLocation?.entry
        updated.note = trimmedNote(entry.note)
        updated.travelContext = entry.travelContext
            ?? existingEntry?.travelContext
            ?? travelContextForCurrentRecording()
        updated.timeZoneIdentifier = entry.time != nil
            ? editedTimeZoneIdentifier(for: entry.timeZoneIdentifier, travelContext: updated.travelContext)
            : nil
        do {
            if let existingLocation {
                var record = existingLocation.record
                record.bowelMovements[existingLocation.index] = updated
                record.bowelMovements.sort { sortOptionalTimes($0.time, $1.time) }
                let savedRecord = try persistRecord(record)
                await syncRecordToCloudIfNeeded(savedRecord)
            } else if let index = dailyRecord.bowelMovements.firstIndex(where: { $0.id == entry.id }) {
                dailyRecord.bowelMovements[index] = updated
                dailyRecord.bowelMovements.sort { sortOptionalTimes($0.time, $1.time) }
                persistCurrentRecord()
                await syncCurrentRecordToCloudIfNeeded()
            } else {
                dailyRecord.bowelMovements.append(updated)
                dailyRecord.bowelMovements.sort { sortOptionalTimes($0.time, $1.time) }
                persistCurrentRecord()
                await syncCurrentRecordToCloudIfNeeded()
            }
        } catch {
            errorMessage = NSLocalizedString("保存排便失败：", comment: "") + error.localizedDescription
        }
    }

    func deleteBowelMovement(_ entry: BowelMovementEntry) async {
        guard canEditSelectedDate else { return }
        do {
            let locations = bowelMovementEntryLocations(id: entry.id)
            if locations.isEmpty {
                dailyRecord.bowelMovements.removeAll { $0.id == entry.id }
                persistCurrentRecord()
                await syncCurrentRecordToCloudIfNeeded()
                return
            }
            for location in locations {
                var record = location.record
                record.bowelMovements.removeAll { $0.id == entry.id }
                let savedRecord = try persistRecord(record)
                await syncRecordToCloudIfNeeded(savedRecord)
            }
        } catch {
            errorMessage = NSLocalizedString("删除排便失败：", comment: "") + error.localizedDescription
        }
    }

    func saveSexualActivity(_ entry: SexualActivityEntry) async {
        guard canEditSelectedDate else { return }
        var updated = entry
        let existingLocation = preferredSexualActivityEntryLocation(for: entry)
        let existingEntry = existingLocation?.entry
        updated.note = trimmedNote(entry.note)
        updated.travelContext = entry.travelContext
            ?? existingEntry?.travelContext
            ?? travelContextForCurrentRecording()
        if updated.time != nil {
            updated.timeZoneIdentifier = editedTimeZoneIdentifier(
                for: entry.timeZoneIdentifier,
                travelContext: updated.travelContext
            )
        }
        do {
            if let existingLocation {
                var record = existingLocation.record
                record.sexualActivities[existingLocation.index] = updated
                let savedRecord = try persistRecord(record)
                await syncRecordToCloudIfNeeded(savedRecord)
            } else if let index = dailyRecord.sexualActivities.firstIndex(where: { $0.id == entry.id }) {
                dailyRecord.sexualActivities[index] = updated
                persistCurrentRecord()
                await syncCurrentRecordToCloudIfNeeded()
            } else {
                dailyRecord.sexualActivities.append(updated)
                persistCurrentRecord()
                await syncCurrentRecordToCloudIfNeeded()
            }
        } catch {
            errorMessage = NSLocalizedString("保存性生活失败：", comment: "") + error.localizedDescription
        }
    }

    func deleteSexualActivity(_ entry: SexualActivityEntry) async {
        guard canEditSelectedDate else { return }
        do {
            let locations = sexualActivityEntryLocations(id: entry.id)
            if locations.isEmpty {
                dailyRecord.sexualActivities.removeAll { $0.id == entry.id }
                persistCurrentRecord()
                await syncCurrentRecordToCloudIfNeeded()
                return
            }
            for location in locations {
                var record = location.record
                record.sexualActivities.removeAll { $0.id == entry.id }
                let savedRecord = try persistRecord(record)
                await syncRecordToCloudIfNeeded(savedRecord)
            }
        } catch {
            errorMessage = NSLocalizedString("删除性生活失败：", comment: "") + error.localizedDescription
        }
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
        await refreshCurrentWeatherIfPossible()
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
            do {
                try loadTravelPlans(for: user.userID)
            } catch {
                errorMessage = NSLocalizedString("刷新旅行计划失败：", comment: "") + error.localizedDescription
            }
        }
        do {
            try loadSelectedRecord()
        } catch {
            errorMessage = NSLocalizedString("刷新记录失败：", comment: "") + error.localizedDescription
        }
        refreshLocationIfAuthorized()
        await refreshCurrentWeatherIfPossible()
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
            guard !healthKitSleepOverlapsTravel(hkSleep) else { return }

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
        let upper = min(range.upperBound.startOfDay, logicalToday)
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
        let normalized = normalizedTravelRecordTimeZones(in: record)
        if normalized.didChange {
            record = normalized.record
            try repository.saveRecord(record, preferences: preferences, userID: user.userID)
        }
        record.sleepRecord.targetBedtime = preferences.bedtimeSchedule.target(for: selectedDate)
        dailyRecord = mergedRecord(record, with: preferences)
        restoreEnvironmentSnapshot()
        refreshEnvironmentIfNeeded()
        Task { await syncHealthKitForCurrentDate() }
    }

    private func loadAllRecords(for userID: String) throws {
        let records = try repository.loadAllRecords(userID: userID, preferences: preferences)
            .filter { $0.date >= availableStartDate }
        allRecords = try migrateRecordedTimeZonesIfNeeded(in: records, userID: userID)
        Task { await refreshRemotePhotoCache() }
    }

    private func loadTravelPlans(for userID: String) throws {
        travelPlans = try travelPlanRepository.loadTravelPlans(userID: userID)
        try normalizeStoredTravelRecordTimeZonesIfNeeded(for: userID)
    }

    private func persistCurrentRecord() {
        guard let user, canEditSelectedDate else { return }
        do {
            dailyRecord.date = selectedDate.startOfDay
            dailyRecord.sleepRecord.targetBedtime = preferences.bedtimeSchedule.target(for: selectedDate)
            dailyRecord = mergedRecord(dailyRecord, with: preferences)
            dailyRecord.aiInsightNarrative = nil
            dailyRecord.modifiedAt = .now
            try repository.saveRecord(dailyRecord, preferences: preferences, userID: user.userID)
            try loadAllRecords(for: user.userID)
            invalidateDailyInsightNarrative()
        } catch {
            errorMessage = NSLocalizedString("保存记录失败：", comment: "") + error.localizedDescription
        }
    }

    @discardableResult
    private func persistRecord(_ record: DailyRecord) throws -> DailyRecord {
        guard let user else { return record }
        var updated = record
        updated.sleepRecord.targetBedtime = preferences.bedtimeSchedule.target(for: updated.date)
        updated = mergedRecord(updated, with: preferences)
        updated.aiInsightNarrative = nil
        updated.modifiedAt = .now
        try repository.saveRecord(updated, preferences: preferences, userID: user.userID)
        try loadAllRecords(for: user.userID)
        if updated.date.startOfDay == selectedDate.startOfDay {
            dailyRecord = mergedRecord(updated, with: preferences)
            restoreEnvironmentSnapshot()
            refreshEnvironmentIfNeeded()
        }
        invalidateDailyInsightNarrative()
        return updated
    }

    private func candidateRecordsForEntryLookup() -> [DailyRecord] {
        var recordsByKey: [String: DailyRecord] = [:]
        for record in allRecords + [dailyRecord] {
            let key = record.date.storageKey()
            if let existing = recordsByKey[key] {
                recordsByKey[key] = existing.mergedPreservingSupplementalContent(
                    with: record,
                    preferences: preferences
                )
            } else {
                recordsByKey[key] = record
            }
        }
        return recordsByKey.values.sorted { $0.date < $1.date }
    }

    private struct MealEntryLocation {
        var record: DailyRecord
        var index: Int
        var entry: MealEntry
    }

    private struct ShowerEntryLocation {
        var record: DailyRecord
        var index: Int
        var entry: ShowerEntry
    }

    private struct BowelMovementEntryLocation {
        var record: DailyRecord
        var index: Int
        var entry: BowelMovementEntry
    }

    private struct SexualActivityEntryLocation {
        var record: DailyRecord
        var index: Int
        var entry: SexualActivityEntry
    }

    private func mealEntryLocations(id: UUID) -> [MealEntryLocation] {
        candidateRecordsForEntryLookup().flatMap { record in
            record.meals.indices.compactMap { index in
                record.meals[index].id == id
                    ? MealEntryLocation(record: record, index: index, entry: record.meals[index])
                    : nil
            }
        }
    }

    private func showerEntryLocations(id: UUID) -> [ShowerEntryLocation] {
        candidateRecordsForEntryLookup().flatMap { record in
            record.showers.indices.compactMap { index in
                record.showers[index].id == id
                    ? ShowerEntryLocation(record: record, index: index, entry: record.showers[index])
                    : nil
            }
        }
    }

    private func bowelMovementEntryLocations(id: UUID) -> [BowelMovementEntryLocation] {
        candidateRecordsForEntryLookup().flatMap { record in
            record.bowelMovements.indices.compactMap { index in
                record.bowelMovements[index].id == id
                    ? BowelMovementEntryLocation(record: record, index: index, entry: record.bowelMovements[index])
                    : nil
            }
        }
    }

    private func sexualActivityEntryLocations(id: UUID) -> [SexualActivityEntryLocation] {
        candidateRecordsForEntryLookup().flatMap { record in
            record.sexualActivities.indices.compactMap { index in
                record.sexualActivities[index].id == id
                    ? SexualActivityEntryLocation(record: record, index: index, entry: record.sexualActivities[index])
                    : nil
            }
        }
    }

    private func preferredMealEntryLocation(for entry: MealEntry) -> MealEntryLocation? {
        preferredLocation(in: mealEntryLocations(id: entry.id), travelContext: entry.travelContext, entryContext: \.entry.travelContext)
    }

    private func preferredShowerEntryLocation(for entry: ShowerEntry) -> ShowerEntryLocation? {
        preferredLocation(in: showerEntryLocations(id: entry.id), travelContext: entry.travelContext, entryContext: \.entry.travelContext)
    }

    private func preferredBowelMovementEntryLocation(for entry: BowelMovementEntry) -> BowelMovementEntryLocation? {
        preferredLocation(in: bowelMovementEntryLocations(id: entry.id), travelContext: entry.travelContext, entryContext: \.entry.travelContext)
    }

    private func preferredSexualActivityEntryLocation(for entry: SexualActivityEntry) -> SexualActivityEntryLocation? {
        preferredLocation(in: sexualActivityEntryLocations(id: entry.id), travelContext: entry.travelContext, entryContext: \.entry.travelContext)
    }

    private func preferredLocation<Location>(
        in locations: [Location],
        travelContext: TravelRecordContext?,
        entryContext: KeyPath<Location, TravelRecordContext?>
    ) -> Location? {
        if let travelContext,
           let matchingContext = locations.first(where: { $0[keyPath: entryContext] == travelContext }) {
            return matchingContext
        }
        if let matchingSelectedDate = locations.first(where: { location in
            guard let recordDate = recordDate(for: location) else { return false }
            return recordDate.startOfDay == selectedDate.startOfDay
        }) {
            return matchingSelectedDate
        }
        return locations.first
    }

    private func recordDate<Location>(for location: Location) -> Date? {
        if let location = location as? MealEntryLocation { return location.record.date }
        if let location = location as? ShowerEntryLocation { return location.record.date }
        if let location = location as? BowelMovementEntryLocation { return location.record.date }
        if let location = location as? SexualActivityEntryLocation { return location.record.date }
        return nil
    }

    private func persistPreferences(invalidateInsights: Bool = true) {
        do {
            preferences.locationPermissionState = locationService.permissionState
            try preferencesStore.savePreferences(preferences, userID: user?.userID)
            if invalidateInsights {
                invalidateDailyInsightNarrative()
            }
        } catch {
            errorMessage = NSLocalizedString("保存偏好失败：", comment: "") + error.localizedDescription
        }
    }

    private func invalidateDailyInsightNarrative() {
        dailyInsightNarrative = nil
        dailyInsightNarrativeDate = nil
        aiInsightErrorMessage = nil
    }

    private func currentNarrative(for date: Date) -> DailyInsightNarrative? {
        if dailyInsightNarrativeDate?.startOfDay == date.startOfDay,
           let dailyInsightNarrative {
            return dailyInsightNarrative
        }
        return record(for: date)?.aiInsightNarrative
    }

    private func canonicalInsightPayload(for date: Date) -> DailyInsightPayload? {
        let resolvedRecord = record(for: date) ?? DailyRecord.empty(for: date, preferences: preferences)
        return DailyInsightAnalyzer.makePayload(
            record: mergedRecord(resolvedRecord, with: preferences),
            preferences: preferences,
            language: .zhHans,
            locale: Locale(identifier: "zh-Hans"),
            history: allRecords.map { mergedRecord($0, with: preferences) }
        )
    }

    private func insightPayload(for date: Date) -> DailyInsightPayload? {
        let resolvedRecord = record(for: date) ?? DailyRecord.empty(for: date, preferences: preferences)
        let locale = preferences.appLanguage.locale ?? Locale.autoupdatingCurrent
        return DailyInsightAnalyzer.makePayload(
            record: mergedRecord(resolvedRecord, with: preferences),
            preferences: preferences,
            language: preferences.appLanguage,
            locale: locale,
            history: allRecords.map { mergedRecord($0, with: preferences) }
        )
    }

    private func validatedNarrative(for date: Date) -> DailyInsightNarrative? {
        guard let narrative = currentNarrative(for: date),
              narrative.hasAIScoring,
              narrative.scoringVersion >= DailyInsightNarrative.currentScoringVersion,
              let payload = canonicalInsightPayload(for: date),
              let signature = try? payload.stableSignature(),
              narrative.payloadSignature == signature else {
            return nil
        }
        return narrative
    }

    private func localizedNarrative(_ narrative: DailyInsightNarrative?) -> DailyInsightNarrative? {
        narrative?.localized(
            for: preferences.appLanguage,
            locale: preferences.appLanguage.locale ?? Locale.autoupdatingCurrent
        )
    }

    private func backfillEnglishTranslationIfNeeded(
        for narrative: DailyInsightNarrative,
        date: Date
    ) async -> DailyInsightNarrative {
        let englishCode = AppLanguage.en.aiNarrativeLanguageCode()
        guard narrative.localizedTexts?[englishCode] == nil else {
            return narrative
        }

        do {
            let englishText = try await aiInsightNarrativeService.translateNarrative(narrative, to: .en)
            let updatedNarrative = narrative.addingLocalizedText(englishText, for: englishCode)
            try persistDailyInsightNarrative(updatedNarrative, for: date)
            return updatedNarrative
        } catch {
            return narrative
        }
    }

    private func record(for date: Date) -> DailyRecord? {
        if dailyRecord.date.startOfDay == date.startOfDay {
            return dailyRecord
        }
        return allRecords.first(where: { $0.date.startOfDay == date.startOfDay })
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

        try repository.saveRecord(storedRecord, preferences: preferences, userID: user.userID)
        try loadAllRecords(for: user.userID)

        if selectedDate.startOfDay == date.startOfDay {
            try loadSelectedRecord()
        }
    }

    private var automaticInsightTargetDate: Date? {
        let yesterday = logicalToday.adding(days: -1)
        guard availableStartDate <= yesterday else { return nil }
        return yesterday
    }

    private func ensureAutomaticYesterdayInsightIfNeeded() async {
        guard let targetDate = automaticInsightTargetDate else { return }
        guard validatedNarrative(for: targetDate)?.hasAIScoring != true else { return }
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
                        photoURL: nil,
                        isCustomTitleManuallyEdited: slot.kind == .custom
                    )
                )
            }
        }
        updated.meals = MealEntry.sortedByTime(updated.meals, on: updated.date)
        return updated
    }

    private func updateSunTimesIfPossible() {
        guard isViewingLogicalToday else { return }
        preferences.locationPermissionState = locationService.permissionState
        guard let coordinate = locationService.latestLocation?.coordinate else { return }
        let timeZone = locationService.detectedTimeZone ?? TimeZone.autoupdatingCurrent
        let sunTimes = sunTimesService.sunTimes(for: selectedDate, coordinate: coordinate, timeZone: timeZone)
        guard dailyRecord.sunTimes != sunTimes else { return }
        dailyRecord.sunTimes = sunTimes
        persistEnvironmentSnapshotIfNeeded()
    }

    private func refreshCurrentWeatherIfPossible() async {
        guard isViewingLogicalToday,
              locationService.permissionState == .authorized,
              let coordinate = locationService.latestLocation?.coordinate else {
            return
        }

        currentLocationName = locationService.detectedLocationName
        dailyRecord.locationName = currentLocationName

        do {
            let snapshot = try await weatherService.weather(at: coordinate)
            currentWeather = snapshot
            dailyRecord.weatherSnapshot = snapshot
            persistEnvironmentSnapshotIfNeeded()
        } catch {
            currentWeather = dailyRecord.weatherSnapshot
        }
    }

    private var isViewingLogicalToday: Bool {
        selectedDate.startOfDay == logicalToday
    }

    private func restoreEnvironmentSnapshot() {
        currentWeather = dailyRecord.weatherSnapshot
        currentLocationName = dailyRecord.locationName
    }

    private func refreshEnvironmentIfNeeded() {
        guard isViewingLogicalToday else { return }
        restoreEnvironmentSnapshot()
        updateSunTimesIfPossible()
        refreshLocationIfAuthorized()
    }

    private func persistEnvironmentSnapshotIfNeeded() {
        guard isViewingLogicalToday, let user else { return }
        do {
            dailyRecord.modifiedAt = .now
            try repository.saveRecord(dailyRecord, preferences: preferences, userID: user.userID)
            try loadAllRecords(for: user.userID)
        } catch {
            // Keep live environment refresh best-effort.
        }
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
                },
                preferences: preferences
            )

            if payload.records.isEmpty {
                if database.recordsByUser[user.userID] != prunedLocalRecordMap {
                    database.recordsByUser[user.userID] = prunedLocalRecordMap
                    try store.save(database)
                }
                allRecords = prunedLocalRecordMap.values.sorted { $0.date < $1.date }
                let normalizedRecords = try normalizeStoredTravelRecordTimeZonesIfNeeded(for: user.userID)
                for record in deduplicatedPendingUploads(normalizedRecords) {
                    try await cloudSyncService.pushRecord(record, user: user)
                }
                await refreshRemotePhotoCache()
            }

            if !payload.records.isEmpty {
                let localRecordMap = prunedLocalRecordMap
                let remoteRecordMap = Self.recordsByStorageKey(payload.records, preferences: preferences)
                var merged = remoteRecordMap
                var recordsToPush: [DailyRecord] = []
                var discardedRemotePhotoReferences = Set<String>()
                for (key, localRecord) in localRecordMap {
                    guard let remoteRecord = merged[key] else {
                        merged[key] = localRecord
                        recordsToPush.append(localRecord)
                        continue
                    }
                    let reconciliation = Self.reconcileCloudRecord(localRecord: localRecord, remoteRecord: remoteRecord)
                    merged[key] = reconciliation.record.backfillingRecordedTimeZones(TimeZone.autoupdatingCurrent.identifier)
                    discardedRemotePhotoReferences.formUnion(reconciliation.discardedRemotePhotoReferences)
                    if reconciliation.shouldPushRecord {
                        recordsToPush.append(reconciliation.record)
                    }
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
                let normalizedRecords = try normalizeStoredTravelRecordTimeZonesIfNeeded(for: user.userID)
                await refreshRemotePhotoCache()

                await deleteCloudPhotoReferencesIfPossible(Array(discardedRemotePhotoReferences))

                for record in deduplicatedPendingUploads(recordsToPush + normalizedRecords) {
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

    static func reconcileCloudRecord(localRecord: DailyRecord, remoteRecord: DailyRecord) -> CloudRecordReconciliationResult {
        let localRecordIsPreferred = DailyRecord.preferredRecord(between: localRecord, and: remoteRecord) == localRecord
        var mergedRecord = localRecord.mergedPreservingSupplementalContent(
            with: remoteRecord,
            preferences: UserPreferences()
        )
        var discardedRemotePhotoReferences = Set<String>()

        if localRecordIsPreferred {
            restoreRemoteMediaForMissingLocalReferences(in: &mergedRecord, from: remoteRecord)
        }
        let shouldPushRecord = mergedRecord != remoteRecord
        if shouldPushRecord {
            discardedRemotePhotoReferences = remotePhotoReferences(in: remoteRecord, excluding: mergedRecord)
        }

        return CloudRecordReconciliationResult(
            record: mergedRecord,
            shouldPushRecord: shouldPushRecord,
            discardedRemotePhotoReferences: discardedRemotePhotoReferences
        )
    }

    private static func restoreRemoteMediaForMissingLocalReferences(in record: inout DailyRecord, from remoteRecord: DailyRecord) {
        for index in record.meals.indices {
            let localPhotos = record.meals[index].photoURLs
            let missingLocalPhotos = localPhotos.filter {
                Self.isMissingLocalPhotoReference($0)
            }
            guard !missingLocalPhotos.isEmpty else {
                continue
            }

            if let remoteMeal = remoteRecord.meals.first(where: { $0.id == record.meals[index].id }),
               !remoteMeal.photoURLs.isEmpty {
                record.meals[index].photoURLs = remoteMeal.photoURLs
            }
        }

        if let localVideo = record.dailyVideo,
           Self.isMissingLocalVideoReference(localVideo.videoURL),
           let remoteVideo = remoteRecord.dailyVideo,
           Self.isRemoteVideoURL(remoteVideo.videoURL) {
            record.dailyVideo = remoteVideo
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

    private func syncRecordToCloudIfNeeded(_ record: DailyRecord) async {
        guard let user, !user.isGuest, cloudSyncService.isAvailable else { return }
        do {
            try await cloudSyncService.pushRecord(record, user: user)
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
        let lower = max(start.startOfDay, logicalToday.adding(days: -29))
        return lower...logicalToday
    }

    private func rekeyAllRecords(for userID: String) throws {
        let rekeyed = Self.recordsByStorageKey(allRecords, preferences: preferences)
        let store = LocalJSONStore()
        var database = try store.load()
        database.recordsByUser[userID] = rekeyed
        try store.save(database)
        try loadAllRecords(for: userID)
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
        await RemoteVideoCache.shared.syncRetention(with: recentRemoteVideoURLs())
    }

    private func recentRemotePhotoURLs() -> [String] {
        let lowerBound = logicalToday.adding(days: -6)
        let urls = allRecords
            .filter { $0.date >= lowerBound }
            .flatMap { record in
                record.meals
                    .flatMap(\.photoURLs)
                    .filter(Self.isRemotePhotoURL)
            }

        return Array(Set(urls))
    }

    private func recentRemoteVideoURLs() -> [String] {
        let lowerBound = logicalToday.adding(days: -6)
        let urls = allRecords
            .filter { $0.date >= lowerBound }
            .compactMap(\.dailyVideo?.videoURL)
            .filter(Self.isRemoteVideoURL)

        return Array(Set(urls))
    }

    private static func isRemotePhotoURL(_ urlString: String) -> Bool {
        urlString.hasPrefix("http://")
            || urlString.hasPrefix("https://")
            || SecureCloudPhotoReference.isSecureReference(urlString)
    }

    private static func isRemoteVideoURL(_ urlString: String) -> Bool {
        urlString.hasPrefix("http://")
            || urlString.hasPrefix("https://")
            || SecureCloudMediaReference.isSecureReference(urlString)
    }

    private static func remotePhotoReferences(in source: DailyRecord, excluding retained: DailyRecord) -> Set<String> {
        let retainedPhotoReferences = Set(retained.meals.flatMap(\.photoURLs))
        return Set(
            source.meals
                .flatMap(\.photoURLs)
                .filter { isRemotePhotoURL($0) && !retainedPhotoReferences.contains($0) }
        )
    }

    private static func isMissingLocalPhotoReference(_ urlString: String) -> Bool {
        !isRemotePhotoURL(urlString) && !LocalPhotoStorageService.isResolvableLocalReference(urlString)
    }

    private static func isMissingLocalVideoReference(_ urlString: String) -> Bool {
        !isRemoteVideoURL(urlString) && !LocalVideoStorageService.isResolvableLocalReference(urlString)
    }

    nonisolated static func recordsByStorageKey(_ records: [DailyRecord], preferences: UserPreferences) -> [String: DailyRecord] {
        records.reduce(into: [:]) { partialResult, record in
            let normalized = normalizedRecord(record, preferences: preferences)
            let key = normalized.canonicalStorageKey(using: preferences, fallback: normalized.date.storageKey())

            if let existing = partialResult[key] {
                partialResult[key] = existing.mergedPreservingSupplementalContent(
                    with: normalized,
                    preferences: preferences
                )
            } else {
                partialResult[key] = normalized
            }
        }
    }

    private nonisolated static func normalizedRecord(_ record: DailyRecord, preferences: UserPreferences) -> DailyRecord {
        let key = record.canonicalStorageKey(using: preferences, fallback: record.date.storageKey())
        return record.anchoredToStorageKey(key)
    }

    private func bindLocationService() {
        Publishers.CombineLatest4(
            locationService.$latestLocation,
            locationService.$detectedTimeZone,
            locationService.$detectedLocationName,
            locationService.$permissionState
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _, _, locationName, permissionState in
            guard let self else { return }
            self.preferences.locationPermissionState = permissionState
            guard self.isViewingLogicalToday else { return }

            guard permissionState == .authorized else {
                self.dailyRecord.sunTimes = nil
                self.dailyRecord.locationName = nil
                self.dailyRecord.weatherSnapshot = nil
                self.currentWeather = nil
                self.currentLocationName = nil
                return
            }

            self.currentLocationName = locationName
            self.dailyRecord.locationName = locationName
            self.updateSunTimesIfPossible()
            Task { await self.refreshCurrentWeatherIfPossible() }
        }
        .store(in: &cancellables)
    }

    private func refreshLocationIfAuthorized() {
        guard isViewingLogicalToday, locationService.permissionState == .authorized else { return }
        locationService.refreshCurrentLocation()
    }

    private struct MigratedRecordsResult {
        var records: [DailyRecord]
        var changedRecords: [DailyRecord]
    }

    private func migrateRecordedTimeZonesIfNeeded(in records: [DailyRecord], userID: String) throws -> [DailyRecord] {
        try migrateRecordedTimeZones(in: records, userID: userID).records
    }

    private func migrateRecordedTimeZones(in records: [DailyRecord], userID: String) throws -> MigratedRecordsResult {
        let identifier = TimeZone.autoupdatingCurrent.identifier
        var changedRecords: [DailyRecord] = []
        let migrated = records.map { record in
            let normalized = normalizedTravelRecordTimeZones(in: record.backfillingRecordedTimeZones(identifier)).record
            if normalized != record {
                changedRecords.append(normalized)
            }
            return normalized
        }
        let sorted = migrated.sorted { $0.date < $1.date }
        guard !changedRecords.isEmpty else {
            return MigratedRecordsResult(records: sorted, changedRecords: [])
        }
        for record in changedRecords {
            try repository.saveRecord(record, preferences: preferences, userID: userID)
        }
        return MigratedRecordsResult(records: sorted, changedRecords: changedRecords)
    }

    @discardableResult
    private func normalizeStoredTravelRecordTimeZonesIfNeeded(for userID: String) throws -> [DailyRecord] {
        guard !travelPlans.isEmpty else { return [] }
        let records = try repository.loadAllRecords(userID: userID, preferences: preferences)
            .filter { $0.date >= availableStartDate }
        let migration = try migrateRecordedTimeZones(in: records, userID: userID)
        allRecords = migration.records
        return migration.changedRecords
    }

    private struct NormalizedTravelTimestamp {
        var date: Date
        var timeZoneIdentifier: String?
        var travelContext: TravelRecordContext?
    }

    private func normalizedTravelRecordTimeZones(in record: DailyRecord) -> (record: DailyRecord, didChange: Bool) {
        guard !travelPlans.isEmpty else { return (record, false) }
        var updated = record
        updated.meals = record.meals.map { normalizedTravelMeal($0) }
        updated.showers = record.showers.map { normalizedTravelShower($0) }
        updated.bowelMovements = record.bowelMovements.map { normalizedTravelBowelMovement($0) }
        updated.sexualActivities = record.sexualActivities.map { normalizedTravelSexualActivity($0) }
        return (updated, updated != record)
    }

    private func normalizedTravelMeal(_ meal: MealEntry) -> MealEntry {
        guard let time = meal.time else { return meal }
        let normalized = normalizedTravelTimestamp(
            time,
            recordedTimeZoneIdentifier: meal.timeZoneIdentifier,
            travelContext: meal.travelContext
        )
        guard normalized.date != time
            || normalized.timeZoneIdentifier != meal.timeZoneIdentifier
            || normalized.travelContext != meal.travelContext else {
            return meal
        }
        var updated = meal
        updated.time = normalized.date
        updated.timeZoneIdentifier = normalized.timeZoneIdentifier
        updated.travelContext = normalized.travelContext
        return updated
    }

    private func normalizedTravelShower(_ shower: ShowerEntry) -> ShowerEntry {
        guard let time = shower.time else { return shower }
        let normalized = normalizedTravelTimestamp(
            time,
            recordedTimeZoneIdentifier: shower.timeZoneIdentifier,
            travelContext: shower.travelContext
        )
        guard normalized.date != time
            || normalized.timeZoneIdentifier != shower.timeZoneIdentifier
            || normalized.travelContext != shower.travelContext else {
            return shower
        }
        var updated = shower
        updated.time = normalized.date
        updated.timeZoneIdentifier = normalized.timeZoneIdentifier
        updated.travelContext = normalized.travelContext
        return updated
    }

    private func normalizedTravelBowelMovement(_ entry: BowelMovementEntry) -> BowelMovementEntry {
        guard let time = entry.time else { return entry }
        let normalized = normalizedTravelTimestamp(
            time,
            recordedTimeZoneIdentifier: entry.timeZoneIdentifier,
            travelContext: entry.travelContext
        )
        guard normalized.date != time
            || normalized.timeZoneIdentifier != entry.timeZoneIdentifier
            || normalized.travelContext != entry.travelContext else {
            return entry
        }
        var updated = entry
        updated.time = normalized.date
        updated.timeZoneIdentifier = normalized.timeZoneIdentifier
        updated.travelContext = normalized.travelContext
        return updated
    }

    private func normalizedTravelSexualActivity(_ entry: SexualActivityEntry) -> SexualActivityEntry {
        guard let time = entry.time else { return entry }
        let normalized = normalizedTravelTimestamp(
            time,
            recordedTimeZoneIdentifier: entry.timeZoneIdentifier,
            travelContext: entry.travelContext
        )
        guard normalized.date != time
            || normalized.timeZoneIdentifier != entry.timeZoneIdentifier
            || normalized.travelContext != entry.travelContext else {
            return entry
        }
        var updated = entry
        updated.time = normalized.date
        updated.timeZoneIdentifier = normalized.timeZoneIdentifier
        updated.travelContext = normalized.travelContext
        return updated
    }

    private func normalizedTravelTimestamp(
        _ date: Date,
        recordedTimeZoneIdentifier: String?,
        travelContext: TravelRecordContext?
    ) -> NormalizedTravelTimestamp {
        guard let travelContext,
              let plan = travelPlan(for: travelContext),
              let resolution = resolvedTravelSegment(for: date, context: travelContext, in: plan),
              let expectedTimeZone = TimeZone(identifier: resolution.segment.departureTimeZoneIdentifier) else {
            return NormalizedTravelTimestamp(
                date: date,
                timeZoneIdentifier: recordedTimeZoneIdentifier,
                travelContext: travelContext
            )
        }

        var normalizedContext = travelContext
        normalizedContext.segmentID = resolution.segment.id

        var candidateDate = resolution.date
        if let sourceIdentifier = recordedTimeZoneIdentifier,
           sourceIdentifier != resolution.segment.departureTimeZoneIdentifier,
           let sourceTimeZone = TimeZone(identifier: sourceIdentifier) {
            let retaggedDate = retaggingWallClock(
                date,
                from: sourceTimeZone,
                to: expectedTimeZone
            )
            candidateDate = preferredTravelRecordDate(
                originalDate: date,
                retaggedDate: retaggedDate,
                segment: resolution.segment,
                phase: travelContext.phase
            )
        }
        let repairedDate = repairedTravelRecordTimestampIfNeeded(
            candidateDate,
            segment: resolution.segment,
            phase: travelContext.phase
        )
        return NormalizedTravelTimestamp(
            date: repairedDate,
            timeZoneIdentifier: resolution.segment.departureTimeZoneIdentifier,
            travelContext: normalizedContext
        )
    }

    private func preferredTravelRecordDate(
        originalDate: Date,
        retaggedDate: Date,
        segment: TravelSegment,
        phase: TravelPlanStatus
    ) -> Date {
        guard phase == .inFlight else { return retaggedDate }

        let retaggedIsInSegment = travelDate(retaggedDate, isIn: segment)
        let originalIsInSegment = travelDate(originalDate, isIn: segment)
        if retaggedIsInSegment {
            return retaggedDate
        }
        if originalIsInSegment {
            return originalDate
        }
        return retaggedDate
    }

    private func repairedTravelRecordTimestampIfNeeded(
        _ date: Date,
        segment: TravelSegment,
        phase: TravelPlanStatus
    ) -> Date {
        guard phase == .inFlight,
              !travelDate(date, isIn: segment) else {
            return date
        }

        let departureOffset = TimeInterval(segment.departureTimeZone.secondsFromGMT(for: date))
        let arrivalOffset = TimeInterval(segment.arrivalTimeZone.secondsFromGMT(for: date))
        let routeOffsetDelta = departureOffset - arrivalOffset
        guard routeOffsetDelta != 0 else { return date }

        let candidates = [
            date.addingTimeInterval(routeOffsetDelta),
            date.addingTimeInterval(-routeOffsetDelta)
        ]
        return candidates.first { candidate in
            travelDate(candidate, isIn: segment)
        } ?? date
    }

    private func retaggingWallClock(_ date: Date, from sourceTimeZone: TimeZone, to destinationTimeZone: TimeZone) -> Date {
        var sourceCalendar = Calendar(identifier: .gregorian)
        sourceCalendar.locale = .autoupdatingCurrent
        sourceCalendar.timeZone = sourceTimeZone
        let components = sourceCalendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)

        var destinationCalendar = Calendar(identifier: .gregorian)
        destinationCalendar.locale = .autoupdatingCurrent
        destinationCalendar.timeZone = destinationTimeZone
        return destinationCalendar.date(from: DateComponents(
            timeZone: destinationTimeZone,
            year: components.year,
            month: components.month,
            day: components.day,
            hour: components.hour,
            minute: components.minute,
            second: components.second ?? 0
        )) ?? date
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
        guard entry.travelContext == nil else { return nil }
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
        guard entry.travelContext == nil else { return nil }
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

    private func deleteVideoIfLocal(at path: String) throws {
        guard !Self.isRemoteVideoURL(path) else { return }
        try videoStorageService.deleteVideo(at: path)
    }

    private func deleteMealPhotos(_ photoURLs: [String]) async throws {
        await RemotePhotoCache.shared.remove(photoURLs.filter(Self.isRemotePhotoURL))
        for photoURL in photoURLs {
            if Self.isRemotePhotoURL(photoURL) {
                await deleteCloudPhotoReferenceIfPossible(photoURL)
            } else {
                try deletePhotoIfLocal(at: photoURL)
            }
        }
    }

    private func deleteCloudPhotoReferencesIfPossible(_ photoReferences: [String]) async {
        for photoReference in Set(photoReferences.filter(Self.isRemotePhotoURL)) {
            await deleteCloudPhotoReferenceIfPossible(photoReference)
        }
    }

    private func deleteCloudPhotoReferenceIfPossible(_ photoReference: String) async {
        guard let user, !user.isGuest, cloudSyncService.isAvailable else { return }
        do {
            try await cloudSyncService.deletePhotoReference(photoReference, user: user)
        } catch {
            if isConnectivityError(error) {
                return
            }
            #if DEBUG
            print("CloudSync: failed to delete meal photo \(photoReference): \(error)")
            #endif
        }
    }

    func travelTimeDisplay(for date: Date?, context: TravelRecordContext?) -> TravelTimeDisplay? {
        guard let date else { return nil }

        if let context,
           let plan = travelPlans.first(where: { $0.id == context.planID }) {
            let segment = resolvedTravelSegment(for: date, context: context, in: plan)?.segment
                ?? travelSegment(containing: date, in: plan)
                ?? plan.currentSegment
            return travelTimeDisplay(for: date, phase: context.phase, segment: segment)
        }

        for plan in travelPlans {
            if let segment = travelSegment(containing: date, in: plan),
               let display = travelTimeDisplay(for: date, phase: .inFlight, segment: segment) {
                return display
            }
        }
        return nil
    }

    func travelTimeText(for date: Date?, context: TravelRecordContext?) -> String? {
        guard let display = travelTimeDisplay(for: date, context: context) else { return nil }
        guard let secondary = display.secondary else { return display.primary }
        return "\(display.primary) · \(secondary)"
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
        let timeZone = displayedTimeZone(for: recordedTimeZoneIdentifier)
        return date.displayClockTime(in: timeZone) + nextDayDisplaySuffix(for: date, displayedTimeZone: timeZone)
    }

    func displayedShortTime(for date: Date, recordedTimeZoneIdentifier: String?) -> String {
        let timeZone = displayedTimeZone(for: recordedTimeZoneIdentifier)
        return date.displayShortTime(in: timeZone) + nextDayDisplaySuffix(for: date, displayedTimeZone: timeZone)
    }

    func recordingTimeZone(
        for recordedTimeZoneIdentifier: String?,
        travelContext: TravelRecordContext? = nil
    ) -> TimeZone {
        if let identifier = travelRecordingTimeZoneIdentifier(for: travelContext),
           let timeZone = TimeZone(identifier: identifier) {
            return timeZone
        }
        return displayedTimeZone(for: recordedTimeZoneIdentifier)
    }

    func suggestedEventTimestamp(
        for logicalDate: Date,
        recordedTimeZoneIdentifier: String?,
        referenceDate: Date = .now,
        travelContext: TravelRecordContext? = nil
    ) -> Date {
        let timeZone = recordingTimeZone(for: recordedTimeZoneIdentifier, travelContext: travelContext)
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.hour, .minute], from: referenceDate)
        return resolvedEventTimestamp(
            for: logicalDate,
            hour: components.hour ?? 12,
            minute: components.minute ?? 0,
            recordedTimeZoneIdentifier: recordedTimeZoneIdentifier,
            travelContext: travelContext
        )
    }

    func resolvedEventTimestamp(
        for logicalDate: Date,
        hour: Int,
        minute: Int,
        recordedTimeZoneIdentifier: String?,
        travelContext: TravelRecordContext? = nil
    ) -> Date {
        let timeZone = recordingTimeZone(for: recordedTimeZoneIdentifier, travelContext: travelContext)
        return resolvedTimestamp(
            for: logicalDate,
            hour: hour,
            minute: minute,
            timeZone: timeZone,
            appliesMidnightMode: shouldApplyMidnightMode(for: travelContext)
        )
    }

    func normalizedEventTimestamp(
        from displayedTime: Date,
        baseDate: Date,
        recordedTimeZoneIdentifier: String?,
        travelContext: TravelRecordContext? = nil
    ) -> Date {
        let timeZone = recordingTimeZone(for: recordedTimeZoneIdentifier, travelContext: travelContext)
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.hour, .minute], from: displayedTime)
        return resolvedTimestamp(
            for: baseDate,
            hour: components.hour ?? 12,
            minute: components.minute ?? 0,
            timeZone: timeZone,
            appliesMidnightMode: shouldApplyMidnightMode(for: travelContext)
        )
    }

    func normalizedBedtimeTimestamp(
        from displayedTime: Date,
        baseDate: Date,
        recordedTimeZoneIdentifier: String?
    ) -> Date {
        let timeZone = displayedTimeZone(for: recordedTimeZoneIdentifier)
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.hour, .minute], from: displayedTime)
        let hour = components.hour ?? 23
        let minute = components.minute ?? 30

        if hour >= 12 {
            return baseDate.adding(days: -1).settingTime(hour: hour, minute: minute, in: timeZone)
        }

        return resolvedTimestamp(for: baseDate, hour: hour, minute: minute, timeZone: timeZone)
    }

    private func convertedTemperatureValue(from celsius: Double) -> Double {
        switch preferences.temperatureUnit {
        case .celsius:
            celsius
        case .fahrenheit:
            celsius * 9 / 5 + 32
        }
    }

    private func formattedTemperature(_ celsius: Double) -> String {
        let value = convertedTemperatureValue(from: celsius)
        return String(format: "%.0f°%@", value.rounded(), preferences.temperatureUnit.symbol)
    }

    func formattedCurrentTemperature() -> String {
        guard let currentWeather else { return "--" }
        return formattedTemperature(currentWeather.temperatureCelsius)
    }

    func formattedDailyTemperatureRange() -> String {
        guard let currentWeather else { return "--" }
        let low = convertedTemperatureValue(from: currentWeather.lowTemperatureCelsius).rounded()
        let high = convertedTemperatureValue(from: currentWeather.highTemperatureCelsius).rounded()
        return String(format: "%.0f ~ %.0f°%@", low, high, preferences.temperatureUnit.symbol)
    }

    func currentWeatherSummary() -> String {
        guard let currentWeather else { return "--" }
        return "\(currentWeather.conditionDescription) · \(formattedDailyTemperatureRange())"
    }

    private func editedTimeZoneIdentifier(
        for recordedTimeZoneIdentifier: String?,
        travelContext: TravelRecordContext? = nil
    ) -> String {
        if let identifier = travelRecordingTimeZoneIdentifier(for: travelContext) {
            return identifier
        }
        switch preferences.timeDisplayMode {
        case .current:
            return TimeZone.autoupdatingCurrent.identifier
        case .recorded:
            return recordedTimeZoneIdentifier ?? TimeZone.autoupdatingCurrent.identifier
        }
    }

    private func travelRecordingTimeZoneIdentifier(for context: TravelRecordContext?) -> String? {
        guard let segment = travelSegment(for: context) else { return nil }
        return segment.departureTimeZoneIdentifier
    }

    private func travelPlan(for context: TravelRecordContext?) -> TravelPlan? {
        guard let context else { return nil }
        return travelPlans.first(where: { $0.id == context.planID })
    }

    private func travelSegment(for context: TravelRecordContext?) -> TravelSegment? {
        guard let context, let plan = travelPlan(for: context) else {
            return nil
        }
        if let segmentID = context.segmentID,
           let segment = plan.segments.first(where: { $0.id == segmentID }) {
            return segment
        }
        return plan.currentSegment ?? plan.segments.first
    }

    private func resolvedTravelSegment(
        for date: Date,
        context: TravelRecordContext,
        in plan: TravelPlan
    ) -> (segment: TravelSegment, date: Date)? {
        if let segmentID = context.segmentID,
           let segment = plan.segments.first(where: { $0.id == segmentID }) {
            let repairedDate = repairedTravelRecordTimestampIfNeeded(
                date,
                segment: segment,
                phase: context.phase
            )
            if travelDate(date, isIn: segment) || travelDate(repairedDate, isIn: segment) {
                return (segment, repairedDate)
            }
        }

        if let inferred = inferredTravelSegment(for: date, phase: context.phase, in: plan) {
            return inferred
        }

        if let segmentID = context.segmentID,
           let segment = plan.segments.first(where: { $0.id == segmentID }) {
            return (segment, date)
        }
        guard let closest = closestTravelSegment(to: date, in: plan) else { return nil }
        return (closest, date)
    }

    private func inferredTravelSegment(
        for date: Date,
        phase: TravelPlanStatus,
        in plan: TravelPlan
    ) -> (segment: TravelSegment, date: Date)? {
        var bestMatch: (segment: TravelSegment, date: Date, score: TimeInterval)?
        for segment in plan.segments {
            let candidates = travelRecordTimestampCandidates(for: date, segment: segment, phase: phase)
            for (index, candidate) in candidates.enumerated() where travelDate(candidate, isIn: segment) {
                let score = TimeInterval(index) * 86_400 + distanceFromSegmentMidpoint(candidate, segment: segment)
                if bestMatch == nil || score < bestMatch!.score {
                    bestMatch = (segment, candidate, score)
                }
            }
        }
        guard let bestMatch else { return nil }
        return (bestMatch.segment, bestMatch.date)
    }

    private func travelRecordTimestampCandidates(
        for date: Date,
        segment: TravelSegment,
        phase: TravelPlanStatus
    ) -> [Date] {
        guard phase == .inFlight else { return [date] }
        let departureOffset = TimeInterval(segment.departureTimeZone.secondsFromGMT(for: date))
        let arrivalOffset = TimeInterval(segment.arrivalTimeZone.secondsFromGMT(for: date))
        let routeOffsetDelta = departureOffset - arrivalOffset
        guard routeOffsetDelta != 0 else { return [date] }
        return [
            date,
            date.addingTimeInterval(routeOffsetDelta),
            date.addingTimeInterval(-routeOffsetDelta)
        ]
    }

    private func closestTravelSegment(to date: Date, in plan: TravelPlan) -> TravelSegment? {
        plan.segments.min { lhs, rhs in
            distanceFromSegmentWindow(date, segment: lhs) < distanceFromSegmentWindow(date, segment: rhs)
        }
    }

    private func travelDate(_ date: Date, isIn segment: TravelSegment) -> Bool {
        date >= segment.departureTime && date <= segment.arrivalTime
    }

    private func distanceFromSegmentWindow(_ date: Date, segment: TravelSegment) -> TimeInterval {
        if date < segment.departureTime {
            return segment.departureTime.timeIntervalSince(date)
        }
        if date > segment.arrivalTime {
            return date.timeIntervalSince(segment.arrivalTime)
        }
        return 0
    }

    private func distanceFromSegmentMidpoint(_ date: Date, segment: TravelSegment) -> TimeInterval {
        let midpoint = segment.departureTime.addingTimeInterval(segment.arrivalTime.timeIntervalSince(segment.departureTime) / 2)
        return abs(date.timeIntervalSince(midpoint))
    }

    private func travelTimeDisplay(
        for date: Date,
        phase: TravelPlanStatus,
        segment: TravelSegment?
    ) -> TravelTimeDisplay? {
        guard let segment else { return nil }
        switch phase {
        case .inFlight:
            let elapsed = max(0, date.timeIntervalSince(segment.departureTime))
            return TravelTimeDisplay(
                primary: "\(segment.routeTitle) " + NSLocalizedString("起飞后 ", comment: "") + compactDurationText(elapsed),
                secondary: "\(segment.originCode) \(date.displayClockTime(in: segment.departureTimeZone)) / \(segment.destinationCode) \(date.displayClockTime(in: segment.arrivalTimeZone))"
            )
        case .preDeparture, .planned:
            return TravelTimeDisplay(
                primary: "\(segment.originCode) " + date.displayClockTime(in: segment.departureTimeZone),
                secondary: NSLocalizedString("出发前", comment: "")
            )
        case .layover:
            return TravelTimeDisplay(
                primary: "\(segment.originCode) " + date.displayClockTime(in: segment.departureTimeZone),
                secondary: NSLocalizedString("转机中", comment: "")
            )
        case .arrived, .completed:
            return TravelTimeDisplay(
                primary: "\(segment.originCode) " + date.displayClockTime(in: segment.departureTimeZone),
                secondary: phase.title
            )
        }
    }

    private func travelSegment(containing date: Date, in plan: TravelPlan) -> TravelSegment? {
        plan.segments.first { segment in
            date >= segment.departureTime && date <= segment.arrivalTime
        }
    }

    private func compactDurationText(_ duration: TimeInterval) -> String {
        let totalMinutes = max(0, Int(duration.rounded() / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 {
            return "\(minutes)m"
        }
        return "\(hours)h \(minutes)m"
    }

    private func shouldApplyMidnightMode(for travelContext: TravelRecordContext?) -> Bool {
        travelContext == nil && travelContextForCurrentRecording() == nil
    }

    private func resolvedTimestamp(
        for logicalDate: Date,
        hour: Int,
        minute: Int,
        timeZone: TimeZone,
        appliesMidnightMode: Bool = true
    ) -> Date {
        let sameDay = logicalDate.settingTime(hour: hour, minute: minute, in: timeZone)
        guard appliesMidnightMode,
              preferences.midnightMode.isEnabled,
              hour < MidnightModeSettings.fixedCutoffHour else {
            return sameDay
        }

        let nextDay = logicalDate.adding(days: 1).settingTime(hour: hour, minute: minute, in: timeZone)
        guard preferences.midnightMode.applies(to: nextDay) else {
            return sameDay
        }

        return nextDay
    }

    private func normalizeSelectedDateForCurrentDayBoundaryIfNeeded() async {
        let range = selectableDateRange
        let normalized = min(max(selectedDate.startOfDay, range.lowerBound), range.upperBound)
        guard normalized != selectedDate.startOfDay else { return }
        selectedDate = normalized
        do {
            try loadSelectedRecord()
        } catch {
            errorMessage = NSLocalizedString("加载记录失败：", comment: "") + error.localizedDescription
        }
    }

    private func shouldAttemptAutomaticHealthKitSync() -> Bool {
        guard selectedDate.startOfDay == logicalToday else { return false }
        if preferences.midnightMode.isEnabled, logicalToday != Date().startOfDay {
            return false
        }
        return !dailyRecord.sleepRecord.hasSleepData
    }

    private func healthKitSleepOverlapsTravel(_ sleepRecord: SleepRecord) -> Bool {
        guard let sleepInterval = sleepRecord.recordedInterval else { return false }
        return travelPlans.contains { plan in
            guard let travelInterval = plan.plannedTravelInterval else { return false }
            return sleepInterval.intersects(travelInterval)
        }
    }

    private func nextDayDisplaySuffix(for date: Date, displayedTimeZone: TimeZone) -> String {
        guard preferences.midnightMode.isEnabled else { return "" }

        var calendar = Calendar.current
        calendar.timeZone = displayedTimeZone
        let displayedDay = calendar.startOfDay(for: date)
        let referenceDay = calendar.startOfDay(for: selectedDate)
        guard displayedDay > referenceDay else { return "" }

        return " " + NSLocalizedString("+1", comment: "")
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
        let deduplicated = Self.recordsByStorageKey(records, preferences: preferences)
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

import AuthenticationServices
import CoreLocation
import CryptoKit
import FirebaseAuth
import Foundation
import UIKit

@MainActor
protocol AuthService {
    var currentUser: UserAccount? { get }
    func restoreSession() -> UserAccount?
    func prepareAppleSignIn(_ request: ASAuthorizationAppleIDRequest)
    func handleAppleSignIn(result: Result<ASAuthorization, Error>) async throws -> UserAccount
    func continueAsGuest() throws -> UserAccount
    func updateDisplayName(_ name: String, for user: UserAccount) throws -> UserAccount
    func signOut() throws
}

protocol DailyRecordRepository {
    func loadRecord(for date: Date, preferences: UserPreferences, userID: String) throws -> DailyRecord
    func saveRecord(_ record: DailyRecord, userID: String) throws
    func loadAllRecords(userID: String) throws -> [DailyRecord]
}

protocol PreferencesStore {
    func loadPreferences(userID: String?) throws -> UserPreferences
    func savePreferences(_ preferences: UserPreferences, userID: String?) throws
}

protocol PhotoStorageService {
    func savePhoto(_ image: UIImage) throws -> String
    func deletePhoto(at path: String) throws
}

protocol SunTimesService {
    func sunTimes(for date: Date, coordinate: CLLocationCoordinate2D, timeZone: TimeZone) -> SunTimes?
}

@MainActor
protocol HealthSyncAdapter {
    func requestAuthorization() async throws
    func fetchSleepData(for date: Date, after registrationDate: Date) async throws -> SleepRecord?
}

final class LocalAuthService: AuthService {
    private struct FirebaseUserSnapshot: Sendable {
        var uid: String
        var displayName: String?
        var email: String?
        var creationDate: Date?
    }

    private let defaults = UserDefaults.standard
    private let key = "dailylogs.currentUser"
    private let guestID = "guest.local"
    private let store: LocalJSONStore
    private var currentNonce: String?

    init(store: LocalJSONStore) {
        self.store = store
    }

    var currentUser: UserAccount? {
        if let session = persistedSession, session.isGuest {
            return session
        }
        FirebaseBootstrap.configureIfPossible()
        guard FirebaseBootstrap.isConfigured, let firebaseUser = Auth.auth().currentUser else {
            return nil
        }
        return buildAppleUser(from: firebaseUser, fallback: persistedSession)
    }

    func restoreSession() -> UserAccount? {
        if let guestSession = persistedSession, guestSession.isGuest {
            let refreshed = refreshUser(guestSession)
            if let refreshed {
                persistSession(refreshed)
            }
            return refreshed
        }

        FirebaseBootstrap.configureIfPossible()
        guard FirebaseBootstrap.isConfigured, let firebaseUser = Auth.auth().currentUser else {
            if let session = persistedSession, !session.isGuest {
                defaults.removeObject(forKey: key)
            }
            return nil
        }

        let user = buildAppleUser(from: firebaseUser, fallback: persistedSession)
        let refreshed = (try? saveProfile(for: user)) ?? user
        persistSession(refreshed)
        return refreshed
    }

    func prepareAppleSignIn(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
    }

    func handleAppleSignIn(result: Result<ASAuthorization, Error>) async throws -> UserAccount {
        FirebaseBootstrap.configureIfPossible()
        guard FirebaseBootstrap.isConfigured else {
            throw AuthError.firebaseUnavailable
        }
        defer { currentNonce = nil }

        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                throw AuthError.invalidCredential
            }
            guard let nonce = currentNonce else {
                throw AuthError.missingNonce
            }
            guard let identityToken = credential.identityToken else {
                throw AuthError.missingIdentityToken
            }
            guard let idTokenString = String(data: identityToken, encoding: .utf8) else {
                throw AuthError.invalidIdentityToken
            }

            let firebaseCredential = OAuthProvider.appleCredential(
                withIDToken: idTokenString,
                rawNonce: nonce,
                fullName: credential.fullName
            )
            let firebaseUser = try await signInToFirebase(with: firebaseCredential)
            let previousUser = persistedSession?.authMode == .apple ? persistedSession : nil
            let fullName = formattedName(from: credential.fullName)

            let user = UserAccount(
                userID: firebaseUser.uid,
                displayName: fullName ?? firebaseUser.displayName ?? previousUser?.displayName ?? "我的记录",
                email: firebaseUser.email ?? credential.email ?? previousUser?.email,
                authMode: .apple,
                createdAt: firebaseUser.creationDate?.startOfDay ?? resolveCreatedAt(for: firebaseUser.uid)
            )
            let refreshed = try saveProfile(for: user)
            persistSession(refreshed)
            return refreshed
        case .failure(let error):
            throw error
        }
    }

    func continueAsGuest() throws -> UserAccount {
        if FirebaseBootstrap.isConfigured, Auth.auth().currentUser != nil {
            try Auth.auth().signOut()
        }
        let user = UserAccount(
            userID: guestID,
            displayName: "游客模式",
            email: nil,
            authMode: .guest,
            createdAt: resolveCreatedAt(for: guestID)
        )
        let refreshed = try saveProfile(for: user)
        persistSession(refreshed)
        return refreshed
    }

    func updateDisplayName(_ name: String, for user: UserAccount) throws -> UserAccount {
        let updated = UserAccount(
            userID: user.userID,
            displayName: name,
            email: user.email,
            authMode: user.authMode,
            createdAt: user.createdAt
        )
        persistSession(updated)
        _ = try saveProfile(for: updated)
        return updated
    }

    func signOut() throws {
        if FirebaseBootstrap.isConfigured, Auth.auth().currentUser != nil {
            try Auth.auth().signOut()
        }
        defaults.removeObject(forKey: key)
    }

    enum AuthError: LocalizedError {
        case invalidCredential
        case firebaseUnavailable
        case missingNonce
        case missingIdentityToken
        case invalidIdentityToken
        case unexpectedAuthResult

        var errorDescription: String? {
            switch self {
            case .invalidCredential:
                String(localized: "Apple 登录结果不可用。")
            case .firebaseUnavailable:
                String(localized: "Firebase 还没有正确初始化。")
            case .missingNonce:
                String(localized: "登录请求已失效，请再试一次。")
            case .missingIdentityToken:
                String(localized: "Apple 没有返回可用的身份令牌。")
            case .invalidIdentityToken:
                String(localized: "Apple 身份令牌格式无效。")
            case .unexpectedAuthResult:
                String(localized: "Firebase 没有返回完整的登录结果。")
            }
        }
    }

    private var persistedSession: UserAccount? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(UserAccount.self, from: data)
    }

    private func persistSession(_ user: UserAccount) {
        if let data = try? JSONEncoder().encode(user) {
            defaults.set(data, forKey: key)
        }
    }

    private func refreshUser(_ session: UserAccount) -> UserAccount? {
        do {
            let database = try store.load()
            if let profile = database.profilesByUser[session.userID] {
                return UserAccount(
                    userID: session.userID,
                    displayName: session.displayName,
                    email: session.email,
                    authMode: session.authMode,
                    createdAt: profile.createdAt
                )
            }

            let fallbackCreatedAt = earliestKnownDate(for: session.userID, database: database) ?? session.createdAt
            var updatedDatabase = database
            updatedDatabase.profilesByUser[session.userID] = UserProfile(userID: session.userID, createdAt: fallbackCreatedAt.startOfDay)
            try store.save(updatedDatabase)
            return UserAccount(
                userID: session.userID,
                displayName: session.displayName,
                email: session.email,
                authMode: session.authMode,
                createdAt: fallbackCreatedAt.startOfDay
            )
        } catch {
            return session
        }
    }

    private func saveProfile(for user: UserAccount) throws -> UserAccount {
        var database = try store.load()
        let existingCreatedAt = database.profilesByUser[user.userID]?.createdAt
        let earliestCreatedAt = [existingCreatedAt, earliestKnownDate(for: user.userID, database: database), user.createdAt]
            .compactMap { $0 }
            .min()?
            .startOfDay ?? user.createdAt.startOfDay
        database.profilesByUser[user.userID] = UserProfile(userID: user.userID, createdAt: earliestCreatedAt)
        try store.save(database)
        return UserAccount(
            userID: user.userID,
            displayName: user.displayName,
            email: user.email,
            authMode: user.authMode,
            createdAt: earliestCreatedAt
        )
    }

    private func resolveCreatedAt(for userID: String) -> Date {
        do {
            let database = try store.load()
            if let profile = database.profilesByUser[userID] {
                return profile.createdAt.startOfDay
            }
            if let earliestRecordDate = earliestKnownDate(for: userID, database: database) {
                return earliestRecordDate.startOfDay
            }
        } catch {}

        #if DEBUG
        return Date().startOfDay.adding(days: -44)
        #else
        return Date().startOfDay
        #endif
    }

    private func earliestKnownDate(for userID: String, database: LocalJSONStore.Database) -> Date? {
        database.recordsByUser[userID]?
            .values
            .map(\.date)
            .min()
    }

    private func buildAppleUser(from firebaseUser: FirebaseAuth.User, fallback: UserAccount?) -> UserAccount {
        let user = UserAccount(
            userID: firebaseUser.uid,
            displayName: firebaseUser.displayName ?? fallback?.displayName ?? "我的记录",
            email: firebaseUser.email ?? fallback?.email,
            authMode: .apple,
            createdAt: firebaseUser.metadata.creationDate?.startOfDay ?? resolveCreatedAt(for: firebaseUser.uid)
        )
        return refreshUser(user) ?? user
    }

    private func formattedName(from components: PersonNameComponents?) -> String? {
        let parts = [components?.givenName, components?.familyName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            if status != errSecSuccess {
                fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(status)")
            }

            randoms.forEach { random in
                if remainingLength == 0 {
                    return
                }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }

        return result
    }

    private func sha256(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func signInToFirebase(with credential: OAuthCredential) async throws -> FirebaseUserSnapshot {
        try await withCheckedThrowingContinuation { continuation in
            Auth.auth().signIn(with: credential) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let result {
                    continuation.resume(returning: FirebaseUserSnapshot(
                        uid: result.user.uid,
                        displayName: result.user.displayName,
                        email: result.user.email,
                        creationDate: result.user.metadata.creationDate
                    ))
                } else {
                    continuation.resume(throwing: AuthError.unexpectedAuthResult)
                }
            }
        }
    }
}

final class LocalJSONStore {
    struct Database: Codable {
        var recordsByUser: [String: [String: DailyRecord]] = [:]
        var preferencesByUser: [String: UserPreferences] = [:]
        var profilesByUser: [String: UserProfile] = [:]

        enum CodingKeys: String, CodingKey {
            case recordsByUser
            case preferencesByUser
            case profilesByUser
        }

        init() {}

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            recordsByUser = try container.decodeIfPresent([String: [String: DailyRecord]].self, forKey: .recordsByUser) ?? [:]
            preferencesByUser = try container.decodeIfPresent([String: UserPreferences].self, forKey: .preferencesByUser) ?? [:]
            profilesByUser = try container.decodeIfPresent([String: UserProfile].self, forKey: .profilesByUser) ?? [:]
        }
    }

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(filename: String = "dailylogs-database.json") {
        let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = supportURL.appendingPathComponent("DailyLogs", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent(filename)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() throws -> Database {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return Database() }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(Database.self, from: data)
    }

    func save(_ database: Database) throws {
        let data = try encoder.encode(database)
        try data.write(to: fileURL, options: .atomic)
    }
}

final class LocalDailyRecordRepository: DailyRecordRepository {
    private let store: LocalJSONStore

    init(store: LocalJSONStore) {
        self.store = store
    }

    func loadRecord(for date: Date, preferences: UserPreferences, userID: String) throws -> DailyRecord {
        let key = date.storageKey()
        let database = try store.load()
        if let record = database.recordsByUser[userID]?[key] {
            return record
        }
        return DailyRecord.empty(for: date, preferences: preferences)
    }

    func saveRecord(_ record: DailyRecord, userID: String) throws {
        var database = try store.load()
        var records = database.recordsByUser[userID] ?? [:]
        records[record.date.storageKey()] = record
        database.recordsByUser[userID] = records
        try store.save(database)
    }

    func loadAllRecords(userID: String) throws -> [DailyRecord] {
        let database = try store.load()
        return (database.recordsByUser[userID] ?? [:]).values.sorted { $0.date < $1.date }
    }
}

final class LocalPreferencesStore: PreferencesStore {
    private let store: LocalJSONStore
    private let anonymousKey = "anonymous"

    init(store: LocalJSONStore) {
        self.store = store
    }

    func loadPreferences(userID: String?) throws -> UserPreferences {
        let database = try store.load()
        return database.preferencesByUser[userID ?? anonymousKey] ?? UserPreferences()
    }

    func savePreferences(_ preferences: UserPreferences, userID: String?) throws {
        var database = try store.load()
        database.preferencesByUser[userID ?? anonymousKey] = preferences
        try store.save(database)
    }
}

final class LocalPhotoStorageService: PhotoStorageService {
    private let directory: URL

    init() {
        let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = supportURL.appendingPathComponent("DailyLogs/Photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.directory = directory
    }

    func savePhoto(_ image: UIImage) throws -> String {
        let url = directory.appendingPathComponent("\(UUID().uuidString).jpg")
        guard let data = image.jpegData(compressionQuality: 0.82) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url, options: .atomic)
        return url.path
    }

    func deletePhoto(at path: String) throws {
        guard FileManager.default.fileExists(atPath: path) else { return }
        try FileManager.default.removeItem(atPath: path)
    }
}

final class PlaceholderHealthSyncAdapter: HealthSyncAdapter {
    func requestAuthorization() async throws {}
    func fetchSleepData(for date: Date, after registrationDate: Date) async throws -> SleepRecord? {
        nil
    }
}

final class LocationService: NSObject, ObservableObject, @unchecked Sendable {
    @Published private(set) var permissionState: LocationPermissionState = .notDetermined
    @Published private(set) var latestLocation: CLLocation?
    @Published private(set) var detectedTimeZone: TimeZone?

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    override init() {
        super.init()
        manager.delegate = self
        syncState(from: manager.authorizationStatus)
    }

    func requestAccess() {
        manager.requestWhenInUseAuthorization()
        manager.requestLocation()
    }

    private func syncState(from status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            permissionState = .authorized
        case .denied, .restricted:
            permissionState = .denied
        case .notDetermined:
            permissionState = .notDetermined
        @unknown default:
            permissionState = .notDetermined
        }
    }
}

extension LocationService: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        syncState(from: manager.authorizationStatus)
        if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        latestLocation = locations.last
        guard let location = locations.last else { return }
        geocoder.reverseGeocodeLocation(location) { placemarks, _ in
            self.detectedTimeZone = placemarks?.first?.timeZone ?? TimeZone.autoupdatingCurrent
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        // Keep the UI non-blocking when location fetch fails.
    }
}

struct AstronomySunTimesService: SunTimesService {
    func sunTimes(for date: Date, coordinate: CLLocationCoordinate2D, timeZone: TimeZone) -> SunTimes? {
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 1
        let sunriseUTC = solarTime(dayOfYear: dayOfYear, coordinate: coordinate, zenith: 90.833, isSunrise: true)
        let sunsetUTC = solarTime(dayOfYear: dayOfYear, coordinate: coordinate, zenith: 90.833, isSunrise: false)
        guard let sunriseUTC, let sunsetUTC else { return nil }

        let offset = Double(timeZone.secondsFromGMT(for: date)) / 3600.0
        let sunriseLocal = sunriseUTC + offset
        let sunsetLocal = sunsetUTC + offset

        return SunTimes(
            sunrise: localDate(for: date, hourFraction: sunriseLocal),
            sunset: localDate(for: date, hourFraction: sunsetLocal)
        )
    }

    private func solarTime(dayOfYear: Int, coordinate: CLLocationCoordinate2D, zenith: Double, isSunrise: Bool) -> Double? {
        let lngHour = coordinate.longitude / 15
        let t = Double(dayOfYear) + ((isSunrise ? 6 : 18) - lngHour) / 24
        let m = (0.9856 * t) - 3.289
        var l = m + (1.916 * sin(m.degreesToRadians)) + (0.020 * sin(2 * m.degreesToRadians)) + 282.634
        l = normalizedDegrees(l)

        var ra = atan(0.91764 * tan(l.degreesToRadians)).radiansToDegrees
        ra = normalizedDegrees(ra)

        let lQuadrant = floor(l / 90) * 90
        let raQuadrant = floor(ra / 90) * 90
        ra = (ra + (lQuadrant - raQuadrant)) / 15

        let sinDec = 0.39782 * sin(l.degreesToRadians)
        let cosDec = cos(asin(sinDec))
        let cosH = (cos(zenith.degreesToRadians) - (sinDec * sin(coordinate.latitude.degreesToRadians))) / (cosDec * cos(coordinate.latitude.degreesToRadians))
        guard (-1...1).contains(cosH) else { return nil }

        let h = (isSunrise ? 360 - acos(cosH).radiansToDegrees : acos(cosH).radiansToDegrees) / 15
        let localMeanTime = h + ra - (0.06571 * t) - 6.622
        var utc = localMeanTime - lngHour
        while utc < 0 { utc += 24 }
        while utc >= 24 { utc -= 24 }
        return utc
    }

    private func localDate(for day: Date, hourFraction: Double) -> Date {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: day)
        return dayStart.addingTimeInterval(hourFraction * 3600)
    }

    private func normalizedDegrees(_ value: Double) -> Double {
        var result = value
        while result < 0 { result += 360 }
        while result >= 360 { result -= 360 }
        return result
    }
}

private extension Double {
    var degreesToRadians: Double { self * .pi / 180 }
    var radiansToDegrees: Double { self * 180 / .pi }
}

struct AnalyticsSummary {
    var averageSleepHours: Double
    var averageBedtimeMinutes: Double?
    var averageWakeMinutes: Double?
    var defaultMealCompletionRate: Double
    var averageShowers: Double
    var averageLightSleepHours: Double?
    var averageDeepSleepHours: Double?
    var averageREMSleepHours: Double?
    var days: [AnalyticsDayPoint]
    var mealSeries: [MealAnalyticsSeries]
    var showerPoints: [AnalyticsScatterPoint]
}

enum AnalyticsCalculator {
    static func build(
        records: [DailyRecord],
        range: AnalyticsRange,
        customRange: ClosedRange<Date>? = nil,
        defaultMealSlots: [MealSlot] = MealSlot.defaults
    ) -> AnalyticsSummary {
        let calendar = Calendar.current
        // Exclude today from analytics — incomplete day skews averages
        let endDate = calendar.startOfDay(for: .now).adding(days: -1)
        let bounds: ClosedRange<Date> = {
            if range == .custom, let customRange {
                let lower = customRange.lowerBound.startOfDay
                let upper = min(customRange.upperBound.startOfDay, endDate)
                return lower...upper
            }
            let cutoff = endDate.adding(days: -(range.dayCount - 1))
            return cutoff...endDate
        }()
        let filtered = records.filter { $0.date >= bounds.lowerBound && $0.date <= bounds.upperBound }
        let recordMap = Dictionary(uniqueKeysWithValues: filtered.map { ($0.date.startOfDay, $0) })
        let daySpan = Calendar.current.dateComponents([.day], from: bounds.lowerBound, to: bounds.upperBound).day ?? 0
        let totalDays = max(1, daySpan + 1)
        let days = stride(from: 0, through: totalDays - 1, by: 1).map { offset -> AnalyticsDayPoint in
            let date = bounds.lowerBound.adding(days: offset)
            guard let record = recordMap[date] else {
                return AnalyticsDayPoint(
                    date: date,
                    sleepHours: nil,
                    bedtimeMinutes: nil,
                    wakeMinutes: nil,
                    sleepStartMinutes: nil,
                    sleepEndMinutes: nil,
                    loggedMeals: 0,
                    trackedMeals: 0,
                    showers: 0
                )
            }

            let loggedMeals = record.meals.filter { $0.effectiveStatus(on: record.date) == .logged }.count
            let sleepStartMinutes = record.sleepRecord.bedtimePreviousNight.map(chartMinutes)
            let sleepEndMinutes = record.sleepRecord.wakeTimeCurrentDay.map(chartMinutes)

            let stageDurations = record.sleepRecord.hasStageData ? record.sleepRecord.stageDurations : [:]

            return AnalyticsDayPoint(
                date: date,
                sleepHours: record.sleepRecord.duration.map { $0 / 3600 },
                bedtimeMinutes: record.sleepRecord.bedtimePreviousNight.map(clockMinutes),
                wakeMinutes: record.sleepRecord.wakeTimeCurrentDay.map(clockMinutes),
                sleepStartMinutes: sleepStartMinutes,
                sleepEndMinutes: sleepEndMinutes,
                loggedMeals: loggedMeals,
                trackedMeals: record.meals.count,
                showers: record.showers.count,
                lightSleepHours: stageDurations[.light].map { $0 / 3600 },
                deepSleepHours: stageDurations[.deep].map { $0 / 3600 },
                remSleepHours: stageDurations[.rem].map { $0 / 3600 },
                awakeSleepHours: stageDurations[.awake].map { $0 / 3600 }
            )
        }

        let averageSleepHours = days.compactMap(\.sleepHours).averageOptional ?? 0
        let averageBedtimeMinutes = days.compactMap(\.bedtimeMinutes).averageOptional
        let averageWakeMinutes = days.compactMap(\.wakeMinutes).averageOptional
        let averageShowers = days.map { Double($0.showers) }.average

        let defaultMealEntries = filtered.flatMap { record in
            record.meals.filter { [.breakfast, .lunch, .dinner].contains($0.mealKind) }.map { (record, $0) }
        }
        let defaultTrackedMeals = Double(defaultMealEntries.count)
        let defaultLoggedMeals = Double(defaultMealEntries.filter { pair in
            pair.1.effectiveStatus(on: pair.0.date) == .logged
        }.count)
        let defaultMealCompletionRate = defaultTrackedMeals > 0 ? defaultLoggedMeals / defaultTrackedMeals : 0

        let groupedMeals = Dictionary(grouping: filtered.flatMap { record in
            record.meals.map { (record, $0) }
        }, by: { $0.1.slotKey })

        let defaultMealKeys = Set(defaultMealSlots.map { slot in
            switch slot.kind {
            case .custom:
                return "custom-\(slot.title)"
            default:
                return slot.kind.rawValue
            }
        })

        let mealSeries = groupedMeals.values
            .compactMap { entries -> MealAnalyticsSeries? in
                guard let sample = entries.first?.1 else { return nil }
                let points = entries.compactMap { record, meal -> AnalyticsScatterPoint? in
                    guard meal.effectiveStatus(on: record.date) == .logged, let time = meal.time else { return nil }
                    return AnalyticsScatterPoint(
                        id: "\(record.date.storageKey())-\(meal.slotKey)",
                        date: record.date,
                        minutes: clockMinutes(time)
                    )
                }
                let tracked = Double(entries.count)
                let logged = Double(points.count)
                return MealAnalyticsSeries(
                    key: sample.slotKey,
                    title: sample.displayTitle,
                    showsAverage: defaultMealKeys.contains(sample.slotKey),
                    completionRate: tracked > 0 ? logged / tracked : 0,
                    averageMinutes: points.map(\.minutes).averageOptional,
                    points: points.sorted { $0.date < $1.date }
                )
            }
            .sorted { lhs, rhs in
                mealSortRank(for: lhs.key, title: lhs.title) < mealSortRank(for: rhs.key, title: rhs.title)
            }

        let showerPoints = filtered.flatMap { record in
            record.showers.enumerated().map { index, shower in
                AnalyticsScatterPoint(
                    id: "\(record.date.storageKey())-shower-\(index)",
                    date: record.date,
                    minutes: clockMinutes(shower.time)
                )
            }
        }

        let averageLightSleepHours = days.compactMap(\.lightSleepHours).averageOptional
        let averageDeepSleepHours = days.compactMap(\.deepSleepHours).averageOptional
        let averageREMSleepHours = days.compactMap(\.remSleepHours).averageOptional

        return AnalyticsSummary(
            averageSleepHours: averageSleepHours,
            averageBedtimeMinutes: averageBedtimeMinutes,
            averageWakeMinutes: averageWakeMinutes,
            defaultMealCompletionRate: defaultMealCompletionRate,
            averageShowers: averageShowers,
            averageLightSleepHours: averageLightSleepHours,
            averageDeepSleepHours: averageDeepSleepHours,
            averageREMSleepHours: averageREMSleepHours,
            days: days,
            mealSeries: mealSeries,
            showerPoints: showerPoints
        )
    }

    private static func clockMinutes(_ date: Date) -> Double {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return Double((components.hour ?? 0) * 60 + (components.minute ?? 0))
    }

    private static func chartMinutes(_ date: Date) -> Double {
        let minutes = clockMinutes(date)
        return minutes < 18 * 60 ? minutes + 24 * 60 : minutes
    }

    private static func mealSortRank(for key: String, title: String) -> String {
        if key == MealKind.breakfast.rawValue { return "0-\(title)" }
        if key == MealKind.lunch.rawValue { return "1-\(title)" }
        if key == MealKind.dinner.rawValue { return "2-\(title)" }
        return "3-\(title)"
    }
}

private extension Array where Element == Double {
    var average: Double {
        guard !isEmpty else { return 0 }
        return reduce(0, +) / Double(count)
    }

    var averageOptional: Double? {
        guard !isEmpty else { return nil }
        return average
    }
}

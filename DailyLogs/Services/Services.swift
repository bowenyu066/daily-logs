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
    func saveRecord(_ record: DailyRecord, preferences: UserPreferences, userID: String) throws
    func loadAllRecords(userID: String, preferences: UserPreferences) throws -> [DailyRecord]
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

protocol WeatherService: Sendable {
    func weather(at coordinate: CLLocationCoordinate2D) async throws -> WeatherSnapshot?
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
                let refreshed = refreshUser(session) ?? session
                persistSession(refreshed)
                return refreshed
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
            let storedProfile = storedProfile(for: firebaseUser.uid)

            let user = UserAccount(
                userID: firebaseUser.uid,
                displayName: fullName
                    ?? firebaseUser.displayName
                    ?? previousUser?.displayName
                    ?? storedProfile?.displayName
                    ?? defaultDisplayName(for: .apple),
                email: firebaseUser.email
                    ?? credential.email
                    ?? previousUser?.email
                    ?? storedProfile?.email,
                authMode: .apple,
                createdAt: firebaseUser.creationDate?.startOfDay
                    ?? storedProfile?.createdAt.startOfDay
                    ?? resolveCreatedAt(for: firebaseUser.uid)
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
            displayName: NSLocalizedString("游客模式", comment: ""),
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
                NSLocalizedString("Apple 登录结果不可用。", comment: "")
            case .firebaseUnavailable:
                NSLocalizedString("Firebase 还没有正确初始化。", comment: "")
            case .missingNonce:
                NSLocalizedString("登录请求已失效，请再试一次。", comment: "")
            case .missingIdentityToken:
                NSLocalizedString("Apple 没有返回可用的身份令牌。", comment: "")
            case .invalidIdentityToken:
                NSLocalizedString("Apple 身份令牌格式无效。", comment: "")
            case .unexpectedAuthResult:
                NSLocalizedString("Firebase 没有返回完整的登录结果。", comment: "")
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
            var database = try store.load()
            if let profile = database.profilesByUser[session.userID] {
                let authoritativeCreatedAt = max(profile.createdAt.startOfDay, session.createdAt.startOfDay)
                if profile.createdAt.startOfDay != authoritativeCreatedAt {
                    var updatedProfile = profile
                    updatedProfile.createdAt = authoritativeCreatedAt
                    database.profilesByUser[session.userID] = updatedProfile
                    try store.save(database)
                }
                return UserAccount(
                    userID: session.userID,
                    displayName: resolvedDisplayName(for: session, profile: profile),
                    email: profile.email ?? session.email,
                    authMode: profile.authMode ?? session.authMode,
                    createdAt: authoritativeCreatedAt
                )
            }

            let authoritativeCreatedAt = session.createdAt.startOfDay
            database.profilesByUser[session.userID] = UserProfile(
                userID: session.userID,
                displayName: session.displayName,
                email: session.email,
                authMode: session.authMode,
                createdAt: authoritativeCreatedAt
            )
            try store.save(database)
            return UserAccount(
                userID: session.userID,
                displayName: session.displayName,
                email: session.email,
                authMode: session.authMode,
                createdAt: authoritativeCreatedAt
            )
        } catch {
            return session
        }
    }

    private func saveProfile(for user: UserAccount) throws -> UserAccount {
        var database = try store.load()
        let existingProfile = database.profilesByUser[user.userID]
        let authoritativeCreatedAt = max(existingProfile?.createdAt.startOfDay ?? user.createdAt.startOfDay, user.createdAt.startOfDay)
        let mergedDisplayName = resolvedDisplayName(for: user, profile: existingProfile)
        database.profilesByUser[user.userID] = UserProfile(
            userID: user.userID,
            displayName: mergedDisplayName,
            email: user.email ?? existingProfile?.email,
            authMode: user.authMode,
            createdAt: authoritativeCreatedAt
        )
        try store.save(database)
        return UserAccount(
            userID: user.userID,
            displayName: mergedDisplayName,
            email: user.email ?? existingProfile?.email,
            authMode: user.authMode,
            createdAt: authoritativeCreatedAt
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
            .keys
            .compactMap { Date.fromStorageKey($0) }
            .min()
    }

    private func buildAppleUser(from firebaseUser: FirebaseAuth.User, fallback: UserAccount?) -> UserAccount {
        let profile = storedProfile(for: firebaseUser.uid)
        let user = UserAccount(
            userID: firebaseUser.uid,
            displayName: firebaseUser.displayName
                ?? fallback?.displayName
                ?? profile?.displayName
                ?? defaultDisplayName(for: .apple),
            email: firebaseUser.email ?? fallback?.email ?? profile?.email,
            authMode: .apple,
            createdAt: firebaseUser.metadata.creationDate?.startOfDay
                ?? profile?.createdAt.startOfDay
                ?? resolveCreatedAt(for: firebaseUser.uid)
        )
        return refreshUser(user) ?? user
    }

    private func storedProfile(for userID: String) -> UserProfile? {
        try? store.load().profilesByUser[userID]
    }

    private func resolvedDisplayName(for user: UserAccount, profile: UserProfile?) -> String {
        let candidate = user.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !candidate.isEmpty, !isDefaultDisplayName(candidate, for: user.authMode) {
            return candidate
        }

        let storedName = profile?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !storedName.isEmpty {
            return storedName
        }

        if !candidate.isEmpty {
            return candidate
        }

        return defaultDisplayName(for: user.authMode)
    }

    private func defaultDisplayName(for authMode: AuthMode) -> String {
        switch authMode {
        case .apple:
            NSLocalizedString("我的记录", comment: "")
        case .guest:
            NSLocalizedString("游客模式", comment: "")
        }
    }

    private func isDefaultDisplayName(_ displayName: String, for authMode: AuthMode) -> Bool {
        switch authMode {
        case .apple:
            return [
                defaultDisplayName(for: .apple),
                "我的记录",
                "My Log"
            ].contains(displayName)
        case .guest:
            return [
                defaultDisplayName(for: .guest),
                "游客模式",
                "Guest Mode"
            ].contains(displayName)
        }
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
        var database = try store.load()
        let canonicalRecords = canonicalizedRecordMap(database.recordsByUser[userID] ?? [:], preferences: preferences)
        if canonicalRecords != (database.recordsByUser[userID] ?? [:]) {
            database.recordsByUser[userID] = canonicalRecords
            try store.save(database)
        }
        if let record = canonicalRecords[key] {
            return record
        }
        return DailyRecord.empty(for: date, preferences: preferences)
    }

    func saveRecord(_ record: DailyRecord, preferences: UserPreferences, userID: String) throws {
        var database = try store.load()
        var records = canonicalizedRecordMap(database.recordsByUser[userID] ?? [:], preferences: preferences)
        let key = record.canonicalStorageKey(using: preferences, fallback: record.date.storageKey())
        records[key] = record.anchoredToStorageKey(key)
        database.recordsByUser[userID] = canonicalizedRecordMap(records, preferences: preferences)
        try store.save(database)
    }

    func loadAllRecords(userID: String, preferences: UserPreferences) throws -> [DailyRecord] {
        var database = try store.load()
        let canonicalRecords = canonicalizedRecordMap(database.recordsByUser[userID] ?? [:], preferences: preferences)
        if canonicalRecords != (database.recordsByUser[userID] ?? [:]) {
            database.recordsByUser[userID] = canonicalRecords
            try store.save(database)
        }
        return canonicalRecords.values.sorted { $0.date < $1.date }
    }

    private func canonicalizedRecordMap(_ records: [String: DailyRecord], preferences: UserPreferences) -> [String: DailyRecord] {
        records.reduce(into: [:]) { partialResult, entry in
            let canonicalKey = entry.value.canonicalStorageKey(using: preferences, fallback: entry.key)
            let anchored = entry.value.anchoredToStorageKey(canonicalKey)
            if let existing = partialResult[canonicalKey] {
                partialResult[canonicalKey] = preferredRecord(between: existing, and: anchored)
            } else {
                partialResult[canonicalKey] = anchored
            }
        }
    }

    private func preferredRecord(between lhs: DailyRecord, and rhs: DailyRecord) -> DailyRecord {
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

    private func completenessScore(for record: DailyRecord) -> Int {
        var score = 0
        if record.sleepRecord.bedtimePreviousNight != nil { score += 2 }
        if record.sleepRecord.wakeTimeCurrentDay != nil { score += 2 }
        score += record.sleepRecord.stageIntervals.count * 2
        score += record.showers.count
        score += record.bowelMovements.count
        score += record.sexualActivities.count

        for meal in record.meals {
            switch meal.status {
            case .logged: score += 2
            case .skipped: score += 1
            case .empty: break
            }
            if meal.time != nil { score += 1 }
            if meal.hasPhoto { score += 1 }
        }

        if record.aiInsightNarrative?.hasAIScoring == true { score += 2 }
        if record.locationName?.isEmpty == false { score += 1 }
        if record.sunTimes != nil { score += 1 }
        if record.weatherSnapshot != nil { score += 1 }
        return score
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

struct OpenMeteoWeatherService: WeatherService {
    func weather(at coordinate: CLLocationCoordinate2D) async throws -> WeatherSnapshot? {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(coordinate.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        guard let url = components?.url else { return nil }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            return nil
        }

        let payload = try JSONDecoder().decode(OpenMeteoCurrentWeatherResponse.self, from: data)
        guard let current = payload.current,
              let low = payload.daily?.temperature2mMin.first,
              let high = payload.daily?.temperature2mMax.first else { return nil }
        return WeatherSnapshot(
            conditionDescription: current.conditionDescription,
            symbolName: current.symbolName,
            temperatureCelsius: current.temperature2m,
            lowTemperatureCelsius: low,
            highTemperatureCelsius: high
        )
    }
}

private struct OpenMeteoCurrentWeatherResponse: Decodable {
    struct Current: Decodable {
        let temperature2m: Double
        let weatherCode: Int

        enum CodingKeys: String, CodingKey {
            case temperature2m = "temperature_2m"
            case weatherCode = "weather_code"
        }

        var conditionDescription: String {
            switch weatherCode {
            case 0: "晴朗"
            case 1: "大部晴朗"
            case 2: "局部多云"
            case 3: "阴"
            case 45, 48: "有雾"
            case 51, 53, 55: "毛毛雨"
            case 56, 57: "冻毛毛雨"
            case 61, 63, 65: "下雨"
            case 66, 67: "冻雨"
            case 71, 73, 75, 77: "下雪"
            case 80, 81, 82: "阵雨"
            case 85, 86: "阵雪"
            case 95: "雷暴"
            case 96, 99: "强雷暴"
            default: "天气"
            }
        }

        var symbolName: String {
            switch weatherCode {
            case 0: "sun.max.fill"
            case 1: "sun.max"
            case 2: "cloud.sun"
            case 3: "cloud.fill"
            case 45, 48: "cloud.fog.fill"
            case 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82: "cloud.rain.fill"
            case 71, 73, 75, 77, 85, 86: "cloud.snow.fill"
            case 95, 96, 99: "cloud.bolt.rain.fill"
            default: "cloud.sun.fill"
            }
        }
    }

    struct Daily: Decodable {
        let temperature2mMax: [Double]
        let temperature2mMin: [Double]

        enum CodingKeys: String, CodingKey {
            case temperature2mMax = "temperature_2m_max"
            case temperature2mMin = "temperature_2m_min"
        }
    }

    let current: Current?
    let daily: Daily?
}

final class LocationService: NSObject, ObservableObject, @unchecked Sendable {
    @Published private(set) var permissionState: LocationPermissionState = .notDetermined
    @Published private(set) var latestLocation: CLLocation?
    @Published private(set) var detectedTimeZone: TimeZone?
    @Published private(set) var detectedLocationName: String?

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

    func refreshCurrentLocation() {
        guard permissionState == .authorized else { return }
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
            let placemark = placemarks?.first
            self.detectedTimeZone = placemark?.timeZone ?? TimeZone.autoupdatingCurrent
            self.detectedLocationName = self.formattedLocationName(from: placemark)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        // Keep the UI non-blocking when location fetch fails.
    }

    private func formattedLocationName(from placemark: CLPlacemark?) -> String? {
        guard let placemark else { return nil }
        let candidates = [
            placemark.locality,
            placemark.name,
            placemark.subLocality,
            placemark.administrativeArea
        ]
        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
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
            sunset: localDate(for: date, hourFraction: sunsetLocal),
            timeZoneIdentifier: timeZone.identifier
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
    var averageSleepHours: Double?
    var averageBedtimeMinutes: Double?
    var averageWakeMinutes: Double?
    var previousAverageSleepHours: Double?
    var previousAverageBedtimeMinutes: Double?
    var previousAverageWakeMinutes: Double?
    var defaultMealCompletionRate: Double?
    var averageShowers: Double?
    var averageLightSleepHours: Double?
    var averageDeepSleepHours: Double?
    var averageREMSleepHours: Double?
    var previousAverageLightSleepHours: Double?
    var previousAverageDeepSleepHours: Double?
    var previousAverageREMSleepHours: Double?
    var averageShowerMinutes: Double?
    var averageBowelMovements: Double?
    var averageBowelMovementMinutes: Double?
    var averageSexualActivity: Double?
    var days: [AnalyticsDayPoint]
    var mealSeries: [MealAnalyticsSeries]
    var showerPoints: [AnalyticsScatterPoint]
    var bowelMovementPoints: [AnalyticsScatterPoint]
    var sexualActivityWeeklyData: [SexualActivityWeekPoint]
}

enum AnalyticsCalculator {
    static func visibleDateBounds(
        range: AnalyticsRange,
        customRange: ClosedRange<Date>? = nil,
        today: Date = .now,
        calendar: Calendar = .current
    ) -> ClosedRange<Date> {
        let clampedToday = calendar.startOfDay(for: today)
        if range == .custom, let customRange {
            let lower = calendar.startOfDay(for: customRange.lowerBound)
            let upper = min(calendar.startOfDay(for: customRange.upperBound), clampedToday)
            return lower...upper
        }
        let endDate = clampedToday.adding(days: -1)
        let lower = endDate.adding(days: -(range.dayCount - 1))
        return lower...endDate
    }

    static func build(
        records: [DailyRecord],
        range: AnalyticsRange,
        customRange: ClosedRange<Date>? = nil,
        defaultMealSlots: [MealSlot] = MealSlot.defaults,
        today: Date = .now
    ) -> AnalyticsSummary {
        let calendar = Calendar.current
        let resolvedToday = calendar.startOfDay(for: today)
        let chartBounds = visibleDateBounds(
            range: range,
            customRange: customRange,
            today: resolvedToday,
            calendar: calendar
        )
        let visibleDays = dateRange(in: chartBounds, calendar: calendar)
        let totalDays = max(1, visibleDays.count)
        let chartDayMap = aggregateDayPoints(from: records, within: chartBounds, calendar: calendar)
        let days = visibleDays.map { chartDayMap[$0] ?? emptyDayPoint(for: $0) }

        let comparisonUpperBound = chartBounds.lowerBound.adding(days: -1)
        let comparisonLowerBound = comparisonUpperBound.adding(days: -(totalDays - 1))
        let comparisonBounds: ClosedRange<Date>? = comparisonUpperBound >= availableLowerBound(
            for: records,
            fallback: chartBounds.lowerBound
        ) ? comparisonLowerBound...comparisonUpperBound : nil

        let currentDays = days
        let comparisonDays: [AnalyticsDayPoint] = comparisonBounds.map { bounds in
            let comparisonMap = aggregateDayPoints(from: records, within: bounds, calendar: calendar)
            return dateRange(in: bounds, calendar: calendar).map { comparisonMap[$0] ?? emptyDayPoint(for: $0) }
        } ?? []
        let averageSleepHours = currentDays.compactMap(\.sleepHours).averageOptional
        let averageBedtimeMinutes = averageBedtimeClockMinutes(currentDays.compactMap(\.bedtimeMinutes))
        let averageWakeMinutes = currentDays.compactMap(\.wakeMinutes).averageOptional
        let previousAverageSleepHours = comparisonDays.compactMap(\.sleepHours).averageOptional
        let previousAverageBedtimeMinutes = averageBedtimeClockMinutes(comparisonDays.compactMap(\.bedtimeMinutes))
        let previousAverageWakeMinutes = comparisonDays.compactMap(\.wakeMinutes).averageOptional

        let showerDays = historicalDayPointsStartingAtFirstMatch(in: currentDays) { $0.showers > 0 }
        let averageShowers = showerDays.map { Double($0.showers) }.averageOptional

        let defaultMealKeys = Set(defaultMealSlots.map { slot in
            switch slot.kind {
            case .custom:
                return "custom-\(slot.title)"
            default:
                return slot.kind.rawValue
            }
        })

        let mealSamples = records.flatMap { record in
            record.meals.compactMap { meal -> (slotKey: String, title: String, date: Date, isLogged: Bool, minutes: Double?, id: String)? in
                let anchorDate = meal.time.map {
                    actualDisplayDate(for: $0, timeZoneIdentifier: meal.timeZoneIdentifier)
                } ?? record.date.startOfDay
                guard chartBounds.contains(anchorDate) else { return nil }
                return (
                    slotKey: meal.slotKey,
                    title: meal.displayTitle,
                    date: anchorDate,
                    isLogged: meal.effectiveStatus(on: record.date) == .logged,
                    minutes: meal.time.map { clockMinutes($0, timeZoneIdentifier: meal.timeZoneIdentifier) },
                    id: "\(anchorDate.storageKey())-\(meal.slotKey)-\(meal.id.uuidString)"
                )
            }
        }
        let defaultMealSamples = mealSamples.filter { defaultMealKeys.contains($0.slotKey) }
        let defaultTrackedMeals = Double(defaultMealSamples.count)
        let defaultLoggedMeals = Double(defaultMealSamples.filter(\.isLogged).count)
        let defaultMealCompletionRate = defaultTrackedMeals > 0 ? defaultLoggedMeals / defaultTrackedMeals : nil

        let mealSeries = Dictionary(grouping: mealSamples, by: \.slotKey).values
            .compactMap { entries -> MealAnalyticsSeries? in
                guard let sample = entries.first else { return nil }
                let chartPoints = entries.compactMap { entry -> AnalyticsScatterPoint? in
                    guard entry.isLogged, let minutes = entry.minutes else { return nil }
                    return AnalyticsScatterPoint(
                        id: entry.id,
                        date: entry.date,
                        minutes: minutes
                    )
                }
                let tracked = Double(entries.count)
                let logged = Double(entries.filter(\.isLogged).count)
                return MealAnalyticsSeries(
                    key: sample.slotKey,
                    title: sample.title,
                    showsAverage: defaultMealKeys.contains(sample.slotKey),
                    completionRate: tracked > 0 ? logged / tracked : 0,
                    averageMinutes: chartPoints.map(\.minutes).averageOptional,
                    points: chartPoints.sorted { $0.date < $1.date }
                )
            }
            .sorted { lhs, rhs in
                mealSortRank(for: lhs.key, title: lhs.title) < mealSortRank(for: rhs.key, title: rhs.title)
            }

        let showerPoints = records.flatMap { record in
            record.showers.enumerated().compactMap { index, shower -> AnalyticsScatterPoint? in
                guard let time = shower.time else { return nil }
                let anchorDate = actualDisplayDate(for: time, timeZoneIdentifier: shower.timeZoneIdentifier)
                guard chartBounds.contains(anchorDate) else { return nil }
                return AnalyticsScatterPoint(
                    id: "\(anchorDate.storageKey())-shower-\(record.date.storageKey())-\(index)",
                    date: anchorDate,
                    minutes: clockMinutes(time, timeZoneIdentifier: shower.timeZoneIdentifier)
                )
            }
        }
        let averageShowerMinutes = showerPoints
            .filter { point in
                guard let firstShowerDay = showerDays.first?.date else { return false }
                return point.date >= firstShowerDay
            }
            .map(\.minutes)
            .averageOptional

        let averageLightSleepHours = currentDays.compactMap(\.lightSleepHours).averageOptional
        let averageDeepSleepHours = currentDays.compactMap(\.deepSleepHours).averageOptional
        let averageREMSleepHours = currentDays.compactMap(\.remSleepHours).averageOptional
        let previousAverageLightSleepHours = comparisonDays.compactMap(\.lightSleepHours).averageOptional
        let previousAverageDeepSleepHours = comparisonDays.compactMap(\.deepSleepHours).averageOptional
        let previousAverageREMSleepHours = comparisonDays.compactMap(\.remSleepHours).averageOptional

        let bowelMovementPoints = records.flatMap { record in
            record.bowelMovements.enumerated().compactMap { index, entry -> AnalyticsScatterPoint? in
                guard let time = entry.time else { return nil }
                let anchorDate = actualDisplayDate(for: time, timeZoneIdentifier: entry.timeZoneIdentifier)
                guard chartBounds.contains(anchorDate) else { return nil }
                return AnalyticsScatterPoint(
                    id: "\(anchorDate.storageKey())-bm-\(record.date.storageKey())-\(index)",
                    date: anchorDate,
                    minutes: clockMinutes(time, timeZoneIdentifier: entry.timeZoneIdentifier)
                )
            }
        }
        let bowelMovementDays = historicalDayPointsStartingAtFirstMatch(in: currentDays) { $0.bowelMovements > 0 }
        let averageBowelMovements = bowelMovementDays.map { Double($0.bowelMovements) }.averageOptional
        let averageBowelMovementMinutes = bowelMovementPoints
            .filter { point in
                guard let firstBowelDay = bowelMovementDays.first?.date else { return false }
                return point.date >= firstBowelDay
            }
            .map(\.minutes)
            .averageOptional

        let sexualActivitySamples = records.flatMap { record in
            record.sexualActivities.compactMap { entry -> (date: Date, isMasturbation: Bool)? in
                let anchorDate = entry.time.map {
                    actualDisplayDate(for: $0, timeZoneIdentifier: entry.timeZoneIdentifier)
                } ?? entry.date.startOfDay
                guard chartBounds.contains(anchorDate) else { return nil }
                return (date: anchorDate, isMasturbation: entry.isMasturbation)
            }
        }
        let isoCalendar: Calendar = {
            var cal = Calendar(identifier: .iso8601)
            cal.firstWeekday = 2
            return cal
        }()
        let groupedByWeek = Dictionary(grouping: sexualActivitySamples) { pair in
            isoCalendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: pair.date)
        }
        let sexualActivityWeeklyData: [SexualActivityWeekPoint] = groupedByWeek.compactMap { key, entries in
            guard let weekStart = isoCalendar.date(from: key) else { return nil }
            let masturbationCount = entries.filter(\.isMasturbation).count
            let formatter = DateFormatter()
            formatter.dateFormat = "M/d"
            return SexualActivityWeekPoint(
                weekLabel: formatter.string(from: weekStart),
                weekStart: weekStart,
                partnerCount: entries.count - masturbationCount,
                masturbationCount: masturbationCount
            )
        }.sorted { $0.weekStart < $1.weekStart }

        let sexualActivityDays = historicalDayPointsStartingAtFirstMatch(in: currentDays) { $0.sexualActivities > 0 }
        let historicalSexualActivityDates = sexualActivitySamples
            .filter { sample in
                guard let firstSexDay = sexualActivityDays.first?.date else { return false }
                return sample.date >= firstSexDay
            }
            .map(\.date)
        let averageSexualActivity: Double? = averageSexualActivityPerWeek(
            activityDates: historicalSexualActivityDates,
            upperBound: chartBounds.upperBound,
            calendar: isoCalendar
        )

        return AnalyticsSummary(
            averageSleepHours: averageSleepHours,
            averageBedtimeMinutes: averageBedtimeMinutes,
            averageWakeMinutes: averageWakeMinutes,
            previousAverageSleepHours: previousAverageSleepHours,
            previousAverageBedtimeMinutes: previousAverageBedtimeMinutes,
            previousAverageWakeMinutes: previousAverageWakeMinutes,
            defaultMealCompletionRate: defaultMealCompletionRate,
            averageShowers: averageShowers,
            averageLightSleepHours: averageLightSleepHours,
            averageDeepSleepHours: averageDeepSleepHours,
            averageREMSleepHours: averageREMSleepHours,
            previousAverageLightSleepHours: previousAverageLightSleepHours,
            previousAverageDeepSleepHours: previousAverageDeepSleepHours,
            previousAverageREMSleepHours: previousAverageREMSleepHours,
            averageShowerMinutes: averageShowerMinutes,
            averageBowelMovements: averageBowelMovements,
            averageBowelMovementMinutes: averageBowelMovementMinutes,
            averageSexualActivity: averageSexualActivity,
            days: days,
            mealSeries: mealSeries,
            showerPoints: showerPoints,
            bowelMovementPoints: bowelMovementPoints,
            sexualActivityWeeklyData: sexualActivityWeeklyData
        )
    }

    private static func clockMinutes(_ date: Date, timeZoneIdentifier: String? = nil) -> Double {
        var calendar = Calendar.current
        if let timeZoneIdentifier, let timeZone = TimeZone(identifier: timeZoneIdentifier) {
            calendar.timeZone = timeZone
        }
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return Double((components.hour ?? 0) * 60 + (components.minute ?? 0))
    }

    private static func chartMinutes(_ date: Date, timeZoneIdentifier: String? = nil) -> Double {
        let minutes = clockMinutes(date, timeZoneIdentifier: timeZoneIdentifier)
        return minutes < 18 * 60 ? minutes + 24 * 60 : minutes
    }

    private static func averageBedtimeClockMinutes(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let averaged = values.map(signedBedtimeMinutes).average
        return normalizedClockMinutes(averaged)
    }

    private static func signedBedtimeMinutes(_ minutes: Double) -> Double {
        minutes >= 12 * 60 ? minutes - 24 * 60 : minutes
    }

    private static func normalizedClockMinutes(_ minutes: Double) -> Double {
        let fullDay = 24.0 * 60.0
        var normalized = minutes.truncatingRemainder(dividingBy: fullDay)
        if normalized < 0 {
            normalized += fullDay
        }
        return normalized
    }

    private static func actualDisplayDate(for timestamp: Date, timeZoneIdentifier: String? = nil) -> Date {
        var calendar = Calendar.current
        if let timeZoneIdentifier, let timeZone = TimeZone(identifier: timeZoneIdentifier) {
            calendar.timeZone = timeZone
        }
        return calendar.startOfDay(for: timestamp)
    }

    private static func dateRange(in bounds: ClosedRange<Date>, calendar: Calendar = .current) -> [Date] {
        let daySpan = calendar.dateComponents([.day], from: bounds.lowerBound, to: bounds.upperBound).day ?? 0
        return stride(from: 0, through: max(0, daySpan), by: 1).map { offset in
            bounds.lowerBound.adding(days: offset, calendar: calendar)
        }
    }

    private static func emptyDayPoint(for date: Date) -> AnalyticsDayPoint {
        AnalyticsDayPoint(
            date: date,
            sleepHours: nil,
            bedtimeMinutes: nil,
            wakeMinutes: nil,
            sleepStartMinutes: nil,
            sleepEndMinutes: nil,
            loggedMeals: 0,
            trackedMeals: 0,
            showers: 0,
            bowelMovements: 0,
            sexualActivities: 0,
            sexualActivitiesMasturbation: 0
        )
    }

    private static func aggregateDayPoints(
        from records: [DailyRecord],
        within bounds: ClosedRange<Date>,
        calendar: Calendar = .current
    ) -> [Date: AnalyticsDayPoint] {
        var points = Dictionary(uniqueKeysWithValues: dateRange(in: bounds, calendar: calendar).map { ($0, emptyDayPoint(for: $0)) })

        for record in records {
            let logicalDate = record.date.startOfDay

            if let bedtime = record.sleepRecord.bedtimePreviousNight {
                let anchorDate = actualDisplayDate(for: bedtime, timeZoneIdentifier: record.sleepRecord.timeZoneIdentifier)
                if var point = points[anchorDate] {
                    point.bedtimeMinutes = clockMinutes(bedtime, timeZoneIdentifier: record.sleepRecord.timeZoneIdentifier)
                    points[anchorDate] = point
                }
            }

            let sleepAnchorDate = record.sleepRecord.wakeTimeCurrentDay.map {
                actualDisplayDate(for: $0, timeZoneIdentifier: record.sleepRecord.timeZoneIdentifier)
            } ?? logicalDate
            if var point = points[sleepAnchorDate] {
                let stageDurations = record.sleepRecord.hasStageData ? record.sleepRecord.stageDurations : [:]
                point.sleepHours = record.sleepRecord.duration.map { $0 / 3600 }
                point.wakeMinutes = record.sleepRecord.wakeTimeCurrentDay.map {
                    clockMinutes($0, timeZoneIdentifier: record.sleepRecord.timeZoneIdentifier)
                }
                point.sleepStartMinutes = record.sleepRecord.bedtimePreviousNight.map {
                    chartMinutes($0, timeZoneIdentifier: record.sleepRecord.timeZoneIdentifier)
                }
                point.sleepEndMinutes = record.sleepRecord.wakeTimeCurrentDay.map {
                    chartMinutes($0, timeZoneIdentifier: record.sleepRecord.timeZoneIdentifier)
                }
                point.lightSleepHours = stageDurations[.light].map { $0 / 3600 }
                point.deepSleepHours = stageDurations[.deep].map { $0 / 3600 }
                point.remSleepHours = stageDurations[.rem].map { $0 / 3600 }
                point.awakeSleepHours = stageDurations[.awake].map { $0 / 3600 }
                points[sleepAnchorDate] = point
            }

            for meal in record.meals {
                let anchorDate = meal.time.map {
                    actualDisplayDate(for: $0, timeZoneIdentifier: meal.timeZoneIdentifier)
                } ?? logicalDate
                guard var point = points[anchorDate] else { continue }
                point.trackedMeals += 1
                if meal.effectiveStatus(on: record.date) == .logged {
                    point.loggedMeals += 1
                }
                points[anchorDate] = point
            }

            for shower in record.showers {
                let anchorDate = shower.time.map {
                    actualDisplayDate(for: $0, timeZoneIdentifier: shower.timeZoneIdentifier)
                } ?? logicalDate
                guard var point = points[anchorDate] else { continue }
                point.showers += 1
                points[anchorDate] = point
            }

            for bowelMovement in record.bowelMovements {
                let anchorDate = bowelMovement.time.map {
                    actualDisplayDate(for: $0, timeZoneIdentifier: bowelMovement.timeZoneIdentifier)
                } ?? logicalDate
                guard var point = points[anchorDate] else { continue }
                point.bowelMovements += 1
                points[anchorDate] = point
            }

            for activity in record.sexualActivities {
                let anchorDate = activity.time.map {
                    actualDisplayDate(for: $0, timeZoneIdentifier: activity.timeZoneIdentifier)
                } ?? activity.date.startOfDay
                guard var point = points[anchorDate] else { continue }
                point.sexualActivities += 1
                if activity.isMasturbation {
                    point.sexualActivitiesMasturbation += 1
                }
                points[anchorDate] = point
            }
        }

        return points
    }

    private static func availableLowerBound(for records: [DailyRecord], fallback: Date) -> Date {
        let candidates = records.flatMap { record -> [Date] in
            var dates = [record.date.startOfDay]
            if let bedtime = record.sleepRecord.bedtimePreviousNight {
                dates.append(actualDisplayDate(for: bedtime, timeZoneIdentifier: record.sleepRecord.timeZoneIdentifier))
            }
            if let wakeTime = record.sleepRecord.wakeTimeCurrentDay {
                dates.append(actualDisplayDate(for: wakeTime, timeZoneIdentifier: record.sleepRecord.timeZoneIdentifier))
            }
            dates += record.meals.compactMap {
                guard let time = $0.time else { return nil }
                return actualDisplayDate(for: time, timeZoneIdentifier: $0.timeZoneIdentifier)
            }
            dates += record.showers.compactMap {
                guard let time = $0.time else { return nil }
                return actualDisplayDate(for: time, timeZoneIdentifier: $0.timeZoneIdentifier)
            }
            dates += record.bowelMovements.compactMap {
                guard let time = $0.time else { return nil }
                return actualDisplayDate(for: time, timeZoneIdentifier: $0.timeZoneIdentifier)
            }
            dates += record.sexualActivities.map {
                if let time = $0.time {
                    return actualDisplayDate(for: time, timeZoneIdentifier: $0.timeZoneIdentifier)
                }
                return $0.date.startOfDay
            }
            return dates
        }
        return candidates.min() ?? fallback
    }

    private static func historicalDayPointsStartingAtFirstMatch(
        in days: [AnalyticsDayPoint],
        matches: (AnalyticsDayPoint) -> Bool
    ) -> [AnalyticsDayPoint] {
        guard let startDate = days.first(where: matches)?.date else { return [] }
        return days.filter { $0.date >= startDate }
    }

    private static func averageSexualActivityPerWeek(
        activityDates: [Date],
        upperBound: Date,
        calendar: Calendar
    ) -> Double? {
        guard let firstDate = activityDates.min() else { return nil }
        guard let firstWeekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: firstDate)),
              let lastWeekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: upperBound)) else {
            return nil
        }

        let weekDistance = calendar.dateComponents([.weekOfYear], from: firstWeekStart, to: lastWeekStart).weekOfYear ?? 0
        let totalWeeks = max(1.0, Double(weekDistance + 1))
        return Double(activityDates.count) / totalWeeks
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

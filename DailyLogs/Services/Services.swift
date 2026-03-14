import AuthenticationServices
import CoreLocation
import Foundation
import UIKit

protocol AuthService {
    var currentUser: UserAccount? { get }
    func restoreSession() -> UserAccount?
    func handleAppleSignIn(result: Result<ASAuthorization, Error>) throws -> UserAccount
    func continueAsGuest() throws -> UserAccount
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

protocol HealthSyncAdapter {
    func latestSleepSourceHint() -> RecordSource?
}

final class LocalAuthService: AuthService {
    private let defaults = UserDefaults.standard
    private let key = "dailylogs.currentUser"
    private let guestID = "guest.local"
    private let store: LocalJSONStore

    init(store: LocalJSONStore) {
        self.store = store
    }

    var currentUser: UserAccount? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(UserAccount.self, from: data)
    }

    func restoreSession() -> UserAccount? {
        guard let session = currentUser else { return nil }
        let refreshed = refreshUser(session)
        if let refreshed {
            persistSession(refreshed)
        }
        return refreshed
    }

    func handleAppleSignIn(result: Result<ASAuthorization, Error>) throws -> UserAccount {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                throw AuthError.invalidCredential
            }
            let given = credential.fullName?.givenName ?? ""
            let family = credential.fullName?.familyName ?? ""
            let displayName = [given, family]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let previousUser = currentUser
            let user = UserAccount(
                userID: credential.user,
                displayName: displayName.isEmpty ? (previousUser?.displayName ?? "我的记录") : displayName,
                email: credential.email ?? previousUser?.email,
                authMode: .apple,
                createdAt: resolveCreatedAt(for: credential.user)
            )
            let refreshed = try saveProfile(for: user)
            persistSession(refreshed)
            return refreshed
        case .failure(let error):
            throw error
        }
    }

    func continueAsGuest() throws -> UserAccount {
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

    func signOut() throws {
        defaults.removeObject(forKey: key)
    }

    enum AuthError: LocalizedError {
        case invalidCredential

        var errorDescription: String? {
            "Apple 登录结果不可用。"
        }
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
}

final class LocalJSONStore {
    struct Database: Codable {
        var recordsByUser: [String: [String: DailyRecord]] = [:]
        var preferencesByUser: [String: UserPreferences] = [:]
        var profilesByUser: [String: UserProfile] = [:]
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
    func latestSleepSourceHint() -> RecordSource? {
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
    var averageWakeMinutes: Double?
    var mealCompletionRate: Double
    var averageShowers: Double
    var points: [AnalyticsPoint]
}

enum AnalyticsCalculator {
    static func build(records: [DailyRecord], range: AnalyticsRange) -> AnalyticsSummary {
        let calendar = Calendar.current
        let cutoff = calendar.startOfDay(for: .now).adding(days: -(range.rawValue - 1))
        let filtered = records
            .filter { $0.date >= cutoff }
            .sorted { $0.date < $1.date }

        let points = filtered.map { record in
            let sleepHours = (record.sleepRecord.duration ?? 0) / 3600
            let wakeMinutes = record.sleepRecord.wakeTimeCurrentDay.map {
                let comps = calendar.dateComponents([.hour, .minute], from: $0)
                return Double((comps.hour ?? 0) * 60 + (comps.minute ?? 0))
            }
            let loggedMeals = record.meals.filter { $0.effectiveStatus(on: record.date) == .logged }.count
            let skippedMeals = record.meals.filter { $0.effectiveStatus(on: record.date) == .skipped }.count
            return AnalyticsPoint(
                date: record.date,
                sleepHours: sleepHours,
                wakeMinutes: wakeMinutes,
                loggedMeals: loggedMeals,
                skippedMeals: skippedMeals,
                showers: record.showers.count
            )
        }

        let averageSleepHours = points
            .map(\.sleepHours)
            .filter { $0 > 0 }
            .average
        let averageWakeMinutes = points.compactMap(\.wakeMinutes).averageOptional

        let allTrackedMeals = Double(filtered.flatMap(\.meals).count)
        let allLoggedMeals = Double(
            filtered.flatMap { record in
                record.meals.filter { $0.effectiveStatus(on: record.date) == .logged }
            }.count
        )
        let mealCompletionRate = allTrackedMeals > 0 ? allLoggedMeals / allTrackedMeals : 0
        let averageShowers = filtered.map { Double($0.showers.count) }.average

        return AnalyticsSummary(
            averageSleepHours: averageSleepHours,
            averageWakeMinutes: averageWakeMinutes,
            mealCompletionRate: mealCompletionRate,
            averageShowers: averageShowers,
            points: points
        )
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

import Foundation
import SwiftUI

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

enum TimeZoneDisplay {
    static func utcOffsetText(for timeZoneIdentifier: String, at date: Date = .now) -> String {
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else {
            return NSLocalizedString("UTC 未知", comment: "")
        }
        return utcOffsetText(for: timeZone, at: date)
    }

    static func userFacingTimeZoneText(for timeZoneIdentifier: String, at date: Date = .now) -> String {
        utcOffsetText(for: timeZoneIdentifier, at: date) + " · " + timeZoneIdentifier
    }

    private static func utcOffsetText(for timeZone: TimeZone, at date: Date) -> String {
        let seconds = timeZone.secondsFromGMT(for: date)
        let sign = seconds >= 0 ? "+" : "-"
        let absoluteSeconds = abs(seconds)
        let hours = absoluteSeconds / 3_600
        let minutes = (absoluteSeconds % 3_600) / 60
        return String(format: "UTC%@%02d:%02d", sign, hours, minutes)
    }
}

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case system
    case zhHans
    case en

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: NSLocalizedString("跟随系统", comment: "")
        case .zhHans: NSLocalizedString("中文", comment: "")
        case .en: "English"
        }
    }

    var locale: Locale? {
        switch self {
        case .system: nil
        case .zhHans: Locale(identifier: "zh-Hans")
        case .en: Locale(identifier: "en")
        }
    }

    var appleLanguageCode: [String]? {
        switch self {
        case .system: nil
        case .zhHans: ["zh-Hans", "zh"]
        case .en: ["en"]
        }
    }

    var appleLocaleIdentifier: String? {
        switch self {
        case .system: nil
        case .zhHans: "zh_CN"
        case .en: "en_US"
        }
    }
}

enum AuthMode: String, Codable, Equatable {
    case apple
    case guest
}

struct UserAccount: Codable, Equatable {
    var userID: String
    var displayName: String
    var email: String?
    var authMode: AuthMode
    var createdAt: Date

    var isGuest: Bool {
        authMode == .guest
    }

    enum CodingKeys: String, CodingKey {
        case userID
        case displayName
        case email
        case authMode
        case createdAt
    }

    init(
        userID: String,
        displayName: String,
        email: String?,
        authMode: AuthMode,
        createdAt: Date
    ) {
        self.userID = userID
        self.displayName = displayName
        self.email = email
        self.authMode = authMode
        self.createdAt = createdAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userID = try container.decode(String.self, forKey: .userID)
        displayName = try container.decode(String.self, forKey: .displayName)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        authMode = try container.decode(AuthMode.self, forKey: .authMode)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now.startOfDay
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userID, forKey: .userID)
        try container.encode(displayName, forKey: .displayName)
        try container.encodeIfPresent(email, forKey: .email)
        try container.encode(authMode, forKey: .authMode)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

struct UserProfile: Codable, Equatable {
    var userID: String
    var displayName: String?
    var email: String?
    var authMode: AuthMode?
    var createdAt: Date
}

enum RecordSource: String, Codable, CaseIterable {
    case manual
    case healthKit
}

enum TimeDisplayMode: String, Codable, CaseIterable, Identifiable {
    case current
    case recorded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .current:
            NSLocalizedString("当前时区", comment: "")
        case .recorded:
            NSLocalizedString("记录地", comment: "")
        }
    }

    var shortTitle: String {
        switch self {
        case .current:
            NSLocalizedString("当前", comment: "")
        case .recorded:
            NSLocalizedString("记录地", comment: "")
        }
    }
}

enum TemperatureUnitPreference: String, Codable, CaseIterable, Identifiable {
    case celsius
    case fahrenheit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .celsius:
            NSLocalizedString("摄氏度", comment: "")
        case .fahrenheit:
            NSLocalizedString("华氏度", comment: "")
        }
    }

    var symbol: String {
        switch self {
        case .celsius:
            "C"
        case .fahrenheit:
            "F"
        }
    }
}

enum MealKind: String, Codable, CaseIterable, Identifiable {
    case breakfast
    case lunch
    case dinner
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breakfast: NSLocalizedString("早餐", comment: "")
        case .lunch: NSLocalizedString("午餐", comment: "")
        case .dinner: NSLocalizedString("晚餐", comment: "")
        case .custom: NSLocalizedString("自定义", comment: "")
        }
    }
}

enum MealTitleSuggestion {
    static func title(for date: Date, in timeZone: TimeZone = .autoupdatingCurrent) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let minutes = calendar.component(.hour, from: date) * 60
            + calendar.component(.minute, from: date)

        switch minutes {
        case 5 * 60 ..< 10 * 60:
            return NSLocalizedString("早咖啡", comment: "")
        case 10 * 60 ..< 12 * 60:
            return NSLocalizedString("上午茶", comment: "")
        case 12 * 60 ..< 14 * 60:
            return NSLocalizedString("午间加餐", comment: "")
        case 14 * 60 ..< 18 * 60:
            return NSLocalizedString("下午茶", comment: "")
        case 18 * 60 ..< 22 * 60:
            return NSLocalizedString("晚间加餐", comment: "")
        default:
            return NSLocalizedString("夜宵", comment: "")
        }
    }
}

enum MealStatus: String, Codable, CaseIterable {
    case empty
    case logged
    case skipped

    var title: String {
        switch self {
        case .empty: NSLocalizedString("未记录", comment: "")
        case .logged: NSLocalizedString("已记录", comment: "")
        case .skipped: NSLocalizedString("跳过", comment: "")
        }
    }
}

struct MealSlot: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var kind: MealKind
    var title: String
    var isDefault: Bool = false

    static let defaults: [MealSlot] = [
        MealSlot(kind: .breakfast, title: "breakfast", isDefault: true),
        MealSlot(kind: .lunch, title: "lunch", isDefault: true),
        MealSlot(kind: .dinner, title: "dinner", isDefault: true)
    ]

    var displayTitle: String {
        isDefault ? kind.title : title
    }
}

struct SunTimes: Codable, Equatable {
    var sunrise: Date
    var sunset: Date
    var timeZoneIdentifier: String?

    enum CodingKeys: String, CodingKey {
        case sunrise, sunset, timeZoneIdentifier
    }

    init(
        sunrise: Date,
        sunset: Date,
        timeZoneIdentifier: String? = nil
    ) {
        self.sunrise = sunrise
        self.sunset = sunset
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sunrise = try container.decode(Date.self, forKey: .sunrise)
        sunset = try container.decode(Date.self, forKey: .sunset)
        timeZoneIdentifier = try container.decodeIfPresent(String.self, forKey: .timeZoneIdentifier)
    }
}

struct WeatherSnapshot: Codable, Equatable, Sendable {
    var conditionDescription: String
    var symbolName: String
    var temperatureCelsius: Double
    var lowTemperatureCelsius: Double
    var highTemperatureCelsius: Double
}

enum SleepStage: String, Codable, CaseIterable {
    case awake, light, deep, rem

    var title: String {
        switch self {
        case .awake: NSLocalizedString("清醒", comment: "")
        case .light: NSLocalizedString("浅睡", comment: "")
        case .deep: NSLocalizedString("深睡", comment: "")
        case .rem: "REM"
        }
    }

    var color: SwiftUI.Color {
        switch self {
        case .awake: Color(red: 0.90, green: 0.66, blue: 0.26)
        case .light: Color(red: 0.55, green: 0.68, blue: 0.92)
        case .deep: Color(red: 0.30, green: 0.40, blue: 0.78)
        case .rem: Color(red: 0.62, green: 0.44, blue: 0.82)
        }
    }
}

struct SleepStageInterval: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var stage: SleepStage
    var start: Date
    var end: Date

    var duration: TimeInterval {
        end.timeIntervalSince(start)
    }
}

struct SleepRecord: Codable, Equatable {
    var bedtimePreviousNight: Date?
    var wakeTimeCurrentDay: Date?
    var targetBedtime: DateComponents?
    var source: RecordSource = .manual
    var stageIntervals: [SleepStageInterval] = []
    var timeZoneIdentifier: String?
    var note: String?

    var duration: TimeInterval? {
        guard let bedtimePreviousNight, let wakeTimeCurrentDay else { return nil }
        let rawDuration = wakeTimeCurrentDay.timeIntervalSince(bedtimePreviousNight)
        guard rawDuration > 0 else { return nil }
        let awakeDuration = stageDurations[.awake] ?? 0
        let adjustedDuration = rawDuration - awakeDuration
        return adjustedDuration > 0 ? adjustedDuration : rawDuration
    }

    var hasStageData: Bool {
        !stageIntervals.isEmpty
    }

    var stageDurations: [SleepStage: TimeInterval] {
        Dictionary(grouping: stageIntervals, by: \.stage)
            .mapValues { intervals in intervals.reduce(0) { $0 + $1.duration } }
    }

    enum CodingKeys: String, CodingKey {
        case bedtimePreviousNight, wakeTimeCurrentDay, targetBedtime, source, stageIntervals, timeZoneIdentifier, note
    }

    init(
        bedtimePreviousNight: Date? = nil,
        wakeTimeCurrentDay: Date? = nil,
        targetBedtime: DateComponents? = nil,
        source: RecordSource = .manual,
        stageIntervals: [SleepStageInterval] = [],
        timeZoneIdentifier: String? = nil,
        note: String? = nil
    ) {
        self.bedtimePreviousNight = bedtimePreviousNight
        self.wakeTimeCurrentDay = wakeTimeCurrentDay
        self.targetBedtime = targetBedtime
        self.source = source
        self.stageIntervals = stageIntervals
        self.timeZoneIdentifier = timeZoneIdentifier
        self.note = note
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bedtimePreviousNight = try container.decodeIfPresent(Date.self, forKey: .bedtimePreviousNight)
        wakeTimeCurrentDay = try container.decodeIfPresent(Date.self, forKey: .wakeTimeCurrentDay)
        targetBedtime = try container.decodeIfPresent(DateComponents.self, forKey: .targetBedtime)
        source = try container.decodeIfPresent(RecordSource.self, forKey: .source) ?? .manual
        stageIntervals = try container.decodeIfPresent([SleepStageInterval].self, forKey: .stageIntervals) ?? []
        timeZoneIdentifier = try container.decodeIfPresent(String.self, forKey: .timeZoneIdentifier)
        note = try container.decodeIfPresent(String.self, forKey: .note)
    }
}

struct MealEntry: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var mealKind: MealKind
    var customTitle: String?
    var status: MealStatus = .empty
    var time: Date?
    var photoURLs: [String]
    var timeZoneIdentifier: String?
    var note: String?
    var locationName: String?
    var latitude: Double?
    var longitude: Double?
    var isLocationManuallyEdited: Bool
    var isCustomTitleManuallyEdited: Bool
    var travelContext: TravelRecordContext?

    var displayTitle: String {
        customTitle?.isEmpty == false ? customTitle! : mealKind.title
    }

    var slotKey: String {
        switch mealKind {
        case .custom:
            return "custom-\(customTitle ?? id.uuidString)"
        default:
            return mealKind.rawValue
        }
    }

    var hasPhoto: Bool {
        !photoURLs.isEmpty
    }

    var primaryPhotoURL: String? {
        photoURLs.first
    }

    var photoURL: String? {
        get { primaryPhotoURL }
        set { photoURLs = newValue.map { [$0] } ?? [] }
    }

    static func sortedByTime(_ meals: [MealEntry], on baseDate: Date) -> [MealEntry] {
        meals.sorted { lhs, rhs in
            let lhsDate = lhs.sortingDate(on: baseDate)
            let rhsDate = rhs.sortingDate(on: baseDate)

            switch (lhsDate, rhsDate) {
            case let (lhs?, rhs?):
                if lhs != rhs {
                    return lhs < rhs
                }
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                break
            }

            if lhs.displayTitle != rhs.displayTitle {
                return lhs.displayTitle < rhs.displayTitle
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func sortingDate(on baseDate: Date) -> Date? {
        if let time {
            return time
        }

        switch mealKind {
        case .breakfast:
            return baseDate.settingTime(hour: 8, minute: 0)
        case .lunch:
            return baseDate.settingTime(hour: 12, minute: 0)
        case .dinner:
            return baseDate.settingTime(hour: 18, minute: 0)
        case .custom:
            return nil
        }
    }

    var isLoggedWithoutTime: Bool {
        effectiveStatus(on: .now, relativeTo: .now) == .logged && time == nil
    }

    func effectiveStatus(on recordDate: Date, relativeTo referenceDate: Date = .now) -> MealStatus {
        if status == .logged || time != nil || hasPhoto {
            return .logged
        }
        if status == .skipped {
            return .skipped
        }
        return recordDate.startOfDay < referenceDate.startOfDay ? .skipped : .empty
    }

    enum CodingKeys: String, CodingKey {
        case id, mealKind, customTitle, status, time, photoURL, photoURLs, timeZoneIdentifier
        case note, locationName, latitude, longitude, isLocationManuallyEdited
        case isCustomTitleManuallyEdited, travelContext
    }

    init(
        id: UUID = UUID(),
        mealKind: MealKind,
        customTitle: String? = nil,
        status: MealStatus = .empty,
        time: Date? = nil,
        photoURLs: [String] = [],
        photoURL: String? = nil,
        timeZoneIdentifier: String? = nil,
        note: String? = nil,
        locationName: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        isLocationManuallyEdited: Bool = false,
        isCustomTitleManuallyEdited: Bool = false,
        travelContext: TravelRecordContext? = nil
    ) {
        self.id = id
        self.mealKind = mealKind
        self.customTitle = customTitle
        self.status = status
        self.time = time
        self.photoURLs = photoURLs.isEmpty ? (photoURL.map { [$0] } ?? []) : photoURLs
        self.timeZoneIdentifier = timeZoneIdentifier
        self.note = note
        self.locationName = locationName
        self.latitude = latitude
        self.longitude = longitude
        self.isLocationManuallyEdited = isLocationManuallyEdited
        self.isCustomTitleManuallyEdited = isCustomTitleManuallyEdited
        self.travelContext = travelContext
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        mealKind = try container.decode(MealKind.self, forKey: .mealKind)
        customTitle = try container.decodeIfPresent(String.self, forKey: .customTitle)
        status = try container.decodeIfPresent(MealStatus.self, forKey: .status) ?? .empty
        time = try container.decodeIfPresent(Date.self, forKey: .time)
        let decodedPhotoURLs = try container.decodeIfPresent([String].self, forKey: .photoURLs) ?? []
        if decodedPhotoURLs.isEmpty, let legacyPhotoURL = try container.decodeIfPresent(String.self, forKey: .photoURL) {
            photoURLs = [legacyPhotoURL]
        } else {
            photoURLs = decodedPhotoURLs
        }
        timeZoneIdentifier = try container.decodeIfPresent(String.self, forKey: .timeZoneIdentifier)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        locationName = try container.decodeIfPresent(String.self, forKey: .locationName)
        latitude = try container.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)
        isLocationManuallyEdited = try container.decodeIfPresent(Bool.self, forKey: .isLocationManuallyEdited)
            ?? (locationName != nil || latitude != nil || longitude != nil)
        isCustomTitleManuallyEdited = try container.decodeIfPresent(Bool.self, forKey: .isCustomTitleManuallyEdited)
            ?? (mealKind == .custom && customTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
        travelContext = try container.decodeIfPresent(TravelRecordContext.self, forKey: .travelContext)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(mealKind, forKey: .mealKind)
        try container.encodeIfPresent(customTitle, forKey: .customTitle)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(time, forKey: .time)
        try container.encode(photoURLs, forKey: .photoURLs)
        try container.encodeIfPresent(primaryPhotoURL, forKey: .photoURL)
        try container.encodeIfPresent(timeZoneIdentifier, forKey: .timeZoneIdentifier)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encodeIfPresent(locationName, forKey: .locationName)
        try container.encodeIfPresent(latitude, forKey: .latitude)
        try container.encodeIfPresent(longitude, forKey: .longitude)
        try container.encode(isLocationManuallyEdited, forKey: .isLocationManuallyEdited)
        try container.encode(isCustomTitleManuallyEdited, forKey: .isCustomTitleManuallyEdited)
        try container.encodeIfPresent(travelContext, forKey: .travelContext)
    }
}

struct DailyVideoEntry: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var videoURL: String
    var duration: TimeInterval
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, videoURL, duration, createdAt
    }

    init(
        id: UUID = UUID(),
        videoURL: String,
        duration: TimeInterval,
        createdAt: Date = .now
    ) {
        self.id = id
        self.videoURL = videoURL
        self.duration = duration
        self.createdAt = createdAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        videoURL = try container.decode(String.self, forKey: .videoURL)
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 10
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
    }
}

enum HomeSectionKind: String, Codable, CaseIterable, Identifiable {
    case sunTimes
    case sleep
    case meals
    case showers
    case bowelMovements
    case sexualActivity
    case dailyVideo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sunTimes: NSLocalizedString("日出日落", comment: "")
        case .sleep: NSLocalizedString("睡眠", comment: "")
        case .meals: NSLocalizedString("餐食", comment: "")
        case .showers: NSLocalizedString("洗澡", comment: "")
        case .bowelMovements: NSLocalizedString("排便", comment: "")
        case .sexualActivity: NSLocalizedString("性生活", comment: "")
        case .dailyVideo: NSLocalizedString("每日视频", comment: "")
        }
    }

    static let defaultVisible: [HomeSectionKind] = [.sunTimes, .sleep, .meals, .dailyVideo, .showers]
}

struct ShowerEntry: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var time: Date?
    var timeZoneIdentifier: String?
    var note: String?
    var travelContext: TravelRecordContext?

    enum CodingKeys: String, CodingKey {
        case id, time, timeZoneIdentifier, note, travelContext
    }

    init(
        id: UUID = UUID(),
        time: Date? = nil,
        timeZoneIdentifier: String? = nil,
        note: String? = nil,
        travelContext: TravelRecordContext? = nil
    ) {
        self.id = id
        self.time = time
        self.timeZoneIdentifier = timeZoneIdentifier
        self.note = note
        self.travelContext = travelContext
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        time = try container.decodeIfPresent(Date.self, forKey: .time)
        timeZoneIdentifier = try container.decodeIfPresent(String.self, forKey: .timeZoneIdentifier)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        travelContext = try container.decodeIfPresent(TravelRecordContext.self, forKey: .travelContext)
    }
}

struct BowelMovementEntry: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var time: Date?
    var timeZoneIdentifier: String?
    var note: String?
    var travelContext: TravelRecordContext?

    enum CodingKeys: String, CodingKey {
        case id, time, timeZoneIdentifier, note, travelContext
    }

    init(
        id: UUID = UUID(),
        time: Date? = nil,
        timeZoneIdentifier: String? = nil,
        note: String? = nil,
        travelContext: TravelRecordContext? = nil
    ) {
        self.id = id
        self.time = time
        self.timeZoneIdentifier = timeZoneIdentifier
        self.note = note
        self.travelContext = travelContext
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        time = try container.decodeIfPresent(Date.self, forKey: .time)
        timeZoneIdentifier = try container.decodeIfPresent(String.self, forKey: .timeZoneIdentifier)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        travelContext = try container.decodeIfPresent(TravelRecordContext.self, forKey: .travelContext)
    }
}

struct SexualActivityEntry: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var date: Date
    var time: Date?
    var isMasturbation: Bool = false
    var timeZoneIdentifier: String?
    var note: String?
    var travelContext: TravelRecordContext?

    enum CodingKeys: String, CodingKey {
        case id, date, time, isMasturbation, timeZoneIdentifier, note, travelContext
    }

    init(
        id: UUID = UUID(),
        date: Date,
        time: Date? = nil,
        isMasturbation: Bool = false,
        timeZoneIdentifier: String? = nil,
        note: String? = nil,
        travelContext: TravelRecordContext? = nil
    ) {
        self.id = id
        self.date = date
        self.time = time
        self.isMasturbation = isMasturbation
        self.timeZoneIdentifier = timeZoneIdentifier
        self.note = note
        self.travelContext = travelContext
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try container.decode(Date.self, forKey: .date)
        time = try container.decodeIfPresent(Date.self, forKey: .time)
        isMasturbation = try container.decodeIfPresent(Bool.self, forKey: .isMasturbation) ?? false
        timeZoneIdentifier = try container.decodeIfPresent(String.self, forKey: .timeZoneIdentifier)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        travelContext = try container.decodeIfPresent(TravelRecordContext.self, forKey: .travelContext)
    }
}

enum TravelPlanStatus: String, Codable, CaseIterable {
    case planned
    case preDeparture
    case inFlight
    case layover
    case arrived
    case completed

    var title: String {
        switch self {
        case .planned: NSLocalizedString("未开始", comment: "")
        case .preDeparture: NSLocalizedString("出发前", comment: "")
        case .inFlight: NSLocalizedString("飞行中", comment: "")
        case .layover: NSLocalizedString("转机中", comment: "")
        case .arrived: NSLocalizedString("已到达", comment: "")
        case .completed: NSLocalizedString("已结束", comment: "")
        }
    }

    var allowsPlanEditing: Bool {
        switch self {
        case .planned, .preDeparture, .inFlight, .layover, .arrived:
            true
        case .completed:
            false
        }
    }
}

struct TravelRecordContext: Codable, Equatable {
    var planID: UUID
    var segmentID: UUID?
    var phase: TravelPlanStatus

    enum CodingKeys: String, CodingKey {
        case planID, segmentID, phase
    }
}

struct TravelTimeDisplay: Equatable {
    var primary: String
    var secondary: String?
}

struct AirportInfo: Codable, Equatable, Identifiable {
    var code: String
    var name: String
    var city: String
    var country: String
    var timeZoneIdentifier: String

    var id: String { code }

    var displayTitle: String {
        "\(code) · \(city)"
    }

    var detailText: String {
        "\(name) · \(country)"
    }
}

enum AirportCatalog {
    private final class BundleToken {}

    static let airports: [AirportInfo] = loadAirports()
    private static let airportsByCode: [String: AirportInfo] = {
        var indexed: [String: AirportInfo] = [:]
        for airport in airports where indexed[airport.code] == nil {
            indexed[airport.code] = airport
        }
        return indexed
    }()

    static func airport(for code: String) -> AirportInfo? {
        airportsByCode[code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()]
    }

    static func search(_ query: String, limit: Int = 8) -> [AirportInfo] {
        let normalized = normalizedSearchText(query)
        guard !normalized.isEmpty else { return [] }

        let scored = airports.compactMap { airport -> (AirportInfo, Int)? in
            let code = airport.code
            let city = normalizedSearchText(airport.city)
            let name = normalizedSearchText(airport.name)
            let country = normalizedSearchText(airport.country)

            if code == normalized.uppercased() { return (airport, 0) }
            if code.hasPrefix(normalized.uppercased()) { return (airport, 1) }
            if city.hasPrefix(normalized) { return (airport, 2) }
            if name.hasPrefix(normalized) { return (airport, 3) }
            if city.contains(normalized) || name.contains(normalized) || country.contains(normalized) {
                return (airport, 4)
            }
            return nil
        }

        return scored
            .sorted {
                if $0.1 != $1.1 { return $0.1 < $1.1 }
                if $0.0.city != $1.0.city { return $0.0.city < $1.0.city }
                return $0.0.code < $1.0.code
            }
            .prefix(limit)
            .map(\.0)
    }

    private static func loadAirports() -> [AirportInfo] {
        let candidateBundles = [Bundle.main, Bundle(for: BundleToken.self)]
        for bundle in candidateBundles {
            guard let url = bundle.url(forResource: "airports", withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let airports = try? JSONDecoder().decode([AirportInfo].self, from: data),
                  !airports.isEmpty else {
                continue
            }
            return airports.sorted { $0.code < $1.code }
        }

        return fallbackAirports
    }

    private static func normalizedSearchText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    private static let fallbackAirports: [AirportInfo] = [
        AirportInfo(code: "BOS", name: "General Edward Lawrence Logan International Airport", city: "Boston", country: "US", timeZoneIdentifier: "America/New_York"),
        AirportInfo(code: "LHR", name: "London Heathrow Airport", city: "London", country: "GB", timeZoneIdentifier: "Europe/London"),
        AirportInfo(code: "PKX", name: "Beijing Daxing International Airport", city: "Beijing", country: "CN", timeZoneIdentifier: "Asia/Shanghai")
    ]
}

struct TravelSleepSession: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var segmentID: UUID?
    var phase: TravelPlanStatus
    var title: String
    var startTime: Date
    var endTime: Date
    var timeZoneIdentifier: String?
    var source: RecordSource = .manual
    var note: String?

    enum CodingKeys: String, CodingKey {
        case id, segmentID, phase, title, startTime, endTime, timeZoneIdentifier, source, note
    }

    init(
        id: UUID = UUID(),
        segmentID: UUID? = nil,
        phase: TravelPlanStatus,
        title: String,
        startTime: Date,
        endTime: Date,
        timeZoneIdentifier: String? = nil,
        source: RecordSource = .manual,
        note: String? = nil
    ) {
        self.id = id
        self.segmentID = segmentID
        self.phase = phase
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? NSLocalizedString("睡眠", comment: "")
        self.startTime = startTime
        self.endTime = max(startTime, endTime)
        self.timeZoneIdentifier = timeZoneIdentifier
        self.source = source
        self.note = note?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    var duration: TimeInterval {
        max(0, endTime.timeIntervalSince(startTime))
    }
}

struct TravelSegment: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var flightNumber: String?
    var originCode: String
    var destinationCode: String
    var plannedDepartureTime: Date
    var plannedArrivalTime: Date
    var departureTimeZoneIdentifier: String
    var arrivalTimeZoneIdentifier: String
    var actualDepartureTime: Date? = nil
    var actualArrivalTime: Date? = nil

    enum CodingKeys: String, CodingKey {
        case id, flightNumber, originCode, destinationCode, plannedDepartureTime, plannedArrivalTime
        case departureTimeZoneIdentifier, arrivalTimeZoneIdentifier
    }

    init(
        id: UUID = UUID(),
        flightNumber: String? = nil,
        originCode: String,
        destinationCode: String,
        plannedDepartureTime: Date,
        plannedArrivalTime: Date,
        departureTimeZoneIdentifier: String,
        arrivalTimeZoneIdentifier: String,
        actualDepartureTime: Date? = nil,
        actualArrivalTime: Date? = nil
    ) {
        self.id = id
        self.flightNumber = flightNumber?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.originCode = originCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.destinationCode = destinationCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.plannedDepartureTime = plannedDepartureTime
        self.plannedArrivalTime = plannedArrivalTime
        self.departureTimeZoneIdentifier = departureTimeZoneIdentifier
        self.arrivalTimeZoneIdentifier = arrivalTimeZoneIdentifier
        self.actualDepartureTime = nil
        self.actualArrivalTime = nil
    }

    var departureTimeZone: TimeZone {
        TimeZone(identifier: departureTimeZoneIdentifier) ?? .autoupdatingCurrent
    }

    var arrivalTimeZone: TimeZone {
        TimeZone(identifier: arrivalTimeZoneIdentifier) ?? .autoupdatingCurrent
    }

    var departureTime: Date {
        plannedDepartureTime
    }

    var arrivalTime: Date {
        plannedArrivalTime
    }

    var plannedDuration: TimeInterval {
        normalizedPlannedArrivalTime.timeIntervalSince(plannedDepartureTime)
    }

    var actualDuration: TimeInterval? {
        nil
    }

    var effectiveDuration: TimeInterval {
        max(0, plannedDuration)
    }

    private var normalizedPlannedArrivalTime: Date {
        Self.normalizedArrivalTime(
            departure: plannedDepartureTime,
            arrival: plannedArrivalTime,
            departureTimeZone: departureTimeZone,
            arrivalTimeZone: arrivalTimeZone
        )
    }

    var routeTitle: String {
        "\(originCode)-\(destinationCode)"
    }

    var flightDisplayTitle: String {
        guard let flightNumber, !flightNumber.isEmpty else { return routeTitle }
        return "\(flightNumber) · \(routeTitle)"
    }

    func normalizedForChronology() -> TravelSegment {
        var normalized = self
        normalized.plannedArrivalTime = Self.normalizedArrivalTime(
            departure: plannedDepartureTime,
            arrival: plannedArrivalTime,
            departureTimeZone: departureTimeZone,
            arrivalTimeZone: arrivalTimeZone
        )
        normalized.actualDepartureTime = nil
        normalized.actualArrivalTime = nil
        return normalized
    }

    private static func normalizedArrivalTime(
        departure: Date,
        arrival: Date,
        departureTimeZone: TimeZone,
        arrivalTimeZone: TimeZone
    ) -> Date {
        var normalized = arrival
        while normalized <= departure {
            normalized = normalized.addingTimeInterval(86_400)
        }

        let duration = normalized.timeIntervalSince(departure)
        guard duration < minimumPlausibleFlightDuration || duration > maximumPlausibleFlightDuration else {
            return normalized
        }

        let departureOffset = TimeInterval(departureTimeZone.secondsFromGMT(for: departure))
        let arrivalOffset = TimeInterval(arrivalTimeZone.secondsFromGMT(for: normalized))
        let legacyDoubleShift = departureOffset - arrivalOffset
        guard legacyDoubleShift != 0 else { return normalized }

        let repaired = normalized.addingTimeInterval(-legacyDoubleShift)
        let repairedDuration = repaired.timeIntervalSince(departure)
        if repairedDuration >= minimumPlausibleFlightDuration,
           repairedDuration <= maximumPlausibleFlightDuration {
            return repaired
        }
        return normalized
    }

    private static func isPlausibleFlightDuration(_ duration: TimeInterval) -> Bool {
        duration >= minimumPlausibleFlightDuration && duration <= maximumPlausibleFlightDuration
    }

    private static let minimumPlausibleFlightDuration: TimeInterval = 20.0 * 60.0
    private static let maximumPlausibleFlightDuration: TimeInterval = 20.0 * 3600.0
}

struct TravelPlan: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var title: String
    var segments: [TravelSegment]
    var sleepSessions: [TravelSleepSession] = []
    var status: TravelPlanStatus = .planned
    var currentSegmentID: UUID?
    var createdAt: Date = .now
    var modifiedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, title, segments, sleepSessions, status, currentSegmentID, createdAt, modifiedAt
    }

    init(
        id: UUID = UUID(),
        title: String,
        segments: [TravelSegment],
        sleepSessions: [TravelSleepSession] = [],
        status: TravelPlanStatus = .planned,
        currentSegmentID: UUID? = nil,
        createdAt: Date = .now,
        modifiedAt: Date? = nil
    ) {
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? NSLocalizedString("未命名旅程", comment: "")
        self.segments = segments
        self.sleepSessions = sleepSessions.sorted { $0.startTime < $1.startTime }
        self.status = status
        self.currentSegmentID = currentSegmentID
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? NSLocalizedString("未命名旅程", comment: "")
        segments = try container.decodeIfPresent([TravelSegment].self, forKey: .segments) ?? []
        sleepSessions = try container.decodeIfPresent([TravelSleepSession].self, forKey: .sleepSessions) ?? []
        status = try container.decodeIfPresent(TravelPlanStatus.self, forKey: .status) ?? .planned
        currentSegmentID = try container.decodeIfPresent(UUID.self, forKey: .currentSegmentID)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt)
    }

    var routeSummary: String {
        guard let first = segments.first, let last = segments.last else { return title }
        return "\(first.originCode)-\(last.destinationCode)"
    }

    var displayTitle: String {
        title == routeSummary ? title : "\(title) · \(routeSummary)"
    }

    var currentSegmentIndex: Int? {
        if let currentSegmentID,
           let index = segments.firstIndex(where: { $0.id == currentSegmentID }) {
            return index
        }
        return segments.isEmpty ? nil : 0
    }

    var currentSegment: TravelSegment? {
        guard let currentSegmentIndex else { return nil }
        return segments[currentSegmentIndex]
    }

    var affectedStorageKeys: Set<String> {
        var keys: Set<String> = []
        for segment in segments {
            keys.insert(segment.departureTime.storageKey(in: segment.departureTimeZone))
            keys.insert(segment.arrivalTime.storageKey(in: segment.arrivalTimeZone))
        }

        guard let earliest = segments.map(\.departureTime).min(),
              let latest = segments.map(\.arrivalTime).max() else {
            return keys
        }
        var day = earliest.startOfDay
        let finalDay = latest.startOfDay
        while day <= finalDay {
            keys.insert(day.storageKey())
            day = day.adding(days: 1)
        }
        return keys
    }

    func affectedStorageKeys(using preferences: UserPreferences) -> Set<String> {
        var keys = affectedStorageKeys
        for segment in segments {
            keys.insert(preferences.storageKey(
                for: segment.departureTime,
                timeZoneIdentifier: segment.departureTimeZoneIdentifier,
                fallbackTimeZone: segment.departureTimeZone
            ))
            keys.insert(preferences.storageKey(
                for: segment.arrivalTime,
                timeZoneIdentifier: segment.arrivalTimeZoneIdentifier,
                fallbackTimeZone: segment.arrivalTimeZone
            ))
        }

        let keyDates = keys.compactMap(Self.date(fromStorageKey:))
        guard let earliest = keyDates.min(), let latest = keyDates.max() else {
            return keys
        }
        var day = earliest.startOfDay
        let finalDay = latest.startOfDay
        while day <= finalDay {
            keys.insert(day.storageKey())
            day = day.adding(days: 1)
        }
        return keys
    }

    var earliestCalendarDate: Date? {
        segments.map(\.departureTime).min()?.startOfDay
    }

    var latestCalendarDate: Date? {
        segments.map(\.arrivalTime).max()?.startOfDay
    }

    func earliestCalendarDate(using preferences: UserPreferences) -> Date? {
        affectedStorageKeys(using: preferences)
            .compactMap(Self.date(fromStorageKey:))
            .min()
    }

    func latestCalendarDate(using preferences: UserPreferences) -> Date? {
        affectedStorageKeys(using: preferences)
            .compactMap(Self.date(fromStorageKey:))
            .max()
    }

    var plannedTravelInterval: DateInterval? {
        guard let start = segments.map(\.departureTime).min(),
              let end = segments.map(\.arrivalTime).max(),
              end > start else {
            return nil
        }
        return DateInterval(start: start, end: end)
    }

    func normalizedForChronology() -> TravelPlan {
        var normalized = self
        normalized.segments = segments.map { $0.normalizedForChronology() }
        return normalized
    }

    mutating func advance(now: Date = .now) {
        guard !segments.isEmpty else { return }
        switch status {
        case .planned:
            currentSegmentID = segments.first?.id
            status = .preDeparture
        case .preDeparture:
            status = .inFlight
        case .inFlight:
            if let nextSegment = nextSegmentAfterCurrent() {
                currentSegmentID = nextSegment.id
                status = .layover
            } else {
                status = .arrived
            }
        case .layover:
            status = .inFlight
        case .arrived:
            status = .completed
        case .completed:
            break
        }
        modifiedAt = now
    }

    mutating func retreat(now: Date = .now) {
        guard !segments.isEmpty else { return }
        switch status {
        case .planned:
            break
        case .preDeparture:
            status = .planned
            currentSegmentID = nil
        case .inFlight:
            status = (currentSegmentIndex ?? 0) == 0 ? .preDeparture : .layover
        case .layover:
            if let previousSegment = previousSegmentBeforeCurrent() {
                currentSegmentID = previousSegment.id
            }
            status = .inFlight
        case .arrived:
            currentSegmentID = segments.last?.id
            status = .inFlight
        case .completed:
            status = .arrived
        }
        modifiedAt = now
    }

    private func nextSegmentAfterCurrent() -> TravelSegment? {
        guard let index = currentSegmentIndex else { return nil }
        let nextIndex = segments.index(after: index)
        guard segments.indices.contains(nextIndex) else { return nil }
        return segments[nextIndex]
    }

    private func previousSegmentBeforeCurrent() -> TravelSegment? {
        guard let index = currentSegmentIndex, index > segments.startIndex else { return nil }
        return segments[segments.index(before: index)]
    }

    private static func date(fromStorageKey key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))?.startOfDay
    }

    static func sampleBOSPKX() -> TravelPlan {
        let bosTimeZone = "America/New_York"
        let lhrTimeZone = "Europe/London"
        let pkxTimeZone = "Asia/Shanghai"
        return TravelPlan(
            title: NSLocalizedString("BOS-PKX 旅程", comment: ""),
            segments: [
                TravelSegment(
                    flightNumber: "BA238",
                    originCode: "BOS",
                    destinationCode: "LHR",
                    plannedDepartureTime: zonedDate(year: 2026, month: 5, day: 21, hour: 7, minute: 25, timeZoneID: bosTimeZone),
                    plannedArrivalTime: zonedDate(year: 2026, month: 5, day: 21, hour: 18, minute: 55, timeZoneID: lhrTimeZone),
                    departureTimeZoneIdentifier: bosTimeZone,
                    arrivalTimeZoneIdentifier: lhrTimeZone
                ),
                TravelSegment(
                    flightNumber: "BA089",
                    originCode: "LHR",
                    destinationCode: "PKX",
                    plannedDepartureTime: zonedDate(year: 2026, month: 5, day: 21, hour: 21, minute: 0, timeZoneID: lhrTimeZone),
                    plannedArrivalTime: zonedDate(year: 2026, month: 5, day: 22, hour: 14, minute: 15, timeZoneID: pkxTimeZone),
                    departureTimeZoneIdentifier: lhrTimeZone,
                    arrivalTimeZoneIdentifier: pkxTimeZone
                )
            ]
        )
    }

    private static func zonedDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        timeZoneID: String
    ) -> Date {
        let timeZone = TimeZone(identifier: timeZoneID) ?? .autoupdatingCurrent
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(
            timeZone: timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )) ?? .now
    }
}

struct DailyRecord: Codable, Equatable {
    var date: Date
    var sleepRecord: SleepRecord
    var meals: [MealEntry]
    var showers: [ShowerEntry]
    var bowelMovements: [BowelMovementEntry]
    var sexualActivities: [SexualActivityEntry]
    var dailyVideo: DailyVideoEntry?
    var locationName: String?
    var sunTimes: SunTimes?
    var weatherSnapshot: WeatherSnapshot?
    var aiInsightNarrative: DailyInsightNarrative?
    var modifiedAt: Date?

    enum CodingKeys: String, CodingKey {
        case date, sleepRecord, meals, showers, bowelMovements, sexualActivities
        case dailyVideo, locationName, sunTimes, weatherSnapshot, aiInsightNarrative, modifiedAt
    }

    init(
        date: Date,
        sleepRecord: SleepRecord,
        meals: [MealEntry],
        showers: [ShowerEntry],
        bowelMovements: [BowelMovementEntry] = [],
        sexualActivities: [SexualActivityEntry] = [],
        dailyVideo: DailyVideoEntry? = nil,
        locationName: String? = nil,
        sunTimes: SunTimes? = nil,
        weatherSnapshot: WeatherSnapshot? = nil,
        aiInsightNarrative: DailyInsightNarrative? = nil,
        modifiedAt: Date? = nil
    ) {
        self.date = date
        self.sleepRecord = sleepRecord
        self.meals = meals
        self.showers = showers
        self.bowelMovements = bowelMovements
        self.sexualActivities = sexualActivities
        self.dailyVideo = dailyVideo
        self.locationName = locationName
        self.sunTimes = sunTimes
        self.weatherSnapshot = weatherSnapshot
        self.aiInsightNarrative = aiInsightNarrative
        self.modifiedAt = modifiedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(Date.self, forKey: .date)
        sleepRecord = try container.decode(SleepRecord.self, forKey: .sleepRecord)
        meals = try container.decode([MealEntry].self, forKey: .meals)
        showers = try container.decodeIfPresent([ShowerEntry].self, forKey: .showers) ?? []
        bowelMovements = try container.decodeIfPresent([BowelMovementEntry].self, forKey: .bowelMovements) ?? []
        sexualActivities = try container.decodeIfPresent([SexualActivityEntry].self, forKey: .sexualActivities) ?? []
        dailyVideo = try container.decodeIfPresent(DailyVideoEntry.self, forKey: .dailyVideo)
        locationName = try container.decodeIfPresent(String.self, forKey: .locationName)
        sunTimes = try container.decodeIfPresent(SunTimes.self, forKey: .sunTimes)
        weatherSnapshot = try container.decodeIfPresent(WeatherSnapshot.self, forKey: .weatherSnapshot)
        aiInsightNarrative = try container.decodeIfPresent(DailyInsightNarrative.self, forKey: .aiInsightNarrative)
        modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt)
    }

    static func empty(for date: Date, preferences: UserPreferences) -> DailyRecord {
        DailyRecord(
            date: date.startOfDay,
            sleepRecord: SleepRecord(targetBedtime: preferences.bedtimeSchedule.target(for: date)),
            meals: preferences.defaultMealSlots.map {
                MealEntry(
                    mealKind: $0.kind,
                    customTitle: $0.kind == .custom ? $0.title : nil,
                    isCustomTitleManuallyEdited: $0.kind == .custom
                )
            },
            showers: [],
            bowelMovements: [],
            sexualActivities: [],
            dailyVideo: nil,
            locationName: nil,
            sunTimes: nil,
            weatherSnapshot: nil,
            aiInsightNarrative: nil
        )
    }
}

enum LocationPermissionState: String, Codable {
    case notDetermined
    case denied
    case authorized
}

enum AppearanceMode: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: NSLocalizedString("跟随系统", comment: "")
        case .light: NSLocalizedString("浅色", comment: "")
        case .dark: NSLocalizedString("深色", comment: "")
        }
    }
}

enum Weekday: Int, CaseIterable, Codable, Identifiable {
    case monday = 1
    case tuesday = 2
    case wednesday = 3
    case thursday = 4
    case friday = 5
    case saturday = 6
    case sunday = 7

    var id: Int { rawValue }

    var shortLabel: String {
        switch self {
        case .monday: NSLocalizedString("一", comment: "")
        case .tuesday: NSLocalizedString("二", comment: "")
        case .wednesday: NSLocalizedString("三", comment: "")
        case .thursday: NSLocalizedString("四", comment: "")
        case .friday: NSLocalizedString("五", comment: "")
        case .saturday: NSLocalizedString("六", comment: "")
        case .sunday: NSLocalizedString("日", comment: "")
        }
    }

    var title: String {
        switch self {
        case .monday: NSLocalizedString("周一", comment: "")
        case .tuesday: NSLocalizedString("周二", comment: "")
        case .wednesday: NSLocalizedString("周三", comment: "")
        case .thursday: NSLocalizedString("周四", comment: "")
        case .friday: NSLocalizedString("周五", comment: "")
        case .saturday: NSLocalizedString("周六", comment: "")
        case .sunday: NSLocalizedString("周日", comment: "")
        }
    }
}

struct BedtimeScheduleEntry: Codable, Equatable, Identifiable {
    var weekday: Weekday
    var time: DateComponents

    var id: Int { weekday.rawValue }
}

struct BedtimeSchedule: Codable, Equatable {
    var entries: [BedtimeScheduleEntry]

    static let `default` = BedtimeSchedule(
        entries: Weekday.allCases.map {
            BedtimeScheduleEntry(weekday: $0, time: DateComponents(hour: 23, minute: 30))
        }
    )

    static func uniform(_ time: DateComponents?) -> BedtimeSchedule {
        guard let time else { return .default }
        return BedtimeSchedule(
            entries: Weekday.allCases.map { BedtimeScheduleEntry(weekday: $0, time: time) }
        )
    }

    func target(for date: Date) -> DateComponents? {
        let weekday = Weekday(rawValue: date.isoWeekday)
        return entries.first(where: { $0.weekday == weekday })?.time
    }

    func summary() -> String {
        let grouped = Dictionary(grouping: entries, by: { $0.time.displayTime })
        let ordered = grouped.keys.sorted()
        return ordered.map { time in
            let days = (grouped[time] ?? [])
                .sorted { $0.weekday.rawValue < $1.weekday.rawValue }
                .map { $0.weekday.shortLabel }
                .joined()
            return "\(days) \(time)"
        }
        .joined(separator: " · ")
    }
}

struct UserPreferences: Codable, Equatable {
    static let currentHomeSectionSchemaVersion = 1

    var defaultMealSlots: [MealSlot] = MealSlot.defaults
    var bedtimeSchedule: BedtimeSchedule = .default
    var locationPermissionState: LocationPermissionState = .notDetermined
    var appearanceMode: AppearanceMode = .system
    var analyticsCustomization: AnalyticsCustomization = .default
    var healthKitSyncEnabled: Bool = false
    var appLanguage: AppLanguage = .system
    var timeDisplayMode: TimeDisplayMode = .recorded
    var temperatureUnit: TemperatureUnitPreference = .celsius
    var midnightMode: MidnightModeSettings = .default
    var visibleHomeSections: [HomeSectionKind] = HomeSectionKind.defaultVisible
    var showMasturbationOption: Bool = false
    var homeSectionSchemaVersion: Int = 0

    enum CodingKeys: String, CodingKey {
        case defaultMealSlots
        case bedtimeSchedule
        case locationPermissionState
        case appearanceMode
        case analyticsCustomization
        case healthKitSyncEnabled
        case appLanguage
        case timeDisplayMode
        case temperatureUnit
        case midnightMode
        case targetBedtime
        case visibleHomeSections
        case showMasturbationOption
        case homeSectionSchemaVersion
    }

    init(
        defaultMealSlots: [MealSlot] = MealSlot.defaults,
        bedtimeSchedule: BedtimeSchedule = .default,
        locationPermissionState: LocationPermissionState = .notDetermined,
        appearanceMode: AppearanceMode = .system,
        analyticsCustomization: AnalyticsCustomization = .default,
        healthKitSyncEnabled: Bool = false,
        appLanguage: AppLanguage = .system,
        timeDisplayMode: TimeDisplayMode = .recorded,
        temperatureUnit: TemperatureUnitPreference = .celsius,
        midnightMode: MidnightModeSettings = .default,
        visibleHomeSections: [HomeSectionKind] = HomeSectionKind.defaultVisible,
        showMasturbationOption: Bool = false,
        homeSectionSchemaVersion: Int = UserPreferences.currentHomeSectionSchemaVersion
    ) {
        self.defaultMealSlots = defaultMealSlots
        self.bedtimeSchedule = bedtimeSchedule
        self.locationPermissionState = locationPermissionState
        self.appearanceMode = appearanceMode
        self.analyticsCustomization = analyticsCustomization
        self.healthKitSyncEnabled = healthKitSyncEnabled
        self.appLanguage = appLanguage
        self.timeDisplayMode = timeDisplayMode
        self.temperatureUnit = temperatureUnit
        self.midnightMode = midnightMode
        self.visibleHomeSections = visibleHomeSections
        self.showMasturbationOption = showMasturbationOption
        self.homeSectionSchemaVersion = homeSectionSchemaVersion
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultMealSlots = try container.decodeIfPresent([MealSlot].self, forKey: .defaultMealSlots) ?? MealSlot.defaults
        locationPermissionState = try container.decodeIfPresent(LocationPermissionState.self, forKey: .locationPermissionState) ?? .notDetermined
        appearanceMode = try container.decodeIfPresent(AppearanceMode.self, forKey: .appearanceMode) ?? .system
        analyticsCustomization = try container.decodeIfPresent(AnalyticsCustomization.self, forKey: .analyticsCustomization) ?? .default
        healthKitSyncEnabled = try container.decodeIfPresent(Bool.self, forKey: .healthKitSyncEnabled) ?? false
        appLanguage = try container.decodeIfPresent(AppLanguage.self, forKey: .appLanguage) ?? .system
        timeDisplayMode = try container.decodeIfPresent(TimeDisplayMode.self, forKey: .timeDisplayMode) ?? .recorded
        temperatureUnit = try container.decodeIfPresent(TemperatureUnitPreference.self, forKey: .temperatureUnit) ?? .celsius
        midnightMode = try container.decodeIfPresent(MidnightModeSettings.self, forKey: .midnightMode) ?? .default
        visibleHomeSections = try container.decodeIfPresent([HomeSectionKind].self, forKey: .visibleHomeSections) ?? HomeSectionKind.defaultVisible
        showMasturbationOption = try container.decodeIfPresent(Bool.self, forKey: .showMasturbationOption) ?? false
        homeSectionSchemaVersion = try container.decodeIfPresent(Int.self, forKey: .homeSectionSchemaVersion) ?? 0
        if let bedtimeSchedule = try container.decodeIfPresent(BedtimeSchedule.self, forKey: .bedtimeSchedule) {
            self.bedtimeSchedule = bedtimeSchedule
        } else {
            let legacy = try container.decodeIfPresent(DateComponents.self, forKey: .targetBedtime)
            self.bedtimeSchedule = BedtimeSchedule.uniform(legacy ?? DateComponents(hour: 23, minute: 30))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(defaultMealSlots, forKey: .defaultMealSlots)
        try container.encode(bedtimeSchedule, forKey: .bedtimeSchedule)
        try container.encode(locationPermissionState, forKey: .locationPermissionState)
        try container.encode(appearanceMode, forKey: .appearanceMode)
        try container.encode(analyticsCustomization, forKey: .analyticsCustomization)
        try container.encode(healthKitSyncEnabled, forKey: .healthKitSyncEnabled)
        try container.encode(appLanguage, forKey: .appLanguage)
        try container.encode(timeDisplayMode, forKey: .timeDisplayMode)
        try container.encode(temperatureUnit, forKey: .temperatureUnit)
        try container.encode(midnightMode, forKey: .midnightMode)
        try container.encode(visibleHomeSections, forKey: .visibleHomeSections)
        try container.encode(showMasturbationOption, forKey: .showMasturbationOption)
        try container.encode(homeSectionSchemaVersion, forKey: .homeSectionSchemaVersion)
    }
}

struct MidnightModeSettings: Codable, Equatable {
    static let fixedCutoffHour = 4

    var isEnabled: Bool = false
    var cutoffHour: Int = MidnightModeSettings.fixedCutoffHour
    var effectiveFrom: Date?

    static let `default` = MidnightModeSettings()

    init(isEnabled: Bool = false, cutoffHour: Int = MidnightModeSettings.fixedCutoffHour, effectiveFrom: Date? = nil) {
        self.isEnabled = isEnabled
        self.cutoffHour = cutoffHour
        self.effectiveFrom = effectiveFrom
    }

    var appliesRetroactively: Bool {
        isEnabled && effectiveFrom == nil
    }

    func applies(to timestamp: Date) -> Bool {
        guard isEnabled else { return false }
        guard let effectiveFrom else { return true }
        return timestamp >= effectiveFrom
    }

    func logicalDate(for timestamp: Date, timeZone: TimeZone = .autoupdatingCurrent, calendar: Calendar = .current) -> Date {
        var adjustedCalendar = calendar
        adjustedCalendar.timeZone = timeZone
        var logicalDay = adjustedCalendar.startOfDay(for: timestamp)
        guard applies(to: timestamp) else { return logicalDay }
        if adjustedCalendar.component(.hour, from: timestamp) < MidnightModeSettings.fixedCutoffHour {
            logicalDay = adjustedCalendar.date(byAdding: .day, value: -1, to: logicalDay) ?? logicalDay
        }
        return logicalDay
    }
}

extension UserPreferences {
    func logicalDate(for timestamp: Date, timeZoneIdentifier: String? = nil, fallbackTimeZone: TimeZone = .autoupdatingCurrent) -> Date {
        let timeZone = TimeZone(identifier: timeZoneIdentifier ?? "") ?? fallbackTimeZone
        return midnightMode.logicalDate(for: timestamp, timeZone: timeZone)
    }

    func storageKey(for timestamp: Date, timeZoneIdentifier: String? = nil, fallbackTimeZone: TimeZone = .autoupdatingCurrent) -> String {
        let timeZone = TimeZone(identifier: timeZoneIdentifier ?? "") ?? fallbackTimeZone
        let logicalDay = midnightMode.logicalDate(for: timestamp, timeZone: timeZone)
        return logicalDay.storageKey(in: timeZone)
    }

    func currentLogicalDate(now: Date = .now, timeZone: TimeZone = .autoupdatingCurrent) -> Date {
        midnightMode.logicalDate(for: now, timeZone: timeZone)
    }
}

extension SleepRecord {
    var hasSleepData: Bool {
        bedtimePreviousNight != nil || wakeTimeCurrentDay != nil || !stageIntervals.isEmpty
    }

    var recordedInterval: DateInterval? {
        if let bedtimePreviousNight, let wakeTimeCurrentDay, wakeTimeCurrentDay > bedtimePreviousNight {
            return DateInterval(start: bedtimePreviousNight, end: wakeTimeCurrentDay)
        }

        let stageStart = stageIntervals.map(\.start).min()
        let stageEnd = stageIntervals.map(\.end).max()
        guard let stageStart, let stageEnd, stageEnd > stageStart else { return nil }
        return DateInterval(start: stageStart, end: stageEnd)
    }

    var hasUserEnteredSleepData: Bool {
        hasSleepData
    }

    var blocksHealthKitSync: Bool {
        source == .manual && hasUserEnteredSleepData
    }

    var needsRecordedTimeZoneMigration: Bool {
        hasUserEnteredSleepData && timeZoneIdentifier == nil
    }

    func backfillingRecordedTimeZone(_ identifier: String) -> SleepRecord {
        guard needsRecordedTimeZoneMigration else { return self }
        var updated = self
        updated.timeZoneIdentifier = identifier
        return updated
    }
}

extension MealEntry {
    var needsRecordedTimeZoneMigration: Bool {
        time != nil && timeZoneIdentifier == nil && travelContext == nil
    }

    func backfillingRecordedTimeZone(_ identifier: String) -> MealEntry {
        guard needsRecordedTimeZoneMigration else { return self }
        var updated = self
        updated.timeZoneIdentifier = identifier
        return updated
    }
}

extension ShowerEntry {
    var needsRecordedTimeZoneMigration: Bool {
        time != nil && timeZoneIdentifier == nil && travelContext == nil
    }

    func backfillingRecordedTimeZone(_ identifier: String) -> ShowerEntry {
        guard needsRecordedTimeZoneMigration else { return self }
        var updated = self
        updated.timeZoneIdentifier = identifier
        return updated
    }
}

extension SunTimes {
    var needsRecordedTimeZoneMigration: Bool {
        timeZoneIdentifier == nil
    }

    func backfillingRecordedTimeZone(_ identifier: String) -> SunTimes {
        guard needsRecordedTimeZoneMigration else { return self }
        var updated = self
        updated.timeZoneIdentifier = identifier
        return updated
    }
}

extension BowelMovementEntry {
    var needsRecordedTimeZoneMigration: Bool {
        time != nil && timeZoneIdentifier == nil && travelContext == nil
    }

    func backfillingRecordedTimeZone(_ identifier: String) -> BowelMovementEntry {
        guard needsRecordedTimeZoneMigration else { return self }
        var updated = self
        updated.timeZoneIdentifier = identifier
        return updated
    }
}

extension SexualActivityEntry {
    var needsRecordedTimeZoneMigration: Bool {
        time != nil && timeZoneIdentifier == nil && travelContext == nil
    }

    func backfillingRecordedTimeZone(_ identifier: String) -> SexualActivityEntry {
        guard needsRecordedTimeZoneMigration else { return self }
        var updated = self
        updated.timeZoneIdentifier = identifier
        return updated
    }
}

extension DailyRecord {
    var effectiveModifiedAt: Date {
        modifiedAt ?? date.startOfDay
    }

    var needsRecordedTimeZoneMigration: Bool {
        sleepRecord.needsRecordedTimeZoneMigration
            || meals.contains(where: \.needsRecordedTimeZoneMigration)
            || showers.contains(where: \.needsRecordedTimeZoneMigration)
            || bowelMovements.contains(where: \.needsRecordedTimeZoneMigration)
            || sexualActivities.contains(where: \.needsRecordedTimeZoneMigration)
            || sunTimes?.needsRecordedTimeZoneMigration == true
    }

    func backfillingRecordedTimeZones(_ identifier: String) -> DailyRecord {
        var updated = self
        updated.sleepRecord = sleepRecord.backfillingRecordedTimeZone(identifier)
        updated.meals = meals.map { $0.backfillingRecordedTimeZone(identifier) }
        updated.showers = showers.map { $0.backfillingRecordedTimeZone(identifier) }
        updated.bowelMovements = bowelMovements.map { $0.backfillingRecordedTimeZone(identifier) }
        updated.sexualActivities = sexualActivities.map { $0.backfillingRecordedTimeZone(identifier) }
        updated.sunTimes = sunTimes?.backfillingRecordedTimeZone(identifier)
        return updated
    }

    func anchoredToStorageKey(_ key: String, calendar: Calendar = .current) -> DailyRecord {
        guard let anchoredDate = Date.fromStorageKey(key, calendar: calendar) else { return self }
        var updated = self
        updated.date = anchoredDate
        return updated
    }

    func canonicalStorageKey(using preferences: UserPreferences, fallback fallbackKey: String? = nil) -> String {
        let fallbackKey = fallbackKey ?? date.storageKey()
        let candidates = inferredStorageKeyCandidates(using: preferences)
        guard !candidates.isEmpty else { return fallbackKey }

        let counts = Dictionary(candidates.map { ($0, 1) }, uniquingKeysWith: +)
        let bestCount = counts.values.max() ?? 0
        let bestKeys = counts
            .filter { $0.value == bestCount }
            .map(\.key)
            .sorted()

        if bestKeys.contains(fallbackKey) {
            return fallbackKey
        }
        return bestKeys.first ?? fallbackKey
    }

    func canonicalStorageKey(fallback fallbackKey: String? = nil) -> String {
        canonicalStorageKey(using: UserPreferences(), fallback: fallbackKey)
    }

    private func inferredStorageKeyCandidates(using preferences: UserPreferences) -> [String] {
        var candidates: [String] = []

        if let wakeTime = sleepRecord.wakeTimeCurrentDay {
            candidates.append(preferences.storageKey(for: wakeTime, timeZoneIdentifier: sleepRecord.timeZoneIdentifier))
        }

        candidates += meals.compactMap {
            guard let time = $0.time else { return nil }
            return preferences.storageKey(for: time, timeZoneIdentifier: $0.timeZoneIdentifier)
        }

        candidates += showers.compactMap {
            guard let time = $0.time else { return nil }
            return preferences.storageKey(for: time, timeZoneIdentifier: $0.timeZoneIdentifier)
        }

        candidates += bowelMovements.compactMap {
            guard let time = $0.time else { return nil }
            return preferences.storageKey(for: time, timeZoneIdentifier: $0.timeZoneIdentifier)
        }

        candidates += sexualActivities.map { entry in
            if let time = entry.time {
                return preferences.storageKey(for: time, timeZoneIdentifier: entry.timeZoneIdentifier)
            }
            return entry.date.storageKey()
        }

        if let sunrise = sunTimes?.sunrise {
            candidates.append(preferences.storageKey(for: sunrise, timeZoneIdentifier: sunTimes?.timeZoneIdentifier))
        }

        return candidates
    }

    func mergedPreservingSupplementalContent(
        with other: DailyRecord,
        preferences _: UserPreferences
    ) -> DailyRecord {
        let preferred = DailyRecord.preferredRecord(between: self, and: other)
        let supplemental = preferred == self ? other : self
        let supplementalIsOlder = preferred.effectiveModifiedAt > supplemental.effectiveModifiedAt
        var merged = preferred

        merged.sleepRecord = DailyRecord.mergedSleepRecord(
            preferred: preferred.sleepRecord,
            supplemental: supplemental.sleepRecord
        )
        merged.meals = DailyRecord.mergedMeals(
            preferred: preferred.meals,
            supplemental: supplemental.meals,
            requiresTravelContext: supplementalIsOlder
        )
        merged.showers = DailyRecord.mergedShowers(
            preferred: preferred.showers,
            supplemental: supplemental.showers,
            requiresTravelContext: supplementalIsOlder
        )
        merged.bowelMovements = DailyRecord.mergedBowelMovements(
            preferred: preferred.bowelMovements,
            supplemental: supplemental.bowelMovements,
            requiresTravelContext: supplementalIsOlder
        )
        merged.sexualActivities = DailyRecord.mergedSexualActivities(
            preferred: preferred.sexualActivities,
            supplemental: supplemental.sexualActivities,
            requiresTravelContext: supplementalIsOlder
        )

        if merged.dailyVideo == nil {
            merged.dailyVideo = supplemental.dailyVideo
        }
        if merged.locationName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            merged.locationName = supplemental.locationName
        }
        if merged.sunTimes == nil {
            merged.sunTimes = supplemental.sunTimes
        }
        if merged.weatherSnapshot == nil {
            merged.weatherSnapshot = supplemental.weatherSnapshot
        }
        if merged.aiInsightNarrative == nil {
            merged.aiInsightNarrative = supplemental.aiInsightNarrative
        }
        merged.modifiedAt = DailyRecord.latestModifiedAt(preferred.modifiedAt, supplemental.modifiedAt)
        return merged.anchoredToStorageKey(preferred.date.storageKey())
    }

    static func preferredRecord(between lhs: DailyRecord, and rhs: DailyRecord) -> DailyRecord {
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

    static func completenessScore(for record: DailyRecord) -> Int {
        var score = 0
        if record.sleepRecord.bedtimePreviousNight != nil { score += 2 }
        if record.sleepRecord.wakeTimeCurrentDay != nil { score += 2 }
        if record.sleepRecord.note?.isEmpty == false { score += 1 }
        score += record.sleepRecord.stageIntervals.count * 2
        score += record.showers.count
        score += record.bowelMovements.count
        score += record.sexualActivities.count
        if record.dailyVideo != nil { score += 1 }

        for meal in record.meals {
            switch meal.status {
            case .logged: score += 2
            case .skipped: score += 1
            case .empty: break
            }
            if meal.time != nil { score += 1 }
            if meal.hasPhoto { score += 1 }
            if meal.note?.isEmpty == false { score += 1 }
            if meal.locationName?.isEmpty == false { score += 1 }
        }

        if record.aiInsightNarrative?.hasAIScoring == true { score += 2 }
        if record.locationName?.isEmpty == false { score += 1 }
        if record.sunTimes != nil { score += 1 }
        if record.weatherSnapshot != nil { score += 1 }
        return score
    }

    private static func mergedSleepRecord(
        preferred: SleepRecord,
        supplemental: SleepRecord
    ) -> SleepRecord {
        guard preferred.hasSleepData || preferred.note?.isEmpty == false else {
            return supplemental.hasSleepData || supplemental.note?.isEmpty == false ? supplemental : preferred
        }

        var merged = preferred
        if merged.bedtimePreviousNight == nil {
            merged.bedtimePreviousNight = supplemental.bedtimePreviousNight
        }
        if merged.wakeTimeCurrentDay == nil {
            merged.wakeTimeCurrentDay = supplemental.wakeTimeCurrentDay
        }
        if merged.stageIntervals.isEmpty {
            merged.stageIntervals = supplemental.stageIntervals
        }
        if merged.timeZoneIdentifier == nil {
            merged.timeZoneIdentifier = supplemental.timeZoneIdentifier
        }
        if merged.note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            merged.note = supplemental.note
        }
        if merged.targetBedtime == nil {
            merged.targetBedtime = supplemental.targetBedtime
        }
        return merged
    }

    private static func mergedMeals(
        preferred: [MealEntry],
        supplemental: [MealEntry],
        requiresTravelContext: Bool
    ) -> [MealEntry] {
        var merged = preferred

        for meal in supplemental where meal.hasMeaningfulRecordContent {
            guard !requiresTravelContext || meal.travelContext != nil else {
                continue
            }
            if merged.contains(where: { $0.id == meal.id }) {
                continue
            }
            if let conflictKey = nonTravelMealConflictKey(for: meal),
               merged.contains(where: { nonTravelMealConflictKey(for: $0) == conflictKey }) {
                continue
            }
            merged.append(meal)
        }

        return merged
    }

    private static func mergedShowers(
        preferred: [ShowerEntry],
        supplemental: [ShowerEntry],
        requiresTravelContext: Bool
    ) -> [ShowerEntry] {
        var merged = preferred
        for entry in supplemental where (!requiresTravelContext || entry.travelContext != nil)
            && !merged.contains(where: { $0.id == entry.id }) {
            merged.append(entry)
        }
        return merged
    }

    private static func mergedBowelMovements(
        preferred: [BowelMovementEntry],
        supplemental: [BowelMovementEntry],
        requiresTravelContext: Bool
    ) -> [BowelMovementEntry] {
        var merged = preferred
        for entry in supplemental where (!requiresTravelContext || entry.travelContext != nil)
            && !merged.contains(where: { $0.id == entry.id }) {
            merged.append(entry)
        }
        return merged
    }

    private static func mergedSexualActivities(
        preferred: [SexualActivityEntry],
        supplemental: [SexualActivityEntry],
        requiresTravelContext: Bool
    ) -> [SexualActivityEntry] {
        var merged = preferred
        for entry in supplemental where (!requiresTravelContext || entry.travelContext != nil)
            && !merged.contains(where: { $0.id == entry.id }) {
            merged.append(entry)
        }
        return merged
    }

    private static func nonTravelMealConflictKey(for meal: MealEntry) -> String? {
        guard meal.travelContext == nil else { return nil }
        switch meal.mealKind {
        case .breakfast, .lunch, .dinner:
            return meal.mealKind.rawValue
        case .custom:
            guard let title = meal.customTitle?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current),
                  !title.isEmpty else {
                return nil
            }
            return "custom:\(title)"
        }
    }

    private static func latestModifiedAt(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            return max(lhs, rhs)
        case let (lhs?, nil):
            return lhs
        case let (nil, rhs?):
            return rhs
        case (nil, nil):
            return nil
        }
    }
}

private extension MealEntry {
    var hasMeaningfulRecordContent: Bool {
        status != .empty
            || time != nil
            || hasPhoto
            || note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || locationName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || latitude != nil
            || longitude != nil
            || travelContext != nil
    }
}

enum AnalyticsMetricKind: String, Codable, CaseIterable, Identifiable {
    case averageSleep
    case averageWake
    case averageBedtime
    case mealCompletion
    case averageShowers
    case averageBowelMovements
    case averageSexualActivity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .averageSleep: NSLocalizedString("平均睡眠", comment: "")
        case .averageWake: NSLocalizedString("平均起床", comment: "")
        case .averageBedtime: NSLocalizedString("平均入睡", comment: "")
        case .mealCompletion: NSLocalizedString("三餐完成率", comment: "")
        case .averageShowers: NSLocalizedString("平均洗澡", comment: "")
        case .averageBowelMovements: NSLocalizedString("平均排便", comment: "")
        case .averageSexualActivity: NSLocalizedString("性生活频率", comment: "")
        }
    }

    var requiredSection: HomeSectionKind? {
        switch self {
        case .averageSleep, .averageWake, .averageBedtime: .sleep
        case .mealCompletion: .meals
        case .averageShowers: .showers
        case .averageBowelMovements: .bowelMovements
        case .averageSexualActivity: .sexualActivity
        }
    }
}

enum AnalyticsWidgetKind: String, Codable, CaseIterable, Identifiable {
    case sleepTrend
    case sleepDuration
    case wakeTrend
    case bedtimeTrend
    case lightSleepTrend
    case deepSleepTrend
    case remSleepTrend
    case mealCompletion
    case mealTiming
    case showerTiming
    case bowelMovementTiming
    case sexualActivityFrequency
    case habitFrequencyCalendar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sleepTrend: NSLocalizedString("睡眠总时长", comment: "")
        case .sleepDuration: NSLocalizedString("平均睡眠", comment: "")
        case .wakeTrend: NSLocalizedString("起床时间", comment: "")
        case .bedtimeTrend: NSLocalizedString("入睡时间", comment: "")
        case .lightSleepTrend: NSLocalizedString("浅睡时长", comment: "")
        case .deepSleepTrend: NSLocalizedString("深睡时长", comment: "")
        case .remSleepTrend: NSLocalizedString("REM 时长", comment: "")
        case .mealCompletion: NSLocalizedString("三餐完成率", comment: "")
        case .mealTiming: NSLocalizedString("进餐时间", comment: "")
        case .showerTiming: NSLocalizedString("洗澡时间", comment: "")
        case .bowelMovementTiming: NSLocalizedString("排便时间", comment: "")
        case .sexualActivityFrequency: NSLocalizedString("性生活频率", comment: "")
        case .habitFrequencyCalendar: NSLocalizedString("频率月历", comment: "")
        }
    }

    var requiredSection: HomeSectionKind? {
        switch self {
        case .sleepTrend, .sleepDuration, .wakeTrend, .bedtimeTrend,
             .lightSleepTrend, .deepSleepTrend, .remSleepTrend: .sleep
        case .mealCompletion, .mealTiming: .meals
        case .showerTiming: .showers
        case .bowelMovementTiming: .bowelMovements
        case .sexualActivityFrequency: .sexualActivity
        case .habitFrequencyCalendar: nil
        }
    }
}

struct AnalyticsCustomization: Codable, Equatable {
    var visibleMetrics: [AnalyticsMetricKind]
    var visibleWidgets: [AnalyticsWidgetKind]

    static let `default` = AnalyticsCustomization(
        visibleMetrics: [
            .averageSleep,
            .averageWake,
            .averageBedtime,
            .mealCompletion,
            .averageShowers
        ],
        visibleWidgets: [.sleepTrend]
    )
}

enum AnalyticsRange: String, Codable, CaseIterable, Identifiable {
    case week
    case month
    case quarter
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: NSLocalizedString("7天", comment: "")
        case .month: NSLocalizedString("30天", comment: "")
        case .quarter: NSLocalizedString("90天", comment: "")
        case .custom: NSLocalizedString("自定义", comment: "")
        }
    }

    var dayCount: Int {
        switch self {
        case .week: 7
        case .month: 30
        case .quarter: 90
        case .custom: 30
        }
    }
}

struct AnalyticsDayPoint: Identifiable, Equatable {
    var id: Date { date }
    var date: Date
    var sleepHours: Double?
    var bedtimeMinutes: Double?
    var wakeMinutes: Double?
    var sleepStartMinutes: Double?
    var sleepEndMinutes: Double?
    var loggedMeals: Int
    var trackedMeals: Int
    var showers: Int
    var lightSleepHours: Double?
    var deepSleepHours: Double?
    var remSleepHours: Double?
    var awakeSleepHours: Double?
    var bowelMovements: Int
    var sexualActivities: Int
    var sexualActivitiesMasturbation: Int
}

struct SexualActivityWeekPoint: Identifiable, Equatable {
    var id: String { weekLabel }
    var weekLabel: String
    var weekStart: Date
    var partnerCount: Int
    var masturbationCount: Int

    var totalCount: Int { partnerCount + masturbationCount }
}

struct AnalyticsScatterPoint: Identifiable, Equatable {
    var id: String
    var date: Date
    var minutes: Double
}

struct MealAnalyticsSeries: Identifiable, Equatable {
    var id: String { key }
    var key: String
    var title: String
    var showsAverage: Bool
    var completionRate: Double
    var averageMinutes: Double?
    var points: [AnalyticsScatterPoint]
}

// MARK: - Runtime Language Override

import ObjectiveC

extension Bundle {
    nonisolated(unsafe) private static var _overrideBundle: Bundle?
    nonisolated(unsafe) private static var _swizzled = false

    static func configureLanguageOverride(for language: AppLanguage) {
        if let code = language.appleLanguageCode.flatMap({ Bundle.preferredLocalizations(from: $0).first }),
           let path = Bundle.main.path(forResource: code, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            _overrideBundle = bundle
        } else {
            _overrideBundle = nil
        }
    }

    static func swizzleLocalizationIfNeeded() {
        guard !_swizzled else { return }
        _swizzled = true
        let original = class_getInstanceMethod(Bundle.self, #selector(localizedString(forKey:value:table:)))!
        let swizzled = class_getInstanceMethod(Bundle.self, #selector(_dl_localizedString(forKey:value:table:)))!
        method_exchangeImplementations(original, swizzled)
    }

    @objc private func _dl_localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let override = Bundle._overrideBundle {
            return override._dl_localizedString(forKey: key, value: value, table: tableName)
        }
        return _dl_localizedString(forKey: key, value: value, table: tableName)
    }
}

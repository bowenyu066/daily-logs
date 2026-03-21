import Foundation
import SwiftUI

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case system
    case zhHans
    case en

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: NSLocalizedString("跟随系统", comment: "")
        case .zhHans: "中文"
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
        let duration = wakeTimeCurrentDay.timeIntervalSince(bedtimePreviousNight)
        return duration > 0 ? duration : nil
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
    var photoURL: String?
    var timeZoneIdentifier: String?
    var note: String?
    var locationName: String?
    var latitude: Double?
    var longitude: Double?

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
        photoURL?.isEmpty == false
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
        case id, mealKind, customTitle, status, time, photoURL, timeZoneIdentifier
        case note, locationName, latitude, longitude
    }

    init(
        id: UUID = UUID(),
        mealKind: MealKind,
        customTitle: String? = nil,
        status: MealStatus = .empty,
        time: Date? = nil,
        photoURL: String? = nil,
        timeZoneIdentifier: String? = nil,
        note: String? = nil,
        locationName: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        self.id = id
        self.mealKind = mealKind
        self.customTitle = customTitle
        self.status = status
        self.time = time
        self.photoURL = photoURL
        self.timeZoneIdentifier = timeZoneIdentifier
        self.note = note
        self.locationName = locationName
        self.latitude = latitude
        self.longitude = longitude
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        mealKind = try container.decode(MealKind.self, forKey: .mealKind)
        customTitle = try container.decodeIfPresent(String.self, forKey: .customTitle)
        status = try container.decodeIfPresent(MealStatus.self, forKey: .status) ?? .empty
        time = try container.decodeIfPresent(Date.self, forKey: .time)
        photoURL = try container.decodeIfPresent(String.self, forKey: .photoURL)
        timeZoneIdentifier = try container.decodeIfPresent(String.self, forKey: .timeZoneIdentifier)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        locationName = try container.decodeIfPresent(String.self, forKey: .locationName)
        latitude = try container.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)
    }
}

enum HomeSectionKind: String, Codable, CaseIterable, Identifiable {
    case sunTimes
    case sleep
    case meals
    case showers
    case bowelMovements
    case sexualActivity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sunTimes: NSLocalizedString("日出日落", comment: "")
        case .sleep: NSLocalizedString("睡眠", comment: "")
        case .meals: NSLocalizedString("餐食", comment: "")
        case .showers: NSLocalizedString("洗澡", comment: "")
        case .bowelMovements: NSLocalizedString("排便", comment: "")
        case .sexualActivity: NSLocalizedString("性生活", comment: "")
        }
    }

    static let defaultVisible: [HomeSectionKind] = [.sunTimes, .sleep, .meals, .showers]
}

struct ShowerEntry: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var time: Date?
    var timeZoneIdentifier: String?
    var note: String?

    enum CodingKeys: String, CodingKey {
        case id, time, timeZoneIdentifier, note
    }

    init(
        id: UUID = UUID(),
        time: Date? = nil,
        timeZoneIdentifier: String? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.time = time
        self.timeZoneIdentifier = timeZoneIdentifier
        self.note = note
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        time = try container.decodeIfPresent(Date.self, forKey: .time)
        timeZoneIdentifier = try container.decodeIfPresent(String.self, forKey: .timeZoneIdentifier)
        note = try container.decodeIfPresent(String.self, forKey: .note)
    }
}

struct BowelMovementEntry: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var time: Date?
    var timeZoneIdentifier: String?
    var note: String?

    enum CodingKeys: String, CodingKey {
        case id, time, timeZoneIdentifier, note
    }

    init(
        id: UUID = UUID(),
        time: Date? = nil,
        timeZoneIdentifier: String? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.time = time
        self.timeZoneIdentifier = timeZoneIdentifier
        self.note = note
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        time = try container.decodeIfPresent(Date.self, forKey: .time)
        timeZoneIdentifier = try container.decodeIfPresent(String.self, forKey: .timeZoneIdentifier)
        note = try container.decodeIfPresent(String.self, forKey: .note)
    }
}

struct SexualActivityEntry: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var date: Date
    var time: Date?
    var isMasturbation: Bool = false
    var timeZoneIdentifier: String?
    var note: String?

    enum CodingKeys: String, CodingKey {
        case id, date, time, isMasturbation, timeZoneIdentifier, note
    }

    init(
        id: UUID = UUID(),
        date: Date,
        time: Date? = nil,
        isMasturbation: Bool = false,
        timeZoneIdentifier: String? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.date = date
        self.time = time
        self.isMasturbation = isMasturbation
        self.timeZoneIdentifier = timeZoneIdentifier
        self.note = note
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try container.decode(Date.self, forKey: .date)
        time = try container.decodeIfPresent(Date.self, forKey: .time)
        isMasturbation = try container.decodeIfPresent(Bool.self, forKey: .isMasturbation) ?? false
        timeZoneIdentifier = try container.decodeIfPresent(String.self, forKey: .timeZoneIdentifier)
        note = try container.decodeIfPresent(String.self, forKey: .note)
    }
}

struct DailyRecord: Codable, Equatable {
    var date: Date
    var sleepRecord: SleepRecord
    var meals: [MealEntry]
    var showers: [ShowerEntry]
    var bowelMovements: [BowelMovementEntry]
    var sexualActivities: [SexualActivityEntry]
    var sunTimes: SunTimes?
    var modifiedAt: Date?

    enum CodingKeys: String, CodingKey {
        case date, sleepRecord, meals, showers, bowelMovements, sexualActivities, sunTimes, modifiedAt
    }

    init(
        date: Date,
        sleepRecord: SleepRecord,
        meals: [MealEntry],
        showers: [ShowerEntry],
        bowelMovements: [BowelMovementEntry] = [],
        sexualActivities: [SexualActivityEntry] = [],
        sunTimes: SunTimes? = nil,
        modifiedAt: Date? = nil
    ) {
        self.date = date
        self.sleepRecord = sleepRecord
        self.meals = meals
        self.showers = showers
        self.bowelMovements = bowelMovements
        self.sexualActivities = sexualActivities
        self.sunTimes = sunTimes
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
        sunTimes = try container.decodeIfPresent(SunTimes.self, forKey: .sunTimes)
        modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt)
    }

    static func empty(for date: Date, preferences: UserPreferences) -> DailyRecord {
        DailyRecord(
            date: date.startOfDay,
            sleepRecord: SleepRecord(targetBedtime: preferences.bedtimeSchedule.target(for: date)),
            meals: preferences.defaultMealSlots.map {
                MealEntry(mealKind: $0.kind, customTitle: $0.kind == .custom ? $0.title : nil)
            },
            showers: [],
            bowelMovements: [],
            sexualActivities: [],
            sunTimes: nil
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
    var defaultMealSlots: [MealSlot] = MealSlot.defaults
    var bedtimeSchedule: BedtimeSchedule = .default
    var locationPermissionState: LocationPermissionState = .notDetermined
    var appearanceMode: AppearanceMode = .system
    var analyticsCustomization: AnalyticsCustomization = .default
    var healthKitSyncEnabled: Bool = false
    var appLanguage: AppLanguage = .system
    var timeDisplayMode: TimeDisplayMode = .recorded
    var visibleHomeSections: [HomeSectionKind] = HomeSectionKind.defaultVisible
    var showMasturbationOption: Bool = false

    enum CodingKeys: String, CodingKey {
        case defaultMealSlots
        case bedtimeSchedule
        case locationPermissionState
        case appearanceMode
        case analyticsCustomization
        case healthKitSyncEnabled
        case appLanguage
        case timeDisplayMode
        case targetBedtime
        case visibleHomeSections
        case showMasturbationOption
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
        visibleHomeSections: [HomeSectionKind] = HomeSectionKind.defaultVisible,
        showMasturbationOption: Bool = false
    ) {
        self.defaultMealSlots = defaultMealSlots
        self.bedtimeSchedule = bedtimeSchedule
        self.locationPermissionState = locationPermissionState
        self.appearanceMode = appearanceMode
        self.analyticsCustomization = analyticsCustomization
        self.healthKitSyncEnabled = healthKitSyncEnabled
        self.appLanguage = appLanguage
        self.timeDisplayMode = timeDisplayMode
        self.visibleHomeSections = visibleHomeSections
        self.showMasturbationOption = showMasturbationOption
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
        visibleHomeSections = try container.decodeIfPresent([HomeSectionKind].self, forKey: .visibleHomeSections) ?? HomeSectionKind.defaultVisible
        showMasturbationOption = try container.decodeIfPresent(Bool.self, forKey: .showMasturbationOption) ?? false
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
        try container.encode(visibleHomeSections, forKey: .visibleHomeSections)
        try container.encode(showMasturbationOption, forKey: .showMasturbationOption)
    }
}

extension SleepRecord {
    var hasSleepData: Bool {
        bedtimePreviousNight != nil || wakeTimeCurrentDay != nil || !stageIntervals.isEmpty
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
        time != nil && timeZoneIdentifier == nil
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
        time != nil && timeZoneIdentifier == nil
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
        time != nil && timeZoneIdentifier == nil
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
        time != nil && timeZoneIdentifier == nil
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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sleepTrend: NSLocalizedString("睡眠趋势", comment: "")
        case .sleepDuration: NSLocalizedString("平均睡眠", comment: "")
        case .wakeTrend: NSLocalizedString("平均起床", comment: "")
        case .bedtimeTrend: NSLocalizedString("平均入睡", comment: "")
        case .lightSleepTrend: NSLocalizedString("浅睡时长", comment: "")
        case .deepSleepTrend: NSLocalizedString("深睡时长", comment: "")
        case .remSleepTrend: NSLocalizedString("REM 时长", comment: "")
        case .mealCompletion: NSLocalizedString("三餐完成率", comment: "")
        case .mealTiming: NSLocalizedString("进餐时间", comment: "")
        case .showerTiming: NSLocalizedString("洗澡时间", comment: "")
        case .bowelMovementTiming: NSLocalizedString("排便时间", comment: "")
        case .sexualActivityFrequency: NSLocalizedString("性生活频率", comment: "")
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

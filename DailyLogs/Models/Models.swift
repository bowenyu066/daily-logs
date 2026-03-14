import Foundation

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
    var createdAt: Date
}

enum RecordSource: String, Codable, CaseIterable {
    case manual
    case healthKit
}

enum MealKind: String, Codable, CaseIterable, Identifiable {
    case breakfast
    case lunch
    case dinner
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breakfast: "早餐"
        case .lunch: "午餐"
        case .dinner: "晚餐"
        case .custom: "自定义"
        }
    }
}

enum MealStatus: String, Codable, CaseIterable {
    case empty
    case logged
    case skipped

    var title: String {
        switch self {
        case .empty: "未记录"
        case .logged: "已记录"
        case .skipped: "跳过"
        }
    }
}

struct MealSlot: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var kind: MealKind
    var title: String
    var isDefault: Bool = false

    static let defaults: [MealSlot] = [
        MealSlot(kind: .breakfast, title: "早餐", isDefault: true),
        MealSlot(kind: .lunch, title: "午餐", isDefault: true),
        MealSlot(kind: .dinner, title: "晚餐", isDefault: true)
    ]
}

struct SunTimes: Codable, Equatable {
    var sunrise: Date
    var sunset: Date
}

struct SleepRecord: Codable, Equatable {
    var bedtimePreviousNight: Date?
    var wakeTimeCurrentDay: Date?
    var targetBedtime: DateComponents?
    var source: RecordSource = .manual

    var duration: TimeInterval? {
        guard let bedtimePreviousNight, let wakeTimeCurrentDay else { return nil }
        let duration = wakeTimeCurrentDay.timeIntervalSince(bedtimePreviousNight)
        return duration > 0 ? duration : nil
    }
}

struct MealEntry: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var mealKind: MealKind
    var customTitle: String?
    var status: MealStatus = .empty
    var time: Date?
    var photoURL: String?

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

    func effectiveStatus(on recordDate: Date, relativeTo referenceDate: Date = .now) -> MealStatus {
        if time != nil || hasPhoto {
            return .logged
        }
        if status == .skipped {
            return .skipped
        }
        return recordDate.startOfDay < referenceDate.startOfDay ? .skipped : .empty
    }
}

struct ShowerEntry: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var time: Date
}

struct DailyRecord: Codable, Equatable {
    var date: Date
    var sleepRecord: SleepRecord
    var meals: [MealEntry]
    var showers: [ShowerEntry]
    var sunTimes: SunTimes?

    static func empty(for date: Date, preferences: UserPreferences) -> DailyRecord {
        DailyRecord(
            date: date.startOfDay,
            sleepRecord: SleepRecord(targetBedtime: preferences.bedtimeSchedule.target(for: date)),
            meals: preferences.defaultMealSlots.map {
                MealEntry(mealKind: $0.kind, customTitle: $0.kind == .custom ? $0.title : nil)
            },
            showers: [],
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
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
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
        case .monday: "一"
        case .tuesday: "二"
        case .wednesday: "三"
        case .thursday: "四"
        case .friday: "五"
        case .saturday: "六"
        case .sunday: "日"
        }
    }

    var title: String {
        switch self {
        case .monday: "周一"
        case .tuesday: "周二"
        case .wednesday: "周三"
        case .thursday: "周四"
        case .friday: "周五"
        case .saturday: "周六"
        case .sunday: "周日"
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

    enum CodingKeys: String, CodingKey {
        case defaultMealSlots
        case bedtimeSchedule
        case locationPermissionState
        case appearanceMode
        case analyticsCustomization
        case targetBedtime
    }

    init(
        defaultMealSlots: [MealSlot] = MealSlot.defaults,
        bedtimeSchedule: BedtimeSchedule = .default,
        locationPermissionState: LocationPermissionState = .notDetermined,
        appearanceMode: AppearanceMode = .system,
        analyticsCustomization: AnalyticsCustomization = .default
    ) {
        self.defaultMealSlots = defaultMealSlots
        self.bedtimeSchedule = bedtimeSchedule
        self.locationPermissionState = locationPermissionState
        self.appearanceMode = appearanceMode
        self.analyticsCustomization = analyticsCustomization
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultMealSlots = try container.decodeIfPresent([MealSlot].self, forKey: .defaultMealSlots) ?? MealSlot.defaults
        locationPermissionState = try container.decodeIfPresent(LocationPermissionState.self, forKey: .locationPermissionState) ?? .notDetermined
        appearanceMode = try container.decodeIfPresent(AppearanceMode.self, forKey: .appearanceMode) ?? .system
        analyticsCustomization = try container.decodeIfPresent(AnalyticsCustomization.self, forKey: .analyticsCustomization) ?? .default
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
    }
}

enum AnalyticsMetricKind: String, Codable, CaseIterable, Identifiable {
    case averageSleep
    case averageWake
    case averageBedtime
    case mealCompletion
    case averageShowers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .averageSleep: "平均睡眠"
        case .averageWake: "平均起床"
        case .averageBedtime: "平均入睡"
        case .mealCompletion: "三餐完成率"
        case .averageShowers: "平均洗澡"
        }
    }
}

enum AnalyticsWidgetKind: String, Codable, CaseIterable, Identifiable {
    case sleepTrend
    case sleepDuration
    case wakeTrend
    case bedtimeTrend
    case mealCompletion
    case mealTiming
    case showerTiming

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sleepTrend: "睡眠趋势"
        case .sleepDuration: "平均睡眠"
        case .wakeTrend: "平均起床"
        case .bedtimeTrend: "平均入睡"
        case .mealCompletion: "三餐完成率"
        case .mealTiming: "进餐时间"
        case .showerTiming: "洗澡时间"
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
        case .week: "7天"
        case .month: "30天"
        case .quarter: "90天"
        case .custom: "自定义"
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
    var completionRate: Double
    var averageMinutes: Double?
    var points: [AnalyticsScatterPoint]
}

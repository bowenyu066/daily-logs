import Foundation

extension Date {
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    func startOfDay(in timeZone: TimeZone, calendar: Calendar = .current) -> Date {
        var adjustedCalendar = calendar
        adjustedCalendar.timeZone = timeZone
        return adjustedCalendar.startOfDay(for: self)
    }

    func formattedDayTitle(locale: Locale = .autoupdatingCurrent) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("MMMMdEEEE")
        return formatter.string(from: self)
    }

    func storageKey(calendar: Calendar = .current) -> String {
        CachedFormatters.storageKeyString(from: calendar.startOfDay(for: self), calendar: calendar)
    }

    func storageKey(in timeZone: TimeZone) -> String {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        return storageKey(calendar: calendar)
    }

    func adding(days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: self) ?? self
    }

    func adding(days: Int, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: days, to: self) ?? self
    }

    func settingTime(hour: Int, minute: Int) -> Date {
        Calendar.current.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: self
        ) ?? self
    }

    func settingTime(hour: Int, minute: Int, in timeZone: TimeZone) -> Date {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let dayComponents = Calendar.current.dateComponents([.year, .month, .day], from: self)
        let components = DateComponents(
            timeZone: timeZone,
            year: dayComponents.year,
            month: dayComponents.month,
            day: dayComponents.day,
            hour: hour,
            minute: minute,
            second: 0
        )
        return calendar.date(from: components) ?? self
    }

    func anchoringCurrentClockTime(in timeZone: TimeZone = .autoupdatingCurrent) -> Date {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let currentComponents = calendar.dateComponents([.hour, .minute], from: .now)
        return settingTime(
            hour: currentComponents.hour ?? 12,
            minute: currentComponents.minute ?? 0,
            in: timeZone
        )
    }

    var isoWeekday: Int {
        let weekday = Calendar.current.component(.weekday, from: self)
        return weekday == 1 ? 7 : weekday - 1
    }

    var displayClockTime: String {
        displayClockTime(in: .autoupdatingCurrent)
    }

    func displayClockTime(in timeZone: TimeZone) -> String {
        CachedFormatters.clockTimeString(from: self, timeZone: timeZone)
    }

    func displayShortTime(in timeZone: TimeZone) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = timeZone
        return formatted(style)
    }

    var displayISO8601: String {
        CachedFormatters.iso8601String(from: self)
    }

    static func fromStorageKey(_ key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }

        var anchoredCalendar = calendar
        anchoredCalendar.timeZone = calendar.timeZone
        let components = DateComponents(
            timeZone: anchoredCalendar.timeZone,
            year: parts[0],
            month: parts[1],
            day: parts[2],
            hour: 12,
            minute: 0,
            second: 0
        )
        return anchoredCalendar.date(from: components)
    }
}

/// Storage keys, clock times and ISO timestamps are formatted thousands of times while records are
/// canonicalized and insights are built, and creating a formatter per call dominated that cost.
/// Formatters are cached per configuration; formatting with a configured formatter is thread-safe.
private enum CachedFormatters {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var dateFormatters: [String: DateFormatter] = [:]
    nonisolated(unsafe) private static var iso8601Formatter: ISO8601DateFormatter?

    static func storageKeyString(from date: Date, calendar: Calendar) -> String {
        dateFormatter(cacheKey: "storage|\(calendar.identifier)|\(calendar.timeZone.identifier)") {
            // Pinned to the identifier's zone: an autoupdating zone would follow later system changes
            // while staying cached under the old identifier.
            let timeZone = TimeZone(identifier: calendar.timeZone.identifier) ?? calendar.timeZone
            var fixedCalendar = calendar
            fixedCalendar.timeZone = timeZone
            let formatter = DateFormatter()
            formatter.calendar = fixedCalendar
            formatter.timeZone = timeZone
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter
        }
        .string(from: date)
    }

    static func clockTimeString(from date: Date, timeZone: TimeZone) -> String {
        dateFormatter(cacheKey: "clock|\(timeZone.identifier)") {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: timeZone.identifier) ?? timeZone
            formatter.dateFormat = "HH:mm"
            return formatter
        }
        .string(from: date)
    }

    static func iso8601String(from date: Date) -> String {
        lock.lock()
        defer { lock.unlock() }
        let formatter = iso8601Formatter ?? ISO8601DateFormatter()
        iso8601Formatter = formatter
        return formatter.string(from: date)
    }

    private static func dateFormatter(cacheKey: String, make: () -> DateFormatter) -> DateFormatter {
        lock.lock()
        defer { lock.unlock() }
        if let cached = dateFormatters[cacheKey] {
            return cached
        }
        let formatter = make()
        if dateFormatters.count > 64 {
            dateFormatters.removeAll()
        }
        dateFormatters[cacheKey] = formatter
        return formatter
    }
}

extension DateComponents {
    var displayTime: String {
        let calendar = Calendar.current
        let normalized = DateComponents(
            calendar: calendar,
            timeZone: TimeZone.autoupdatingCurrent,
            year: 2001,
            month: 1,
            day: 1,
            hour: hour,
            minute: minute
        )
        let date = calendar.date(from: normalized) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }

    var canonicalDisplayTime: String {
        let hour = hour ?? 0
        let minute = minute ?? 0
        return String(format: "%02d:%02d", hour, minute)
    }
}

import Foundation

extension Date {
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    func formattedDayTitle(locale: Locale = .autoupdatingCurrent) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("MMMMdEEEE")
        return formatter.string(from: self)
    }

    func storageKey(calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: calendar.startOfDay(for: self))
    }

    func storageKey(in timeZone: TimeZone) -> String {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        return storageKey(calendar: calendar)
    }

    func adding(days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: self) ?? self
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

    var isoWeekday: Int {
        let weekday = Calendar.current.component(.weekday, from: self)
        return weekday == 1 ? 7 : weekday - 1
    }

    var displayClockTime: String {
        displayClockTime(in: .autoupdatingCurrent)
    }

    func displayClockTime(in timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: self)
    }

    func displayShortTime(in timeZone: TimeZone) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = timeZone
        return formatted(style)
    }

    var displayISO8601: String {
        ISO8601DateFormatter().string(from: self)
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
}

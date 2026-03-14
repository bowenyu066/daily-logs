import Foundation

extension Date {
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    func formattedDayTitle(locale: Locale = Locale(identifier: "zh_CN")) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "M月d日 EEEE"
        return formatter.string(from: self)
    }

    func storageKey(calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: self.startOfDay)
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

    var isoWeekday: Int {
        let weekday = Calendar.current.component(.weekday, from: self)
        return weekday == 1 ? 7 : weekday - 1
    }

    var displayClockTime: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: self)
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

import Foundation

enum WeekCalendar {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    static func currentWeekStartDate(now: Date = Date(), calendar: Calendar = Self.calendar) -> String {
        let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        return yyyyMmDdFormatter.string(from: start)
    }

    static func addDays(to yyyyMmDd: String, offset: Int) -> String {
        guard let date = date(from: yyyyMmDd),
              let nextDate = calendar.date(byAdding: .day, value: offset, to: date) else {
            return yyyyMmDd
        }
        return yyyyMmDdFormatter.string(from: nextDate)
    }

    static func shortDateLabel(yyyyMmDd: String) -> String {
        guard let date = date(from: yyyyMmDd) else { return yyyyMmDd }
        return shortFormatter.string(from: date)
    }

    static func isToday(yyyyMmDd: String, today: Date = Date()) -> Bool {
        guard let date = date(from: yyyyMmDd) else { return false }
        // Use the device's local calendar for the day comparison so midnight
        // boundaries follow the user's timezone, not UTC.
        return Calendar.current.isDate(date, inSameDayAs: today)
    }

    static func isPast(yyyyMmDd: String, today: Date = Date()) -> Bool {
        guard let date = date(from: yyyyMmDd) else { return false }
        let localCal = Calendar.current
        return !localCal.isDate(date, inSameDayAs: today)
            && date < localCal.startOfDay(for: today)
    }

    static func date(from yyyyMmDd: String) -> Date? {
        yyyyMmDdFormatter.date(from: yyyyMmDd)
    }

    private static let yyyyMmDdFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let shortFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }()
}

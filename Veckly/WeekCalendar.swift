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

    static func addWeeks(to yyyyMmDd: String, offset: Int) -> String {
        guard let date = date(from: yyyyMmDd),
              let nextDate = calendar.date(byAdding: .weekOfYear, value: offset, to: date) else {
            return yyyyMmDd
        }
        return yyyyMmDdFormatter.string(from: nextDate)
    }

    /// ISO 8601 week number (1-53) for the given calendar date string. Uses an
    /// explicit ISO 8601 calendar rather than the default Gregorian calendar's
    /// `weekOfYear`, which doesn't reliably match ISO week numbering across all
    /// locales and year boundaries.
    static func weekNumber(for yyyyMmDd: String) -> Int {
        guard let date = date(from: yyyyMmDd) else { return 0 }
        var isoCalendar = Calendar(identifier: .iso8601)
        isoCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return isoCalendar.component(.weekOfYear, from: date)
    }

    static func shortDateLabel(yyyyMmDd: String) -> String {
        guard let date = date(from: yyyyMmDd) else { return yyyyMmDd }
        return shortFormatter.string(from: date)
    }

    /// "Jun 22–28" style range label spanning the 7 days of the week starting at `weekStartDate`.
    static func dateRangeLabel(weekStartDate: String) -> String {
        let endDate = addDays(to: weekStartDate, offset: 6)
        guard let start = date(from: weekStartDate), let end = date(from: endDate) else {
            return shortDateLabel(yyyyMmDd: weekStartDate)
        }
        let sameMonth = calendar.component(.month, from: start) == calendar.component(.month, from: end)
            && calendar.component(.year, from: start) == calendar.component(.year, from: end)
        if sameMonth {
            let dayFormatter = DateFormatter()
            dayFormatter.calendar = calendar
            dayFormatter.timeZone = TimeZone(secondsFromGMT: 0)
            dayFormatter.setLocalizedDateFormatFromTemplate("d")
            return "\(shortFormatter.string(from: start))–\(dayFormatter.string(from: end))"
        }
        return "\(shortFormatter.string(from: start)) – \(shortFormatter.string(from: end))"
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

    /// Formats a `Date` back to `yyyy-MM-dd` using the same UTC calendar/timezone
    /// as `date(from:)`, so round-tripping never shifts by a day for users west
    /// of UTC (a local-timezone formatter would parse/format inconsistently).
    static func string(from date: Date) -> String {
        yyyyMmDdFormatter.string(from: date)
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

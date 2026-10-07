import Foundation

// Compiled into both the app (which writes the snapshot) and the
// VecklyWidgets extension (which reads it) — see the membership exception in
// the project file. Keep it Foundation-only. The JSON shape is stored in the
// shared app group under `WidgetSnapshot.storageKey`; only ever add optional
// fields so a snapshot written by an older app still decodes.

struct WidgetMealSnapshot: Codable, Hashable {
    let date: String
    let title: String
    let minutes: Int?
    let recipeID: String

    var deepLink: URL? {
        var components = URLComponents()
        components.scheme = "veckly"
        components.host = "meal"
        components.queryItems = [
            URLQueryItem(name: "date", value: date),
            URLQueryItem(name: "recipe", value: recipeID),
        ]
        return components.url
    }
}

struct WidgetSnapshot: Codable, Equatable {
    static let appGroupID = "group.com.nimaalikhani.Veckly"
    static let storageKey = "widget.snapshot.v1"
    static let staleInterval: TimeInterval = 12 * 60 * 60

    let updatedAt: Date
    let meals: [WidgetMealSnapshot]
    let shoppingRemainingCount: Int

    func isStale(at date: Date = Date()) -> Bool {
        date.timeIntervalSince(updatedAt) > Self.staleInterval
    }
}

enum WidgetDinnerState: Equatable {
    case meals([WidgetMealSnapshot])
    case nothingPlanned
    case needsUpdate
}

enum WidgetTimeline {
    /// Upper bound on midnight entries per timeline; the snapshot never holds
    /// more than about a week and a day of dinners anyway.
    static let maxDays = 14

    /// Meal dates are absolute, so past dinners are dropped here, at render
    /// time, rather than trusting what was upcoming when the app last wrote.
    /// That makes the 12 h staleness rule unnecessary for a planned week: a
    /// dinner on the plan is still the best answer to "what's for dinner"
    /// days later, and blanking it only hid the one thing the widget is for.
    /// Staleness now only matters when there's nothing left to show — an
    /// empty snapshot is trusted as "nothing planned" for 12 h, after which
    /// (or once every known dinner has passed) the widget asks for the app.
    static func dinnerState(for snapshot: WidgetSnapshot?, at date: Date, calendar: Calendar = .current) -> WidgetDinnerState {
        guard let snapshot else { return .needsUpdate }
        let upcoming = upcomingMeals(in: snapshot, at: date, calendar: calendar)
        if !upcoming.isEmpty { return .meals(upcoming) }
        if snapshot.meals.isEmpty && !snapshot.isStale(at: date) { return .nothingPlanned }
        return .needsUpdate
    }

    static func upcomingMeals(in snapshot: WidgetSnapshot, at date: Date, calendar: Calendar = .current) -> [WidgetMealSnapshot] {
        let today = WidgetDay.string(from: date, calendar: calendar)
        return snapshot.meals.filter { WidgetDay.date(from: $0.date, calendar: calendar) != nil && $0.date >= today }
    }

    /// `now`, every local midnight up to and including the one after the
    /// last known dinner (at least the next one), and the staleness horizon
    /// (the shopping count and an empty "nothing planned" expire there).
    static func entryDates(for snapshot: WidgetSnapshot?, now: Date, calendar: Calendar = .current) -> [Date] {
        let gregorian = WidgetDay.gregorian(timeZone: calendar.timeZone)
        let lastMealDate = snapshot
            .flatMap { upcomingMeals(in: $0, at: now, calendar: calendar).last }
            .flatMap { WidgetDay.date(from: $0.date, calendar: calendar) }
        let lastMidnight = lastMealDate.flatMap { gregorian.date(byAdding: .day, value: 1, to: $0) }

        var dates = [now]
        var midnight = gregorian.startOfDay(for: now)
        for _ in 0..<maxDays {
            guard let next = gregorian.date(byAdding: .day, value: 1, to: midnight) else { break }
            midnight = next
            dates.append(midnight)
            if midnight >= (lastMidnight ?? midnight) { break }
        }
        if let staleDate = snapshot.map({ $0.updatedAt.addingTimeInterval(WidgetSnapshot.staleInterval) }),
           staleDate > now, staleDate < dates.last! {
            dates.append(staleDate)
        }
        return Array(Set(dates)).sorted()
    }
}

/// Day strings (`yyyy-MM-dd`) are machine dates: parse and format them with
/// a fixed POSIX locale and the Gregorian calendar, never the user's locale
/// or calendar (which may be Buddhist, Japanese, …), in the viewer's time zone.
enum WidgetDay {
    static func gregorian(timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    static func date(from value: String, calendar: Calendar = .current) -> Date? {
        let formatter = formatter(timeZone: calendar.timeZone)
        guard let date = formatter.date(from: value), formatter.string(from: date) == value else { return nil }
        return date
    }

    static func string(from date: Date, calendar: Calendar = .current) -> String {
        formatter(timeZone: calendar.timeZone).string(from: date)
    }

    private static func formatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = gregorian(timeZone: timeZone)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}

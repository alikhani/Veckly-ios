import Foundation
import WidgetKit

enum WidgetSnapshotBuilder {
    /// Today plus a full following week — enough for the widget to keep
    /// rolling over at midnight for a week without the app being opened
    /// (e.g. a week planned on Sunday evening).
    static let maxMeals = 8

    /// `rows` may span several weeks (the current week plus next week when
    /// it's loaded); they're ordered by date here, so callers needn't.
    static func upcomingMeals(
        from rows: [WeekDayRowViewModel],
        now: Date = Date(),
        calendar: Calendar = Calendar.current
    ) -> [WidgetMealSnapshot] {
        let today = WeekCalendar.localDateString(from: now, calendar: calendar)
        var seenDates: Set<String> = []
        return rows
            .filter { row in
                !row.isSkipped
                    && row.recipe != nil
                    && WeekCalendar.date(from: row.date) != nil
                    && row.date >= today
            }
            .sorted { $0.date < $1.date }
            .filter { seenDates.insert($0.date).inserted }
            .prefix(maxMeals)
            .compactMap { row in
                guard let recipe = row.recipe else { return nil }
                let total = [recipe.prepTimeMinutes, recipe.cookTimeMinutes].compactMap { $0 }.reduce(0, +)
                return WidgetMealSnapshot(
                    date: row.date,
                    title: recipe.title,
                    minutes: total > 0 ? total : nil,
                    recipeID: recipe.id
                )
            }
    }
}

enum WidgetSnapshotStore {
    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: WidgetSnapshot.appGroupID)
    }

    static func save(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: WidgetSnapshot.storageKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func clear() {
        defaults?.removeObject(forKey: WidgetSnapshot.storageKey)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

enum AppDeepLink: Equatable {
    case meal(date: String, recipeID: String?)
    case shopping

    init?(url: URL) {
        guard url.scheme?.lowercased() == "veckly" else { return nil }
        switch url.host?.lowercased() {
        case "meal":
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            guard let date = components?.queryItems?.first(where: { $0.name == "date" })?.value,
                  WeekCalendar.date(from: date) != nil else { return nil }
            self = .meal(
                date: date,
                recipeID: components?.queryItems?.first(where: { $0.name == "recipe" })?.value
            )
        case "shopping":
            self = .shopping
        default:
            return nil
        }
    }
}

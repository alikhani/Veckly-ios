import Foundation
import WidgetKit

struct WidgetMealSnapshot: Codable, Equatable {
    let date: String
    let title: String
    let minutes: Int?
    let recipeID: String
}

struct WidgetSnapshot: Codable, Equatable {
    static let staleInterval: TimeInterval = 12 * 60 * 60

    let updatedAt: Date
    let meals: [WidgetMealSnapshot]
    let shoppingRemainingCount: Int

    func isStale(at date: Date = Date()) -> Bool {
        date.timeIntervalSince(updatedAt) > Self.staleInterval
    }
}

enum WidgetSnapshotBuilder {
    static func upcomingMeals(
        from rows: [WeekDayRowViewModel],
        now: Date = Date(),
        calendar: Calendar = Calendar.current
    ) -> [WidgetMealSnapshot] {
        let today = WeekCalendar.localDateString(from: now, calendar: calendar)
        return rows
            .filter { row in
                !row.isSkipped
                    && row.recipe != nil
                    && WeekCalendar.date(from: row.date) != nil
                    && row.date >= today
            }
            .prefix(3)
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
    static let appGroupID = "group.com.nimaalikhani.Veckly"
    static let storageKey = "widget.snapshot.v1"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static func save(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: storageKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func clear() {
        defaults?.removeObject(forKey: storageKey)
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

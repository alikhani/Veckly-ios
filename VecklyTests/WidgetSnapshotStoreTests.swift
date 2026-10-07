import Foundation
import Testing
@testable import Veckly

struct WidgetSnapshotStoreTests {
    @Test func snapshotBecomesStaleAfterTwelveHours() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let snapshot = WidgetSnapshot(updatedAt: now, meals: [], shoppingRemainingCount: 0)

        #expect(!snapshot.isStale(at: now.addingTimeInterval(12 * 60 * 60)))
        #expect(snapshot.isStale(at: now.addingTimeInterval(12 * 60 * 60 + 1)))
    }

    @Test func parsesMealDeepLink() {
        let link = AppDeepLink(url: URL(string: "veckly://meal?date=2026-10-01&recipe=recipe-1")!)

        #expect(link == .meal(date: "2026-10-01", recipeID: "recipe-1"))
    }

    @Test func parsesShoppingDeepLinkWithoutExposingItems() {
        #expect(AppDeepLink(url: URL(string: "veckly://shopping")!) == .shopping)
    }

    @Test func rejectsInvalidMealDateAndForeignScheme() {
        #expect(AppDeepLink(url: URL(string: "veckly://meal?date=not-a-date")!) == nil)
        #expect(AppDeepLink(url: URL(string: "https://example.com/shopping")!) == nil)
    }

    @Test func upcomingMealsKeepsTheUsersLocalTodayWestOfUTC() throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-10-05T06:30:00Z"))
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))

        let meals = WidgetSnapshotBuilder.upcomingMeals(
            from: [
                day(date: "2026-10-03", title: "Yesterday"),
                day(date: "2026-10-04", title: "Tonight"),
                day(date: "2026-10-05", title: "Tomorrow"),
            ],
            now: now,
            calendar: losAngeles
        )

        #expect(meals.map(\.title) == ["Tonight", "Tomorrow"])
    }

    @Test func upcomingMealsExcludesSkippedInvalidAndPastRows() throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-10-05T12:00:00Z"))
        var stockholm = Calendar(identifier: .gregorian)
        stockholm.timeZone = try #require(TimeZone(identifier: "Europe/Stockholm"))

        let meals = WidgetSnapshotBuilder.upcomingMeals(
            from: [
                day(date: "2026-10-04", title: "Past"),
                day(date: "not-a-date", title: "Invalid"),
                day(date: "2026-10-05", title: "Skipped", isSkipped: true),
                day(date: "2026-10-05", title: "Tonight"),
                day(date: "2026-10-06", title: "Tuesday"),
                day(date: "2026-10-07", title: "Wednesday"),
                day(date: "2026-10-08", title: "Thursday"),
            ],
            now: now,
            calendar: stockholm
        )

        #expect(meals.map(\.title) == ["Tonight", "Tuesday", "Wednesday", "Thursday"])
    }

    @Test func upcomingMealsSpanIntoNextWeekSoTheWidgetSurvivesSundayMidnight() throws {
        // Sunday evening, next week already planned.
        let now = try #require(ISO8601DateFormatter().date(from: "2026-10-11T18:00:00Z"))
        var stockholm = Calendar(identifier: .gregorian)
        stockholm.timeZone = try #require(TimeZone(identifier: "Europe/Stockholm"))
        let thisWeek = (0..<7).map { offset in
            let date = WeekCalendar.addDays(to: "2026-10-05", offset: offset)
            return day(date: date, title: date)
        }
        let nextWeek = (0..<7).map { offset in
            let date = WeekCalendar.addDays(to: "2026-10-12", offset: offset)
            return day(date: date, title: date)
        }

        let meals = WidgetSnapshotBuilder.upcomingMeals(from: nextWeek + thisWeek, now: now, calendar: stockholm)

        #expect(meals.map(\.date) == ["2026-10-11"] + nextWeek.map(\.date))
    }

    private func day(date: String, title: String, isSkipped: Bool = false) -> WeekDayRowViewModel {
        let recipe = WeekSummaryRecipe(
            id: title,
            title: title,
            description: "",
            servings: 4,
            prepTimeMinutes: 10,
            cookTimeMinutes: 20,
            tags: []
        )
        return WeekDayRowViewModel(
            id: date,
            weekday: .monday,
            weekdayLabel: "Monday",
            date: date,
            dateLabel: date,
            mealTitle: title,
            detail: "",
            isToday: false,
            isEmpty: false,
            isSkipped: isSkipped,
            recipe: recipe
        )
    }
}

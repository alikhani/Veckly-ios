import Foundation
import Testing
@testable import Veckly

/// `currentWeekDayRows` feeds the home-screen widget, so it must follow the
/// current week even when its fetch lands while the user browses another week.
@MainActor
struct WeekStoreCurrentWeekRowsTests {
    private let household = Household(id: "11111111-1111-1111-1111-111111111111", name: "Test household", role: .owner)

    @Test func currentWeekFetchLandingWhileBrowsingStillUpdatesCurrentWeekRows() async throws {
        let apiClient = GatedWeekAPIClient()
        let store = WeekStore(apiClient: apiClient)
        let currentWeek = WeekCalendar.currentWeekStartDate()
        let nextWeek = WeekCalendar.addWeeks(to: currentWeek, offset: 1)
        apiClient.gatedWeekStartDate = currentWeek

        let currentLoad = Task { await store.loadCurrentWeek(household: household) }
        for _ in 0..<100 where !apiClient.isWaiting {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(apiClient.isWaiting)

        await store.loadWeek(household: household, weekStartDate: nextWeek)
        #expect(store.dayRows.first?.date == nextWeek)

        apiClient.release()
        await currentLoad.value

        #expect(store.currentWeekDayRows.first?.date == currentWeek)
        #expect(store.currentWeekDayRows.allSatisfy { $0.recipe != nil })
        // The browsed week stays on screen.
        #expect(store.dayRows.first?.date == nextWeek)
    }

    @Test func widgetDayRowsIncludeNextWeekOnceItHasBeenLoaded() async throws {
        let store = WeekStore(apiClient: GatedWeekAPIClient())
        let currentWeek = WeekCalendar.currentWeekStartDate()
        let nextWeek = WeekCalendar.addWeeks(to: currentWeek, offset: 1)

        await store.loadCurrentWeek(household: household)
        #expect(store.widgetDayRows.map(\.date) == store.currentWeekDayRows.map(\.date))

        // Planning next week, then returning to this week: next week's rows
        // come from the per-week cache.
        await store.loadWeek(household: household, weekStartDate: nextWeek)
        await store.loadCurrentWeek(household: household)

        let dates = store.widgetDayRows.map(\.date)
        #expect(dates.count == 14)
        #expect(dates.first == currentWeek)
        #expect(dates.contains(WeekCalendar.addDays(to: nextWeek, offset: 6)))
    }
}

private final class GatedWeekAPIClient: WeekStoreAPIClient, @unchecked Sendable {
    private let lock = NSLock()
    private var _gatedWeekStartDate: String?
    private var continuation: CheckedContinuation<Void, Never>?

    var gatedWeekStartDate: String? {
        get { lock.withLock { _gatedWeekStartDate } }
        set { lock.withLock { _gatedWeekStartDate = newValue } }
    }

    var isWaiting: Bool { lock.withLock { continuation != nil } }

    func release() {
        let pending = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            defer { continuation = nil }
            return continuation
        }
        pending?.resume()
    }

    func weekSummary(householdID: String, weekStartDate: String) async throws -> WeekSummary {
        if weekStartDate == gatedWeekStartDate {
            await withCheckedContinuation { pending in lock.withLock { continuation = pending } }
        }
        return WeekSummary(
            household: SummaryHousehold(id: householdID, name: "Test household"),
            weekStartDate: weekStartDate,
            updatedAt: "v0",
            days: Weekday.allCases.enumerated().map { index, weekday in
                WeekSummaryDay(
                    dayOfWeek: weekday,
                    date: WeekCalendar.addDays(to: weekStartDate, offset: index),
                    state: .planned,
                    isLocked: false,
                    recipe: WeekSummaryRecipe(id: "r\(index)", title: "Recipe \(index)", description: "", servings: 4, prepTimeMinutes: 10, cookTimeMinutes: 10, tags: [])
                )
            }
        )
    }

    func appendWeekPlanEvent(householdID: String, weekStartDate: String, userID: String, event: WeekPlanEventInput) async throws {}
    func generateWeekPlan(householdID: String, weekStartDate: String, regenerate: Bool) async throws {}
    func recipe(householdID: String, recipeID: String) async throws -> FullRecipe { throw APIError.notFound }
}

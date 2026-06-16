import Foundation
import Testing
@testable import Veckly

struct WeekViewModelMapperTests {
    @Test func mapsPlannedRecipeIntoReadableDayRow() {
        let recipe = WeekSummaryRecipe(
            id: "22222222-2222-2222-2222-222222222222",
            title: "Monday Pasta",
            description: "Fast family pasta",
            servings: 4,
            prepTimeMinutes: 10,
            cookTimeMinutes: 15,
            tags: ["weekday"]
        )
        let summary = WeekSummary(
            household: SummaryHousehold(id: "11111111-1111-1111-1111-111111111111", name: "Test household"),
            weekStartDate: "2026-06-08",
            updatedAt: nil,
            days: [
                WeekSummaryDay(dayOfWeek: .monday, date: "2026-06-08", state: .planned, recipe: recipe),
                WeekSummaryDay(dayOfWeek: .tuesday, date: "2026-06-09", state: .empty, recipe: nil),
            ]
        )
        let today = WeekCalendar.date(from: "2026-06-08")!

        let mapped = WeekViewModelMapper.map(summary: summary, today: today)

        #expect(mapped.days.first?.mealTitle == "Monday Pasta")
        #expect(mapped.days.first?.detail == "4 servings · 25 min")
        #expect(mapped.today?.id == "2026-06-08")
        #expect(mapped.days[1].mealTitle == "")
        #expect(mapped.days[1].isEmpty == true)
        #expect(mapped.days[1].isSkipped == false)
    }

    @Test func mapsSkippedDayState() {
        let summary = WeekSummary(
            household: SummaryHousehold(id: "11111111-1111-1111-1111-111111111111", name: "Test household"),
            weekStartDate: "2026-06-08",
            updatedAt: nil,
            days: [
                WeekSummaryDay(dayOfWeek: .monday, date: "2026-06-08", state: .skipped, recipe: nil),
                WeekSummaryDay(dayOfWeek: .tuesday, date: "2026-06-09", state: .empty, recipe: nil),
            ]
        )
        let today = WeekCalendar.date(from: "2026-06-08")!

        let mapped = WeekViewModelMapper.map(summary: summary, today: today)

        #expect(mapped.days[0].isSkipped == true)
        #expect(mapped.days[0].isEmpty == false)
        #expect(mapped.days[1].isSkipped == false)
        #expect(mapped.days[1].isEmpty == true)
    }

    @MainActor
    @Test func toggleSkipRollsBackDayRowWhenAPIRequestFails() async {
        let store = WeekStore(apiClient: FailingWeekStoreAPIClient())
        store.seedForUITests()

        let monday = store.dayRows.first { $0.weekday == .monday }!

        await store.toggleSkip(
            day: monday,
            household: Household(id: "11111111-1111-1111-1111-111111111111", name: "Test household", role: .owner),
            userID: "33333333-3333-3333-3333-333333333333"
        )

        let restoredMonday = store.dayRows.first { $0.weekday == .monday }!
        #expect(restoredMonday == monday)
        #expect(restoredMonday.isSkipped == false)
        #expect(restoredMonday.isEmpty == false)
        #expect(restoredMonday.recipe != nil)
        #expect(store.skippedDays.contains(.monday) == false)
        #expect(store.errorMessage == "We could not skip this day.")
    }

    @MainActor
    @Test func toggleSkipUsesSeededSkippedStateAndPlansDayInstead() async {
        let apiClient = CapturingWeekStoreAPIClient()
        let store = WeekStore(apiClient: apiClient)
        store.seedForUITests()

        let wednesday = store.dayRows.first { $0.weekday == .wednesday }!
        #expect(wednesday.isSkipped == true)
        #expect(store.skippedDays.contains(.wednesday) == true)

        await store.toggleSkip(
            day: wednesday,
            household: Household(id: "11111111-1111-1111-1111-111111111111", name: "Test household", role: .owner),
            userID: "33333333-3333-3333-3333-333333333333"
        )

        let plannedWednesday = store.dayRows.first { $0.weekday == .wednesday }!
        #expect(plannedWednesday.isSkipped == false)
        #expect(plannedWednesday.isEmpty == true)
        #expect(store.skippedDays.contains(.wednesday) == false)
        #expect(apiClient.events.count == 1)
        switch apiClient.events.first {
        case .dayUnskipped(day: .wednesday):
            break
        default:
            Issue.record("Expected dayUnskipped for Wednesday")
        }
    }

    @MainActor
    @Test func skippedOnlyWeekCountsAsContentButNotPlannedMeals() async {
        let store = WeekStore(apiClient: CapturingWeekStoreAPIClient())
        store.seedForUITests()

        let monday = store.dayRows.first { $0.weekday == .monday }!
        await store.unassignMeal(
            day: monday,
            household: Household(id: "11111111-1111-1111-1111-111111111111", name: "Test household", role: .owner),
            userID: "33333333-3333-3333-3333-333333333333"
        )

        #expect(store.hasPlannedMeals == false)
        #expect(store.hasWeekContent == true)
    }

    @MainActor
    @Test func toggleSkipUsesCurrentRowStateWhenCapturedDayIsStale() async {
        let apiClient = CapturingWeekStoreAPIClient()
        let store = WeekStore(apiClient: apiClient)
        store.seedForUITests()

        let staleWednesday = WeekDayRowViewModel(
            id: "2026-06-10",
            weekday: .wednesday,
            weekdayLabel: "Wednesday",
            dateLabel: "Jun 10",
            mealTitle: "",
            detail: "",
            isToday: false,
            isEmpty: true,
            isSkipped: false,
            recipe: nil
        )

        await store.toggleSkip(
            day: staleWednesday,
            household: Household(id: "11111111-1111-1111-1111-111111111111", name: "Test household", role: .owner),
            userID: "33333333-3333-3333-3333-333333333333"
        )

        #expect(apiClient.events.count == 1)
        switch apiClient.events.first {
        case .dayUnskipped(day: .wednesday):
            break
        default:
            Issue.record("Expected stale Wednesday row to unskip current skipped state")
        }
    }
}

private final class FailingWeekStoreAPIClient: WeekStoreAPIClient {
    func weekSummary(householdID: String, weekStartDate: String) async throws -> WeekSummary {
        throw APIError.server(statusCode: 500)
    }

    func mealFeedback(householdID: String) async throws -> [String: MealVote] {
        [:]
    }

    func appendWeekPlanEvent(
        householdID: String,
        weekStartDate: String,
        userID: String,
        event: WeekPlanEventInput
    ) async throws {
        throw APIError.server(statusCode: 500)
    }

    func generateWeekPlan(householdID: String, weekStartDate: String, regenerate: Bool) async throws {}

    func recipe(householdID: String, recipeID: String) async throws -> FullRecipe {
        throw APIError.notFound
    }

    func submitFeedback(mealID: String, vote: MealVote, household: Household) async {}

    func submitMealFeedback(householdID: String, mealID: String, vote: MealVote) async throws {}
}

private final class CapturingWeekStoreAPIClient: WeekStoreAPIClient {
    private(set) var events: [WeekPlanEventInput] = []

    func weekSummary(householdID: String, weekStartDate: String) async throws -> WeekSummary {
        throw APIError.notFound
    }

    func mealFeedback(householdID: String) async throws -> [String: MealVote] {
        [:]
    }

    func appendWeekPlanEvent(
        householdID: String,
        weekStartDate: String,
        userID: String,
        event: WeekPlanEventInput
    ) async throws {
        events.append(event)
    }

    func generateWeekPlan(householdID: String, weekStartDate: String, regenerate: Bool) async throws {}

    func recipe(householdID: String, recipeID: String) async throws -> FullRecipe {
        throw APIError.notFound
    }

    func submitMealFeedback(householdID: String, mealID: String, vote: MealVote) async throws {}
}

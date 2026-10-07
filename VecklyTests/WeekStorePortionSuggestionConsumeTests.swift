import Foundation
import Testing
@testable import Veckly

/// The backend suggests `currentServings ± 1` until the suggestion is
/// recorded in portion memory. Accepting a suggestion must therefore record
/// it *before* the week is reloaded, or the reloaded row immediately
/// suggests one more portion — and a failed memory write must not keep the
/// suggestion climbing either.
@MainActor
struct WeekStorePortionSuggestionConsumeTests {
    private let household = Household(id: "11111111-1111-1111-1111-111111111111", name: "Test household", role: .owner)
    private let userID = "33333333-3333-3333-3333-333333333333"

    @Test func acceptingADaySuggestionDoesNotImmediatelySuggestAnotherPortion() async throws {
        let apiClient = PortionMemoryAPIClient()
        let store = WeekStore(apiClient: apiClient)
        await store.loadCurrentWeek(household: household)
        let monday = try #require(store.dayRows.first { $0.weekday == .monday })
        let suggestion = try #require(monday.portionSuggestion)

        try await store.changeServings(
            day: monday, servings: suggestion.suggestedServings, household: household, userID: userID,
            viewedWeekStartDate: store.weekStartDate, consumesPortionSuggestion: true
        )

        let updated = try #require(store.dayRows.first { $0.weekday == .monday })
        #expect(updated.recipe?.servings == 5)
        #expect(updated.portionSuggestion == nil)
        #expect(apiClient.consumedRecipeIDs == ["recipe"])
    }

    @Test func aFailedMemoryWriteOnTheDaySheetDoesNotKeepClimbing() async throws {
        let apiClient = PortionMemoryAPIClient()
        apiClient.failsPortionMemory = true
        let store = WeekStore(apiClient: apiClient)
        await store.loadCurrentWeek(household: household)
        let monday = try #require(store.dayRows.first { $0.weekday == .monday })

        try await store.changeServings(
            day: monday, servings: 5, household: household, userID: userID,
            viewedWeekStartDate: store.weekStartDate, consumesPortionSuggestion: true
        )

        #expect(store.dayRows.first { $0.weekday == .monday }?.portionSuggestion == nil)
        // Still hidden after an unrelated reload this session.
        await store.refreshWeek(household: household, weekStartDate: store.weekStartDate)
        #expect(store.dayRows.first { $0.weekday == .monday }?.portionSuggestion == nil)
    }

    @Test func aFailedMemoryWriteInTheWeekBriefDoesNotKeepClimbing() async throws {
        let apiClient = PortionMemoryAPIClient()
        apiClient.failsPortionMemory = true
        let store = WeekStore(apiClient: apiClient)
        await store.loadCurrentWeek(household: household)

        let succeeded = await store.applyPortionAdjustments(
            [WeekPortionAdjustment(weekday: .monday, recipeID: "recipe", servings: 5)],
            household: household, userID: userID, weekStartDate: store.weekStartDate
        )

        #expect(succeeded)
        let monday = try #require(store.dayRows.first { $0.weekday == .monday })
        #expect(monday.recipe?.servings == 5)
        #expect(monday.portionSuggestion == nil)
    }

    @Test func plainServingsChangesLeaveTheSuggestionAlone() async throws {
        let apiClient = PortionMemoryAPIClient()
        let store = WeekStore(apiClient: apiClient)
        await store.loadCurrentWeek(household: household)
        let monday = try #require(store.dayRows.first { $0.weekday == .monday })

        try await store.changeServings(
            day: monday, servings: 3, household: household, userID: userID,
            viewedWeekStartDate: store.weekStartDate
        )

        #expect(apiClient.consumedRecipeIDs.isEmpty)
        #expect(store.dayRows.first { $0.weekday == .monday }?.portionSuggestion?.suggestedServings == 4)
    }
}

/// Mirrors the backend: Monday's recipe has "too little" history, so the
/// summary suggests `servings + 1` until portion memory records it.
private final class PortionMemoryAPIClient: WeekStoreAPIClient {
    var failsPortionMemory = false
    private var mondayServings = 4
    private(set) var consumedRecipeIDs: [String] = []

    func weekSummary(householdID: String, weekStartDate: String) async throws -> WeekSummary {
        WeekSummary(
            household: SummaryHousehold(id: householdID, name: "Test household"),
            weekStartDate: weekStartDate,
            updatedAt: nil,
            days: Weekday.allCases.enumerated().map { index, weekday in
                let date = WeekCalendar.addDays(to: weekStartDate, offset: index)
                guard weekday == .monday else {
                    return WeekSummaryDay(dayOfWeek: weekday, date: date, state: .empty, recipe: nil)
                }
                return WeekSummaryDay(
                    dayOfWeek: weekday,
                    date: date,
                    state: .planned,
                    recipe: WeekSummaryRecipe(id: "recipe", title: "Recipe", description: "", servings: mondayServings, prepTimeMinutes: 10, cookTimeMinutes: 10, tags: []),
                    portionSuggestion: consumedRecipeIDs.contains("recipe")
                        ? nil
                        : PortionSuggestion(direction: .more, suggestedServings: mondayServings + 1, evidenceCount: 3, matchingCount: 3)
                )
            }
        )
    }

    func appendWeekPlanEvent(householdID: String, weekStartDate: String, userID: String, event: WeekPlanEventInput) async throws {
        if case let .servingsChanged(day, servings) = event, day == .monday { mondayServings = servings }
    }

    func generateWeekPlan(householdID: String, weekStartDate: String, regenerate: Bool) async throws {}
    func recipe(householdID: String, recipeID: String) async throws -> FullRecipe { throw APIError.notFound }

    func updatePortionMemory(householdID: String, recipeID: String, reset: Bool) async throws {
        if failsPortionMemory { throw APIError.server(statusCode: 500) }
        consumedRecipeIDs.append(recipeID)
    }
}

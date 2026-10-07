import Foundation
import Testing
@testable import Veckly

/// Week Brief portion choices must survive generate/regenerate: they're
/// applied after the new week is in, and only to days that still hold the
/// recipe the suggestion was computed for.
@MainActor
struct WeekStorePortionAdjustmentTests {
    private let household = Household(id: "11111111-1111-1111-1111-111111111111", name: "Test household", role: .owner)
    private let userID = "33333333-3333-3333-3333-333333333333"

    @Test func appliesPortionsOnlyToDaysThatKeptTheSuggestedRecipe() async {
        let weekStartDate = WeekCalendar.currentWeekStartDate()
        // After regenerate: Monday (locked) kept "kept-recipe"; Tuesday got
        // a new recipe in place of "replaced-recipe".
        let apiClient = PortionAdjustmentAPIClient(summary: makeSummary(
            weekStartDate: weekStartDate,
            recipes: [.monday: "kept-recipe", .tuesday: "new-recipe"]
        ))
        let store = WeekStore(apiClient: apiClient)

        let succeeded = await store.applyPortionAdjustments(
            [
                WeekPortionAdjustment(weekday: .monday, recipeID: "kept-recipe", servings: 5),
                WeekPortionAdjustment(weekday: .tuesday, recipeID: "replaced-recipe", servings: 3),
            ],
            household: household,
            userID: userID,
            weekStartDate: weekStartDate
        )

        #expect(succeeded)
        #expect(store.mutationError == nil)
        #expect(apiClient.servingsEvents.count == 1)
        #expect(apiClient.servingsEvents.first?.day == .monday)
        #expect(apiClient.servingsEvents.first?.servings == 5)
        // The replaced recipe's suggestion is left unconsumed.
        #expect(apiClient.portionMemoryRecipeIDs == ["kept-recipe"])
    }

    @Test func aFailedPortionWriteSurfacesAnErrorInsteadOfSilentlyStopping() async {
        let weekStartDate = WeekCalendar.currentWeekStartDate()
        let apiClient = PortionAdjustmentAPIClient(
            summary: makeSummary(weekStartDate: weekStartDate, recipes: [.monday: "kept-recipe"]),
            failsEvents: true
        )
        let store = WeekStore(apiClient: apiClient)

        let succeeded = await store.applyPortionAdjustments(
            [WeekPortionAdjustment(weekday: .monday, recipeID: "kept-recipe", servings: 5)],
            household: household,
            userID: userID,
            weekStartDate: weekStartDate
        )

        #expect(!succeeded)
        #expect(store.mutationError == L10n.string("error.week.servings"))
        #expect(apiClient.portionMemoryRecipeIDs.isEmpty)
    }

    private func makeSummary(weekStartDate: String, recipes: [Weekday: String]) -> WeekSummary {
        WeekSummary(
            household: SummaryHousehold(id: household.id, name: "Test household"),
            weekStartDate: weekStartDate,
            updatedAt: nil,
            days: Weekday.allCases.enumerated().map { index, weekday in
                let recipe = recipes[weekday].map {
                    WeekSummaryRecipe(id: $0, title: $0, description: "", servings: 4, prepTimeMinutes: 10, cookTimeMinutes: 10, tags: [])
                }
                return WeekSummaryDay(
                    dayOfWeek: weekday,
                    date: WeekCalendar.addDays(to: weekStartDate, offset: index),
                    state: recipe == nil ? .empty : .planned,
                    recipe: recipe
                )
            }
        )
    }
}

private final class PortionAdjustmentAPIClient: WeekStoreAPIClient {
    let summary: WeekSummary
    let failsEvents: Bool
    private(set) var servingsEvents: [(day: Weekday, servings: Int)] = []
    private(set) var portionMemoryRecipeIDs: [String] = []

    init(summary: WeekSummary, failsEvents: Bool = false) {
        self.summary = summary
        self.failsEvents = failsEvents
    }

    func weekSummary(householdID: String, weekStartDate: String) async throws -> WeekSummary { summary }

    func appendWeekPlanEvent(householdID: String, weekStartDate: String, userID: String, event: WeekPlanEventInput) async throws {
        if failsEvents { throw APIError.server(statusCode: 500) }
        if case let .servingsChanged(day, servings) = event {
            servingsEvents.append((day, servings))
        }
    }

    func generateWeekPlan(householdID: String, weekStartDate: String, regenerate: Bool) async throws {}
    func recipe(householdID: String, recipeID: String) async throws -> FullRecipe { throw APIError.notFound }

    func updatePortionMemory(householdID: String, recipeID: String, reset: Bool) async throws {
        portionMemoryRecipeIDs.append(recipeID)
    }
}

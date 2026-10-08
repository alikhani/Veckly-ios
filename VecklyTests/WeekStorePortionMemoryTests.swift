import Foundation
import Testing
@testable import Veckly

/// "Not now" / "Reset learned portions" on a planned day: a successful
/// portion-memory write reloads the week (the row's suggestion is derived
/// from portion memory); a failed one reports `false` and leaves the week
/// untouched.
@MainActor
struct WeekStorePortionMemoryTests {
    private let household = Household(id: "11111111-1111-1111-1111-111111111111", name: "Test household", role: .owner)

    @Test func ignoringASuggestionRecordsItAndRefreshesTheWeek() async {
        let weekStartDate = WeekCalendar.currentWeekStartDate()
        let apiClient = PortionMemoryAPIClient(weekStartDate: weekStartDate)
        let store = WeekStore(apiClient: apiClient)

        let succeeded = await store.ignorePortionSuggestion(recipeID: "recipe-1", household: household, weekStartDate: weekStartDate)

        #expect(succeeded)
        #expect(apiClient.portionMemoryCalls.count == 1)
        #expect(apiClient.portionMemoryCalls.first?.recipeID == "recipe-1")
        #expect(apiClient.portionMemoryCalls.first?.reset == false)
        #expect(apiClient.weekSummaryRequests == [weekStartDate])
    }

    @Test func resettingPortionMemoryRecordsAResetAndRefreshesTheWeek() async {
        let weekStartDate = WeekCalendar.currentWeekStartDate()
        let apiClient = PortionMemoryAPIClient(weekStartDate: weekStartDate)
        let store = WeekStore(apiClient: apiClient)

        let succeeded = await store.resetPortionMemory(recipeID: "recipe-1", household: household, weekStartDate: weekStartDate)

        #expect(succeeded)
        #expect(apiClient.portionMemoryCalls.first?.reset == true)
        #expect(apiClient.weekSummaryRequests == [weekStartDate])
    }

    @Test func aFailedPortionMemoryWriteReturnsFalseWithoutRefreshing() async {
        let weekStartDate = WeekCalendar.currentWeekStartDate()
        let apiClient = PortionMemoryAPIClient(weekStartDate: weekStartDate, failsPortionMemory: true)
        let store = WeekStore(apiClient: apiClient)

        let ignored = await store.ignorePortionSuggestion(recipeID: "recipe-1", household: household, weekStartDate: weekStartDate)
        let reset = await store.resetPortionMemory(recipeID: "recipe-1", household: household, weekStartDate: weekStartDate)

        #expect(!ignored)
        #expect(!reset)
        #expect(apiClient.weekSummaryRequests.isEmpty)
    }
}

private final class PortionMemoryAPIClient: WeekStoreAPIClient {
    let weekStartDate: String
    let failsPortionMemory: Bool
    private(set) var portionMemoryCalls: [(recipeID: String, reset: Bool)] = []
    private(set) var weekSummaryRequests: [String] = []

    init(weekStartDate: String, failsPortionMemory: Bool = false) {
        self.weekStartDate = weekStartDate
        self.failsPortionMemory = failsPortionMemory
    }

    func weekSummary(householdID: String, weekStartDate: String) async throws -> WeekSummary {
        weekSummaryRequests.append(weekStartDate)
        return WeekSummary(
            household: SummaryHousehold(id: householdID, name: "Test household"),
            weekStartDate: weekStartDate,
            updatedAt: nil,
            days: Weekday.allCases.enumerated().map { index, weekday in
                WeekSummaryDay(
                    dayOfWeek: weekday,
                    date: WeekCalendar.addDays(to: weekStartDate, offset: index),
                    state: .empty,
                    recipe: nil
                )
            }
        )
    }

    func appendWeekPlanEvent(householdID: String, weekStartDate: String, userID: String, event: WeekPlanEventInput) async throws {}
    func generateWeekPlan(householdID: String, weekStartDate: String, regenerate: Bool) async throws {}
    func recipe(householdID: String, recipeID: String) async throws -> FullRecipe { throw APIError.notFound }

    func updatePortionMemory(householdID: String, recipeID: String, reset: Bool) async throws {
        if failsPortionMemory { throw APIError.server(statusCode: 500) }
        portionMemoryCalls.append((recipeID, reset))
    }
}

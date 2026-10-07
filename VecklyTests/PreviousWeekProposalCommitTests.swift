import Foundation
import Testing
@testable import Veckly

/// The Reuse-last-week proposal is applied server-side as a whole. "Change"
/// on one day must not throw the rest of the proposal away: it uses the plan
/// first, then opens the picker for that day.
@MainActor
struct PreviousWeekProposalCommitTests {
    private let household = Household(id: "11111111-1111-1111-1111-111111111111", name: "Test household", role: .owner)

    @Test func changingADayAppliesTheProposalBeforeOpeningThePicker() async throws {
        let apiClient = ProposalAPIClient()
        let store = WeekStore(apiClient: apiClient)
        let weekStartDate = WeekCalendar.currentWeekStartDate()
        let tuesday = WeekCalendar.addDays(to: weekStartDate, offset: 1)
        var log: [String] = []

        try await PreviousWeekProposalSheet.commit(
            makeProposal(), thenChange: tuesday,
            weekStore: store, household: household, weekStartDate: weekStartDate,
            onApplied: { log.append("applied") },
            onChangeDay: { log.append("change \($0)") }
        )

        #expect(apiClient.appliedProposalIDs == ["proposal"])
        #expect(log == ["applied", "change \(tuesday)"])
        // The picker opens against the week as it is after the proposal.
        #expect(store.dayRows.first { $0.date == tuesday }?.recipe?.id == "kept-recipe")
    }

    @Test func aStaleProposalNeitherAppliesNorOpensThePicker() async {
        let apiClient = ProposalAPIClient()
        apiClient.applyError = APIError.server(statusCode: 409)
        let store = WeekStore(apiClient: apiClient)
        let weekStartDate = WeekCalendar.currentWeekStartDate()
        var changedDays: [String] = []

        await #expect(throws: APIError.self) {
            try await PreviousWeekProposalSheet.commit(
                makeProposal(), thenChange: weekStartDate,
                weekStore: store, household: household, weekStartDate: weekStartDate,
                onApplied: {}, onChangeDay: { changedDays.append($0) }
            )
        }
        #expect(changedDays.isEmpty)
    }

    private func makeProposal() -> PreviousWeekProposal {
        PreviousWeekProposal(
            proposalID: "proposal",
            sourceWeekStartDate: WeekCalendar.addWeeks(to: WeekCalendar.currentWeekStartDate(), offset: -1),
            expectedUpdatedAt: "v0",
            keptCount: 6,
            changedCount: 1,
            days: []
        )
    }
}

private final class ProposalAPIClient: WeekStoreAPIClient {
    var applyError: Error?
    private(set) var appliedProposalIDs: [String] = []

    func weekSummary(householdID: String, weekStartDate: String) async throws -> WeekSummary {
        guard !appliedProposalIDs.isEmpty else { throw APIError.notFound }
        return WeekSummary(
            household: SummaryHousehold(id: householdID, name: "Test household"),
            weekStartDate: weekStartDate,
            updatedAt: "v1",
            days: Weekday.allCases.enumerated().map { index, weekday in
                WeekSummaryDay(
                    dayOfWeek: weekday,
                    date: WeekCalendar.addDays(to: weekStartDate, offset: index),
                    state: .planned,
                    recipe: WeekSummaryRecipe(id: "kept-recipe", title: "Kept", description: "", servings: 4, prepTimeMinutes: 10, cookTimeMinutes: 10, tags: [])
                )
            }
        )
    }

    func appendWeekPlanEvent(householdID: String, weekStartDate: String, userID: String, event: WeekPlanEventInput) async throws {}
    func generateWeekPlan(householdID: String, weekStartDate: String, regenerate: Bool) async throws {}
    func recipe(householdID: String, recipeID: String) async throws -> FullRecipe { throw APIError.notFound }

    func applyPreviousWeekProposal(
        householdID: String, weekStartDate: String, proposalID: String, expectedUpdatedAt: String?
    ) async throws {
        if let applyError { throw applyError }
        appliedProposalIDs.append(proposalID)
    }
}

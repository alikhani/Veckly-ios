import Foundation
import Testing
@testable import Veckly

/// Rescue and Reuse-last-week send `summary.updatedAt` as `expectedUpdatedAt`;
/// the backend answers 409 STALE_WEEK_PLAN when it's behind. Lock/skip writes
/// bump the server's `updatedAt`, so the store must keep its copy current.
@MainActor
struct WeekStoreStaleWeekPlanTests {
    private let household = Household(id: "11111111-1111-1111-1111-111111111111", name: "Test household", role: .owner)
    private let userID = "33333333-3333-3333-3333-333333333333"

    @Test func lockSyncRefreshesSummaryUpdatedAt() async throws {
        let apiClient = VersionedWeekAPIClient()
        let store = WeekStore(apiClient: apiClient, syncDebounceNanoseconds: 0, retryDelayNanoseconds: 60_000_000_000)
        await store.loadCurrentWeek(household: household)
        #expect(store.summary?.updatedAt == "v0")

        let monday = try #require(store.dayRows.first { $0.weekday == .monday })
        await store.toggleLock(day: monday, household: household, userID: userID)

        for _ in 0..<100 where store.summary?.updatedAt != "v1" || store.hasPendingSync {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(apiClient.eventCount == 1)
        #expect(!store.hasPendingSync)
        #expect(store.summary?.updatedAt == "v1")
        #expect(store.dayRows.first { $0.weekday == .monday }?.isLocked == true)
    }

    @Test func assignMealRefreshesSummaryUpdatedAt() async throws {
        let apiClient = VersionedWeekAPIClient()
        let store = WeekStore(apiClient: apiClient)
        await store.loadCurrentWeek(household: household)
        let monday = try #require(store.dayRows.first { $0.weekday == .monday })
        let recipe = WeekSummaryRecipe(id: "new", title: "New", description: "", servings: 4, prepTimeMinutes: 10, cookTimeMinutes: 10, tags: [])

        await store.assignMeal(day: monday, recipe: recipe, household: household, userID: userID)

        #expect(store.mutationError == nil)
        #expect(store.summary?.updatedAt == "v1")
    }

    @Test func unassignMealRefreshesSummaryUpdatedAt() async throws {
        let apiClient = VersionedWeekAPIClient()
        let store = WeekStore(apiClient: apiClient)
        await store.loadCurrentWeek(household: household)
        let monday = try #require(store.dayRows.first { $0.weekday == .monday })

        await store.unassignMeal(day: monday, household: household, userID: userID)

        #expect(store.mutationError == nil)
        #expect(store.summary?.updatedAt == "v1")
    }

    @Test func changeServingsRefreshesSummaryUpdatedAt() async throws {
        let apiClient = VersionedWeekAPIClient()
        let store = WeekStore(apiClient: apiClient)
        await store.loadCurrentWeek(household: household)
        let monday = try #require(store.dayRows.first { $0.weekday == .monday })

        try await store.changeServings(day: monday, servings: 5, household: household, userID: userID, viewedWeekStartDate: store.weekStartDate)

        #expect(store.summary?.updatedAt == "v1")
    }

    @Test func staleRescuePreviewRefreshesAndRetriesOnceWithTheCurrentVersion() async throws {
        let apiClient = VersionedWeekAPIClient()
        let store = WeekStore(apiClient: apiClient)
        await store.loadCurrentWeek(household: household)
        let monday = try #require(store.dayRows.first { $0.weekday == .monday })
        apiClient.version = 3 // someone else changed the week

        let preview = try await store.previewRescue(
            day: monday, household: household, weekStartDate: store.weekStartDate,
            intent: .quick, missingIngredient: "", rescueID: "rescue", expectedUpdatedAt: "v0"
        )

        #expect(preview.expectedUpdatedAt == "v3")
        #expect(apiClient.rescuePreviewExpectedVersions == ["v0", "v3"])
        #expect(store.summary?.updatedAt == "v3")
    }

    @Test func staleReusePreviewRefreshesAndRetriesOnceWithTheCurrentVersion() async throws {
        let apiClient = VersionedWeekAPIClient()
        let store = WeekStore(apiClient: apiClient)
        await store.loadCurrentWeek(household: household)
        apiClient.version = 2

        let proposal = try await store.previewPreviousWeek(
            household: household, weekStartDate: store.weekStartDate, proposalID: "proposal", expectedUpdatedAt: "v0"
        )

        #expect(proposal.expectedUpdatedAt == "v2")
        #expect(apiClient.proposalPreviewExpectedVersions == ["v0", "v2"])
    }
}

/// A fake backend whose week has a version that every write bumps, and whose
/// rescue/reuse previews reject a mismatched `expectedUpdatedAt` with 409 like
/// the real STALE_WEEK_PLAN check.
private final class VersionedWeekAPIClient: WeekStoreAPIClient {
    var version = 0
    private var lockedDays: Set<Weekday> = []
    private(set) var eventCount = 0
    private(set) var rescuePreviewExpectedVersions: [String?] = []
    private(set) var proposalPreviewExpectedVersions: [String?] = []

    private var updatedAt: String { "v\(version)" }

    func weekSummary(householdID: String, weekStartDate: String) async throws -> WeekSummary {
        WeekSummary(
            household: SummaryHousehold(id: householdID, name: "Test household"),
            weekStartDate: weekStartDate,
            updatedAt: updatedAt,
            days: Weekday.allCases.enumerated().map { index, weekday in
                WeekSummaryDay(
                    dayOfWeek: weekday,
                    date: WeekCalendar.addDays(to: weekStartDate, offset: index),
                    state: .planned,
                    isLocked: lockedDays.contains(weekday),
                    recipe: WeekSummaryRecipe(id: "r\(index)", title: "Recipe \(index)", description: "", servings: 4, prepTimeMinutes: 10, cookTimeMinutes: 10, tags: [])
                )
            }
        )
    }

    func appendWeekPlanEvent(householdID: String, weekStartDate: String, userID: String, event: WeekPlanEventInput) async throws {
        eventCount += 1
        if case let .mealLocked(day) = event { lockedDays.insert(day) }
        version += 1
    }

    func generateWeekPlan(householdID: String, weekStartDate: String, regenerate: Bool) async throws {}
    func recipe(householdID: String, recipeID: String) async throws -> FullRecipe { throw APIError.notFound }

    func previewWeekRescue(
        householdID: String, weekStartDate: String, date: String,
        intent: WeekRescueIntent, missingIngredient: String?, rescueID: String,
        expectedUpdatedAt: String?
    ) async throws -> WeekRescuePreview {
        rescuePreviewExpectedVersions.append(expectedUpdatedAt)
        guard expectedUpdatedAt == updatedAt else { throw APIError.server(statusCode: 409) }
        return WeekRescuePreview(
            rescueID: rescueID,
            intent: intent,
            primaryChange: WeekRescueChange(date: date, beforeTitle: "A", afterTitle: "B", beforeServings: 4, afterServings: 4),
            followUpChanges: [],
            addedShoppingItems: [],
            removedShoppingItems: [],
            expectedUpdatedAt: updatedAt
        )
    }

    func previewPreviousWeekProposal(
        householdID: String, weekStartDate: String, proposalID: String, expectedUpdatedAt: String?
    ) async throws -> PreviousWeekProposal {
        proposalPreviewExpectedVersions.append(expectedUpdatedAt)
        guard expectedUpdatedAt == updatedAt else { throw APIError.server(statusCode: 409) }
        return PreviousWeekProposal(
            proposalID: proposalID,
            sourceWeekStartDate: WeekCalendar.addWeeks(to: weekStartDate, offset: -1),
            expectedUpdatedAt: updatedAt,
            keptCount: 0,
            changedCount: 0,
            days: []
        )
    }
}

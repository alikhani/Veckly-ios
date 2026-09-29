import Foundation
import Testing
@testable import Veckly

@MainActor
struct MealOutcomeStoreTests {
    private let householdID = "11111111-1111-1111-1111-111111111111"
    private let recipeID = "22222222-2222-2222-2222-222222222222"
    private let weekStartDate = "2026-06-08"
    private let date = "2026-06-09"

    @Test func loadsOutcomesByDate() async {
        let client = StubMealOutcomeAPIClient()
        client.listResult = .success([record(status: .cooked)])
        let store = makeStore(client: client)

        await store.load(householdID: householdID, weekStartDate: weekStartDate)

        #expect(store.outcome(for: date)?.status == .cooked)
        #expect(!store.hasPendingSync)
    }

    @Test func failedWriteKeepsVisibleChoiceAndPersistsItForRetry() async {
        let client = StubMealOutcomeAPIClient()
        client.upsertError = APIError.server(statusCode: 500)
        let persistence = InMemoryMealOutcomePendingStore()
        let store = makeStore(client: client, persistence: persistence)
        await store.load(householdID: householdID, weekStartDate: weekStartDate)

        await store.setOutcome(draft(status: .changedPlan, actualMealLabel: "Takeaway"))

        #expect(store.outcome(for: date)?.status == .changedPlan)
        #expect(store.outcome(for: date)?.actualMealLabel == "Takeaway")
        #expect(store.hasPendingSync)
        #expect(store.mutationError == L10n.string("error.mealOutcome.pendingSync"))
        #expect(persistence.drafts.count == 1)
    }

    @Test func retryClearsPendingAfterSuccess() async {
        let client = StubMealOutcomeAPIClient()
        client.upsertError = APIError.server(statusCode: 500)
        let persistence = InMemoryMealOutcomePendingStore()
        let store = makeStore(client: client, persistence: persistence)
        await store.load(householdID: householdID, weekStartDate: weekStartDate)
        await store.setOutcome(draft(status: .cooked))

        client.upsertError = nil
        await store.retryPending()

        #expect(!store.hasPendingSync)
        #expect(store.mutationError == nil)
        #expect(persistence.drafts.isEmpty)
    }

    @Test func notifiesCookbookOnlyAfterAnOutcomeIsConfirmedByTheServer() async {
        let client = StubMealOutcomeAPIClient()
        client.upsertError = APIError.server(statusCode: 500)
        var syncedHouseholdIDs: [String] = []
        let store = MealOutcomeStore(
            apiClient: client,
            pendingStore: InMemoryMealOutcomePendingStore(),
            retryDelayNanoseconds: 60_000_000_000,
            didSyncOutcome: { syncedHouseholdIDs.append($0) }
        )
        await store.load(householdID: householdID, weekStartDate: weekStartDate)

        await store.setOutcome(draft(status: .cooked))
        #expect(syncedHouseholdIDs.isEmpty)

        client.upsertError = nil
        await store.retryPending()
        #expect(syncedHouseholdIDs == [householdID])
    }

    @Test func pendingChoiceSurvivesANewStoreInstanceAndWinsOverServerState() async {
        let persistence = InMemoryMealOutcomePendingStore()
        let offlineClient = StubMealOutcomeAPIClient()
        offlineClient.upsertError = APIError.server(statusCode: 500)
        let firstStore = makeStore(client: offlineClient, persistence: persistence)
        await firstStore.load(householdID: householdID, weekStartDate: weekStartDate)
        await firstStore.setOutcome(draft(status: .changedPlan))

        let onlineClient = StubMealOutcomeAPIClient()
        onlineClient.listResult = .success([record(status: .skipped)])
        let restoredStore = makeStore(client: onlineClient, persistence: persistence)
        await restoredStore.load(householdID: householdID, weekStartDate: weekStartDate)

        #expect(restoredStore.outcome(for: date)?.status == .changedPlan)
        #expect(!restoredStore.hasPendingSync)
        #expect(onlineClient.upsertedDrafts.map(\.status) == [.changedPlan])
    }

    @Test func switchingHouseholdsClearsThePreviousHouseholdsVisibleOutcomesEvenWhenLoadFails() async {
        let client = StubMealOutcomeAPIClient()
        client.listResult = .success([record(status: .cooked)])
        let store = makeStore(client: client)
        await store.load(householdID: householdID, weekStartDate: weekStartDate)
        #expect(store.outcome(for: date)?.status == .cooked)

        client.listResult = .failure(APIError.server(statusCode: 500))
        await store.load(
            householdID: "33333333-3333-3333-3333-333333333333",
            weekStartDate: weekStartDate
        )

        #expect(store.outcome(for: date) == nil)
        #expect(store.errorMessage == L10n.string("error.mealOutcome.load"))
    }

    @Test func newerChangeForTheSameDateWinsWhileOlderRequestIsInFlight() async throws {
        let client = StubMealOutcomeAPIClient()
        client.upsertDelayNanoseconds = 50_000_000
        let store = makeStore(client: client)
        await store.load(householdID: householdID, weekStartDate: weekStartDate)

        let first = Task { await store.setOutcome(draft(status: .cooked)) }
        try await Task.sleep(nanoseconds: 10_000_000)
        let second = Task { await store.setOutcome(draft(status: .skipped)) }
        await first.value
        await second.value

        #expect(store.outcome(for: date)?.status == .skipped)
        #expect(client.upsertedDrafts.map(\.status) == [.cooked, .skipped])
        #expect(!store.hasPendingSync)
    }

    @Test func normalizedDraftClearsFieldsTheBackendDoesNotAllow() {
        let skipped = draft(status: .skipped, actualMealLabel: "Pizza", portion: .tooMuch).normalized()
        #expect(skipped.portionOutcome == nil)
        #expect(skipped.actualMealLabel == nil)

        let cooked = draft(status: .cooked, actualMealLabel: "Pizza").normalized()
        #expect(cooked.actualMealLabel == nil)
    }

    private func makeStore(
        client: StubMealOutcomeAPIClient,
        persistence: InMemoryMealOutcomePendingStore = InMemoryMealOutcomePendingStore()
    ) -> MealOutcomeStore {
        MealOutcomeStore(apiClient: client, pendingStore: persistence, retryDelayNanoseconds: 60_000_000_000)
    }

    private func draft(
        status: MealOutcomeStatus,
        actualMealLabel: String? = nil,
        portion: MealPortionOutcome? = nil
    ) -> MealOutcomeDraft {
        MealOutcomeDraft(
            householdID: householdID,
            weekStartDate: weekStartDate,
            date: date,
            plannedRecipeID: recipeID,
            status: status,
            portionOutcome: portion,
            reason: nil,
            actualRecipeID: nil,
            actualMealLabel: actualMealLabel
        )
    }

    private func record(status: MealOutcomeStatus) -> MealOutcomeRecord {
        MealOutcomeRecord(draft: draft(status: status), updatedAt: "2026-06-10T12:00:00.000Z")
    }
}

private final class InMemoryMealOutcomePendingStore: MealOutcomePendingPersisting {
    var drafts: [MealOutcomeDraft] = []

    func load() -> [MealOutcomeDraft] { drafts }
    func save(_ drafts: [MealOutcomeDraft]) { self.drafts = drafts }
    func delete() { drafts = [] }
}

private final class StubMealOutcomeAPIClient: MealOutcomeStoreAPIClient {
    var listResult: Result<[MealOutcomeRecord], Error> = .success([])
    var upsertError: Error?
    var upsertDelayNanoseconds: UInt64 = 0
    private(set) var upsertedDrafts: [MealOutcomeDraft] = []

    func mealOutcomes(householdID: String, weekStartDate: String) async throws -> [MealOutcomeRecord] {
        try listResult.get()
    }

    func upsertMealOutcome(_ draft: MealOutcomeDraft) async throws -> MealOutcomeRecord {
        upsertedDrafts.append(draft)
        if upsertDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: upsertDelayNanoseconds)
        }
        if let upsertError { throw upsertError }
        return MealOutcomeRecord(draft: draft, updatedAt: "2026-06-10T12:00:00.000Z")
    }
}

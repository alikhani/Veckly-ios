import Foundation
import Testing
@testable import Veckly

@MainActor
struct PrepBatchStoreTests {
    @Test func changingWeekReloadsPrepBatchesEvenInsideCacheTTL() async {
        let apiClient = FakePrepBatchStoreAPIClient()
        let store = PrepBatchStore(apiClient: apiClient, cacheStore: FakePrepBatchStoreCache())

        await store.load(householdID: TestPrepBatchFixtures.householdID, weekStartDate: TestPrepBatchFixtures.firstWeek)
        await store.load(householdID: TestPrepBatchFixtures.householdID, weekStartDate: TestPrepBatchFixtures.secondWeek)

        #expect(apiClient.requests.count == 2)
        #expect(apiClient.requests.map(\.from) == [TestPrepBatchFixtures.firstWeek, TestPrepBatchFixtures.secondWeek])
        #expect(store.batches == [TestPrepBatchFixtures.secondWeekBatch])
        #expect(store.weekStartDate == TestPrepBatchFixtures.secondWeek)
    }

    @Test func changingHouseholdReloadsPrepBatchesEvenInsideCacheTTL() async {
        let apiClient = FakePrepBatchStoreAPIClient()
        let store = PrepBatchStore(apiClient: apiClient, cacheStore: FakePrepBatchStoreCache())

        await store.load(householdID: TestPrepBatchFixtures.householdID, weekStartDate: TestPrepBatchFixtures.firstWeek)
        await store.load(householdID: TestPrepBatchFixtures.otherHouseholdID, weekStartDate: TestPrepBatchFixtures.firstWeek)

        #expect(apiClient.requests.count == 2)
        #expect(apiClient.requests.map(\.householdID) == [TestPrepBatchFixtures.householdID, TestPrepBatchFixtures.otherHouseholdID])
        #expect(store.batches == [TestPrepBatchFixtures.otherHouseholdBatch])
        #expect(store.householdID == TestPrepBatchFixtures.otherHouseholdID)
    }

    @Test func persistedBatchesAreUsedWithoutANetworkReloadWhileFresh() async {
        let apiClient = FakePrepBatchStoreAPIClient()
        let cacheStore = FakePrepBatchStoreCache(
            caches: [
                "\(TestPrepBatchFixtures.householdID)|\(TestPrepBatchFixtures.firstWeek)": PersistedPrepBatchCache(
                    householdID: TestPrepBatchFixtures.householdID,
                    weekStartDate: TestPrepBatchFixtures.firstWeek,
                    fetchedAt: Date(),
                    batches: [PersistedPrepBatch(TestPrepBatchFixtures.firstWeekBatch)]
                )
            ]
        )
        let store = PrepBatchStore(apiClient: apiClient, cacheStore: cacheStore)

        await store.load(householdID: TestPrepBatchFixtures.householdID, weekStartDate: TestPrepBatchFixtures.firstWeek)

        #expect(store.batches == [TestPrepBatchFixtures.firstWeekBatch])
        #expect(apiClient.requests.isEmpty)
    }

    @Test func fetchedBatchesArePersistedForLaterLoads() async {
        let apiClient = FakePrepBatchStoreAPIClient()
        let cacheStore = FakePrepBatchStoreCache()
        let store = PrepBatchStore(apiClient: apiClient, cacheStore: cacheStore)

        await store.load(householdID: TestPrepBatchFixtures.householdID, weekStartDate: TestPrepBatchFixtures.firstWeek)

        let persisted = cacheStore.caches["\(TestPrepBatchFixtures.householdID)|\(TestPrepBatchFixtures.firstWeek)"]
        #expect(persisted?.batches.map(\.prepBatch) == [TestPrepBatchFixtures.firstWeekBatch])
        #expect(persisted?.householdID == TestPrepBatchFixtures.householdID)
        #expect(persisted?.weekStartDate == TestPrepBatchFixtures.firstWeek)
    }
}

private enum TestPrepBatchFixtures {
    static let householdID = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    static let otherHouseholdID = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
    static let firstWeek = "2026-06-22"
    static let secondWeek = "2026-06-29"

    static let firstWeekBatch = PrepBatch(
        id: "11111111-1111-1111-1111-111111111111",
        householdId: householdID,
        recipeId: nil,
        customRecipeId: nil,
        cookDate: "2026-06-23",
        totalPortions: 4,
        assignments: []
    )

    static let secondWeekBatch = PrepBatch(
        id: "22222222-2222-2222-2222-222222222222",
        householdId: householdID,
        recipeId: nil,
        customRecipeId: nil,
        cookDate: "2026-06-30",
        totalPortions: 6,
        assignments: []
    )

    static let otherHouseholdBatch = PrepBatch(
        id: "33333333-3333-3333-3333-333333333333",
        householdId: otherHouseholdID,
        recipeId: nil,
        customRecipeId: nil,
        cookDate: "2026-06-24",
        totalPortions: 2,
        assignments: []
    )
}

private final class FakePrepBatchStoreAPIClient: PrepBatchStoreAPIClient {
    struct Request {
        let householdID: String
        let from: String
        let to: String
    }

    private(set) var requests: [Request] = []

    func listPrepBatches(householdID: String, from: String, to: String) async throws -> [PrepBatch] {
        requests.append(Request(householdID: householdID, from: from, to: to))
        switch (householdID, from) {
        case (TestPrepBatchFixtures.householdID, TestPrepBatchFixtures.firstWeek):
            return [TestPrepBatchFixtures.firstWeekBatch]
        case (TestPrepBatchFixtures.householdID, TestPrepBatchFixtures.secondWeek):
            return [TestPrepBatchFixtures.secondWeekBatch]
        case (TestPrepBatchFixtures.otherHouseholdID, TestPrepBatchFixtures.firstWeek):
            return [TestPrepBatchFixtures.otherHouseholdBatch]
        default:
            return []
        }
    }

    func createPrepBatch(
        householdID: String,
        recipeId: String?,
        cookDate: String,
        totalPortions: Int,
        assignments: [(date: String, mealType: MealType)]
    ) async throws -> PrepBatch {
        PrepBatch(
            id: "44444444-4444-4444-4444-444444444444",
            householdId: householdID,
            recipeId: recipeId,
            customRecipeId: nil,
            cookDate: cookDate,
            totalPortions: totalPortions,
            assignments: assignments.enumerated().map { index, assignment in
                PrepBatchAssignment(
                    id: "assignment-\(index)",
                    batchId: "44444444-4444-4444-4444-444444444444",
                    date: assignment.date,
                    mealType: assignment.mealType
                )
            }
        )
    }

    func deletePrepBatch(householdID: String, batchID: String) async throws {}

    func removeAssignment(householdID: String, batchID: String, date: String, mealType: MealType) async throws {}
}

private final class FakePrepBatchStoreCache: PrepBatchStoreCachePersisting {
    var caches: [String: PersistedPrepBatchCache]

    init(caches: [String: PersistedPrepBatchCache] = [:]) {
        self.caches = caches
    }

    func loadBatches(householdID: String, weekStartDate: String) -> PersistedPrepBatchCache? {
        caches["\(householdID)|\(weekStartDate)"]
    }

    func saveBatches(_ cache: PersistedPrepBatchCache) {
        caches["\(cache.householdID)|\(cache.weekStartDate)"] = cache
    }

    func deleteBatches(householdID: String, weekStartDate: String) {
        caches["\(householdID)|\(weekStartDate)"] = nil
    }
}

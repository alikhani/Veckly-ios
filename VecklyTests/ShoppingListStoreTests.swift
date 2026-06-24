import Foundation
import Testing
@testable import Veckly

@MainActor
struct ShoppingListStoreTests {
    @Test func togglePersistsExistingPantryStock() async {
        let apiClient = FakeShoppingListStoreAPIClient()
        apiClient.state = ShoppingListSharedState(
            checkedItems: [],
            pantryStock: ["pantry:rice:g": 100],
            customItems: []
        )
        let store = ShoppingListStore(
            apiClient: apiClient,
            syncDebounceNanoseconds: 0,
            retryDelayNanoseconds: 60_000_000_000
        )

        await store.loadCurrentWeek(household: TestShoppingListFixtures.household, weekStartDate: TestShoppingListFixtures.weekStartDate)
        await store.toggleItem(key: "produce:apples:")
        try? await Task.sleep(nanoseconds: 20_000_000)

        #expect(apiClient.updateRequests.count == 1)
        #expect(apiClient.updateRequests[0].pantryStock == ["pantry:rice:g": 100])
        #expect(apiClient.updateRequests[0].checkedItems == ["produce:apples:"])
    }

    @Test func staleRetryMergesLatestServerCustomItems() async throws {
        let apiClient = FakeShoppingListStoreAPIClient()
        apiClient.state = ShoppingListSharedState(checkedItems: [], pantryStock: [:], customItems: [])
        apiClient.updateResponses = [
            .failure(.stale(latestUpdatedAt: "2026-06-22T10:00:00.000Z")),
            .success("2026-06-22T10:00:01.000Z"),
        ]
        apiClient.refetchedState = ShoppingListSharedState(
            checkedItems: [],
            pantryStock: ["pantry:pasta:g": 250],
            customItems: [TestShoppingListFixtures.serverCustomItem]
        )

        let store = ShoppingListStore(
            apiClient: apiClient,
            syncDebounceNanoseconds: 0,
            retryDelayNanoseconds: 60_000_000_000
        )
        await store.loadCurrentWeek(household: TestShoppingListFixtures.household, weekStartDate: TestShoppingListFixtures.weekStartDate)

        try await store.addCustomItem(label: "Milk")
        try await Task.sleep(nanoseconds: 20_000_000)

        #expect(apiClient.updateRequests.count == 2)
        #expect(apiClient.updateRequests[1].pantryStock == ["pantry:pasta:g": 250])
        #expect(apiClient.updateRequests[1].customItems.contains(TestShoppingListFixtures.serverCustomItem))
        #expect(apiClient.updateRequests[1].customItems.contains(where: { $0.label == "Milk" }))
        #expect(store.customItems.contains(TestShoppingListFixtures.serverCustomItem))
        #expect(store.customItems.contains(where: { $0.label == "Milk" }))
    }

    @Test func toggleFailureKeepsLocalStateAndMarksPendingSync() async {
        let apiClient = FakeShoppingListStoreAPIClient()
        apiClient.state = ShoppingListSharedState(checkedItems: [], pantryStock: [:], customItems: [])
        apiClient.updateResponses = [.failure(.server(statusCode: 500))]
        let store = ShoppingListStore(
            apiClient: apiClient,
            syncDebounceNanoseconds: 0,
            retryDelayNanoseconds: 60_000_000_000
        )

        await store.loadCurrentWeek(household: TestShoppingListFixtures.household, weekStartDate: TestShoppingListFixtures.weekStartDate)
        await store.toggleItem(key: "produce:apples:")
        try? await Task.sleep(nanoseconds: 20_000_000)

        #expect(store.checkedItems == ["produce:apples:"])
        #expect(store.hasPendingSync)
        #expect(store.mutationError == L10n.string("error.shopping.pendingSync"))
    }

    @Test func rapidTogglesAreBatchedIntoSingleRequest() async throws {
        let apiClient = FakeShoppingListStoreAPIClient()
        apiClient.summary = TestShoppingListFixtures.summaryWithTwoItems
        apiClient.state = ShoppingListSharedState(checkedItems: [], pantryStock: [:], customItems: [])
        let store = ShoppingListStore(
            apiClient: apiClient,
            syncDebounceNanoseconds: 50_000_000,
            retryDelayNanoseconds: 60_000_000_000
        )

        await store.loadCurrentWeek(household: TestShoppingListFixtures.household, weekStartDate: TestShoppingListFixtures.weekStartDate)

        await store.toggleItem(key: "produce:apples:")
        await store.toggleItem(key: "produce:bananas:")

        #expect(store.checkedItems == ["produce:apples:", "produce:bananas:"])
        #expect(apiClient.updateRequests.isEmpty)

        try await Task.sleep(nanoseconds: 120_000_000)

        #expect(apiClient.updateRequests.count == 1)
        #expect(apiClient.updateRequests[0].checkedItems == ["produce:apples:", "produce:bananas:"])
        #expect(!store.hasPendingSync)
    }

    @Test func freshCacheIsIgnoredWhenItBelongsToAnotherWeek() async {
        let requestedWeek = TestShoppingListFixtures.weekStartDate
        let staleWeek = "2026-06-15"
        let apiClient = FakeShoppingListStoreAPIClient()
        apiClient.summary = TestShoppingListFixtures.summaryForWeek(staleWeek, itemKey: "produce:old:")
        apiClient.state = ShoppingListSharedState(checkedItems: [], pantryStock: [:], customItems: [])
        let store = ShoppingListStore(
            apiClient: apiClient,
            syncDebounceNanoseconds: 0,
            retryDelayNanoseconds: 60_000_000_000
        )

        await store.loadCurrentWeek(household: TestShoppingListFixtures.household, weekStartDate: requestedWeek)

        apiClient.summary = TestShoppingListFixtures.summaryForWeek(requestedWeek, itemKey: "produce:new:")
        await store.loadCurrentWeek(household: TestShoppingListFixtures.household, weekStartDate: requestedWeek)

        #expect(apiClient.summaryFetchCount == 2)
        #expect(store.summary?.weekStartDate == requestedWeek)
        #expect(store.groups.flatMap(\.items).contains(where: { $0.itemKey == "produce:new:" }))
    }
}

private enum TestShoppingListFixtures {
    static let household = Household(
        id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
        name: "Test household",
        role: .owner
    )
    static let weekStartDate = "2026-06-22"
    static let summary = ShoppingListSummary(
        household: SummaryHousehold(id: household.id, name: household.name),
        weekStartDate: weekStartDate,
        updatedAt: "2026-06-22T09:00:00.000Z",
        groups: [
            ShoppingListGroup(
                category: "Produce",
                items: [
                    ShoppingListItem(
                        itemKey: "produce:apples:",
                        label: "Apples",
                        amount: "4",
                        unit: nil,
                        checked: false
                    )
                ]
            )
        ]
    )
    static let summaryWithTwoItems = ShoppingListSummary(
        household: SummaryHousehold(id: household.id, name: household.name),
        weekStartDate: weekStartDate,
        updatedAt: "2026-06-22T09:00:00.000Z",
        groups: [
            ShoppingListGroup(
                category: "Produce",
                items: [
                    ShoppingListItem(
                        itemKey: "produce:apples:",
                        label: "Apples",
                        amount: "4",
                        unit: nil,
                        checked: false
                    ),
                    ShoppingListItem(
                        itemKey: "produce:bananas:",
                        label: "Bananas",
                        amount: "6",
                        unit: nil,
                        checked: false
                    ),
                ]
            )
        ]
    )

    static func summaryForWeek(_ weekStartDate: String, itemKey: String) -> ShoppingListSummary {
        ShoppingListSummary(
            household: SummaryHousehold(id: household.id, name: household.name),
            weekStartDate: weekStartDate,
            updatedAt: "2026-06-22T09:00:00.000Z",
            groups: [
                ShoppingListGroup(
                    category: "Produce",
                    items: [
                        ShoppingListItem(
                            itemKey: itemKey,
                            label: "Apples",
                            amount: "4",
                            unit: nil,
                            checked: false
                        )
                    ]
                )
            ]
        )
    }
    static let serverCustomItem = ShoppingCustomItem(
        itemKey: "custom:server",
        label: "Coffee",
        category: "Other"
    )
}

private final class FakeShoppingListStoreAPIClient: ShoppingListStoreAPIClient {
    struct UpdateRequest {
        let householdID: String
        let weekStartDate: String
        let checkedItems: [String]
        let pantryStock: [String: Double]
        let expectedUpdatedAt: String?
        let customItems: [ShoppingCustomItem]
    }

    var summary = TestShoppingListFixtures.summary
    var state: ShoppingListSharedState?
    var refetchedState: ShoppingListSharedState?
    var updateResponses: [Result<String?, APIError>] = [.success("2026-06-22T09:05:00.000Z")]
    private(set) var summaryFetchCount = 0
    private(set) var updateRequests: [UpdateRequest] = []
    private var shoppingListStateCallCount = 0

    func shoppingListSummary(householdID: String, weekStartDate: String) async throws -> ShoppingListSummary {
        summaryFetchCount += 1
        return summary
    }

    func shoppingListState(householdID: String, weekStartDate: String) async throws -> (state: ShoppingListSharedState?, updatedAt: String?) {
        shoppingListStateCallCount += 1
        if shoppingListStateCallCount == 1 {
            return (state, summary.updatedAt)
        }
        return (refetchedState ?? state, "2026-06-22T10:00:00.000Z")
    }

    func updateShoppingListState(
        householdID: String,
        weekStartDate: String,
        checkedItems: [String],
        pantryStock: [String: Double],
        expectedUpdatedAt: String?,
        customItems: [ShoppingCustomItem]
    ) async throws -> String? {
        updateRequests.append(
            UpdateRequest(
                householdID: householdID,
                weekStartDate: weekStartDate,
                checkedItems: checkedItems.sorted(),
                pantryStock: pantryStock,
                expectedUpdatedAt: expectedUpdatedAt,
                customItems: customItems
            )
        )

        let response = updateResponses.isEmpty ? .success(expectedUpdatedAt) : updateResponses.removeFirst()
        switch response {
        case .success(let updatedAt):
            state = ShoppingListSharedState(
                checkedItems: checkedItems.sorted(),
                pantryStock: pantryStock,
                customItems: customItems
            )
            return updatedAt
        case .failure(let error):
            throw error
        }
    }
}

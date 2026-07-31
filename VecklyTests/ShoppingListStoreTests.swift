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

    @Test func duplicateCustomItemsAreCollapsedByLabelAndCategory() async throws {
        let apiClient = FakeShoppingListStoreAPIClient()
        apiClient.state = ShoppingListSharedState(
            checkedItems: [],
            pantryStock: [:],
            customItems: [
                ShoppingCustomItem(itemKey: "custom:first", label: "Toapapper", category: "Other"),
                ShoppingCustomItem(itemKey: "custom:second", label: " toapapper ", category: "Other"),
            ]
        )
        let store = ShoppingListStore(
            apiClient: apiClient,
            syncDebounceNanoseconds: 0,
            retryDelayNanoseconds: 60_000_000_000
        )

        await store.loadCurrentWeek(household: TestShoppingListFixtures.household, weekStartDate: TestShoppingListFixtures.weekStartDate)
        store.addCustomItem(label: "TOAPAPPER", category: .other)
        try await Task.sleep(nanoseconds: 20_000_000)

        #expect(store.customItems.map(\.label) == ["Toapapper"])
        #expect(apiClient.updateRequests.isEmpty)
    }

    @Test func customItemsFromSummaryAndStateAreNotRenderedTwice() async {
        let apiClient = FakeShoppingListStoreAPIClient()
        apiClient.summary = TestShoppingListFixtures.summaryWithCustomItem(
            ShoppingListItem(
                itemKey: "custom:summary-toapapper",
                label: "Toapapper",
                amount: nil,
                unit: nil,
                checked: false,
                isCustom: true
            )
        )
        apiClient.state = ShoppingListSharedState(
            checkedItems: [],
            pantryStock: [:],
            customItems: [
                ShoppingCustomItem(itemKey: "custom:state-toapapper", label: " Toapapper ", category: "Other"),
            ]
        )
        let store = ShoppingListStore(
            apiClient: apiClient,
            syncDebounceNanoseconds: 0,
            retryDelayNanoseconds: 60_000_000_000
        )

        await store.loadCurrentWeek(household: TestShoppingListFixtures.household, weekStartDate: TestShoppingListFixtures.weekStartDate)

        let renderedCustomItems = store.groups.flatMap(\.items).filter(\.isCustom)
        #expect(renderedCustomItems.count == 1)
        #expect(renderedCustomItems.first?.label.trimmingCharacters(in: .whitespacesAndNewlines) == "Toapapper")
    }

    @Test func duplicateItemKeysAreNotRenderedWithinTheSameGroup() async {
        let apiClient = FakeShoppingListStoreAPIClient()
        apiClient.summary = TestShoppingListFixtures.summaryWithDuplicateCustomItemKey
        apiClient.state = nil
        let store = ShoppingListStore(
            apiClient: apiClient,
            syncDebounceNanoseconds: 0,
            retryDelayNanoseconds: 60_000_000_000
        )

        await store.loadCurrentWeek(household: TestShoppingListFixtures.household, weekStartDate: TestShoppingListFixtures.weekStartDate)

        let renderedKeys = store.groups.flatMap(\.items).map(\.itemKey)
        #expect(renderedKeys == ["custom:duplicate-servetter"])
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

    @Test func reloadDuringDebounceKeepsOptimisticCheckAndPersistsIt() async throws {
        let apiClient = FakeShoppingListStoreAPIClient()
        apiClient.state = ShoppingListSharedState(checkedItems: [], pantryStock: [:], customItems: [])
        let store = ShoppingListStore(
            apiClient: apiClient,
            syncDebounceNanoseconds: 80_000_000,
            retryDelayNanoseconds: 60_000_000_000
        )
        await store.loadCurrentWeek(household: TestShoppingListFixtures.household, weekStartDate: TestShoppingListFixtures.weekStartDate)

        await store.toggleItem(key: "produce:apples:")
        await store.loadCurrentWeek(
            household: TestShoppingListFixtures.household,
            weekStartDate: TestShoppingListFixtures.weekStartDate,
            force: true
        )

        #expect(store.checkedItems == ["produce:apples:"])
        try await Task.sleep(nanoseconds: 120_000_000)
        #expect(apiClient.updateRequests.count == 1)
        #expect(apiClient.updateRequests[0].checkedItems == ["produce:apples:"])
    }

    @Test func lateReloadCannotOverwriteAnEditMadeWhileItWasInFlight() async throws {
        let apiClient = FakeShoppingListStoreAPIClient()
        apiClient.state = ShoppingListSharedState(checkedItems: [], pantryStock: [:], customItems: [])
        let store = ShoppingListStore(
            apiClient: apiClient,
            syncDebounceNanoseconds: 60_000_000_000,
            retryDelayNanoseconds: 60_000_000_000
        )
        await store.loadCurrentWeek(household: TestShoppingListFixtures.household, weekStartDate: TestShoppingListFixtures.weekStartDate)
        apiClient.stateDelayNanoseconds = 60_000_000

        let reload = Task {
            await store.loadCurrentWeek(
                household: TestShoppingListFixtures.household,
                weekStartDate: TestShoppingListFixtures.weekStartDate,
                force: true
            )
        }
        try await Task.sleep(nanoseconds: 10_000_000)
        await store.toggleItem(key: "produce:apples:")
        await reload.value

        #expect(store.checkedItems == ["produce:apples:"])
    }

    @Test func staleRetryIsIdempotentWhenServerAlreadyHasDesiredCheck() async throws {
        let apiClient = FakeShoppingListStoreAPIClient()
        apiClient.state = ShoppingListSharedState(checkedItems: [], pantryStock: [:], customItems: [])
        apiClient.refetchedState = ShoppingListSharedState(checkedItems: ["produce:apples:"], pantryStock: [:], customItems: [])
        apiClient.updateResponses = [
            .failure(.stale(latestUpdatedAt: "2026-06-22T10:00:00.000Z")),
            .success("2026-06-22T10:00:01.000Z"),
        ]
        let store = ShoppingListStore(apiClient: apiClient, syncDebounceNanoseconds: 0, retryDelayNanoseconds: 0)
        await store.loadCurrentWeek(household: TestShoppingListFixtures.household, weekStartDate: TestShoppingListFixtures.weekStartDate)

        await store.toggleItem(key: "produce:apples:")
        try await Task.sleep(nanoseconds: 30_000_000)

        #expect(apiClient.updateRequests.count == 2)
        #expect(apiClient.updateRequests[1].checkedItems == ["produce:apples:"])
        #expect(store.checkedItems == ["produce:apples:"])
    }

    @Test func ambiguousCommittedWriteRetriesWithoutReversingDesiredCheck() async throws {
        let apiClient = FakeShoppingListStoreAPIClient()
        apiClient.state = ShoppingListSharedState(checkedItems: [], pantryStock: [:], customItems: [])
        apiClient.updateResponses = [
            .failure(.server(statusCode: 500)),
            .failure(.stale(latestUpdatedAt: "2026-06-22T10:00:00.000Z")),
            .success("2026-06-22T10:00:01.000Z"),
        ]
        apiClient.commitFailedUpdateCount = 1
        let store = ShoppingListStore(apiClient: apiClient, syncDebounceNanoseconds: 0, retryDelayNanoseconds: 0)
        await store.loadCurrentWeek(household: TestShoppingListFixtures.household, weekStartDate: TestShoppingListFixtures.weekStartDate)

        await store.toggleItem(key: "produce:apples:")
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(apiClient.updateRequests.count == 3)
        #expect(apiClient.updateRequests.last?.checkedItems == ["produce:apples:"])
        #expect(store.checkedItems == ["produce:apples:"])
        #expect(!store.hasPendingSync)
    }

    @Test func rapidRepeatedEditsOfOneItemPersistOnlyTheFinalState() async throws {
        let apiClient = FakeShoppingListStoreAPIClient()
        apiClient.state = ShoppingListSharedState(checkedItems: [], pantryStock: [:], customItems: [])
        let store = ShoppingListStore(
            apiClient: apiClient,
            syncDebounceNanoseconds: 50_000_000,
            retryDelayNanoseconds: 60_000_000_000
        )
        await store.loadCurrentWeek(household: TestShoppingListFixtures.household, weekStartDate: TestShoppingListFixtures.weekStartDate)

        await store.toggleItem(key: "produce:apples:")
        await store.toggleItem(key: "produce:apples:")
        await store.toggleItem(key: "produce:apples:")
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(apiClient.updateRequests.count == 1)
        #expect(apiClient.updateRequests[0].checkedItems == ["produce:apples:"])
    }

    @Test func pendingMutationIsFlushedOnlyToItsOriginalWeekBeforeContextSwitch() async throws {
        let apiClient = FakeShoppingListStoreAPIClient()
        apiClient.state = ShoppingListSharedState(checkedItems: [], pantryStock: [:], customItems: [])
        let store = ShoppingListStore(
            apiClient: apiClient,
            syncDebounceNanoseconds: 60_000_000_000,
            retryDelayNanoseconds: 60_000_000_000
        )
        let originalWeek = TestShoppingListFixtures.weekStartDate
        let nextWeek = "2026-06-29"
        await store.loadCurrentWeek(household: TestShoppingListFixtures.household, weekStartDate: originalWeek)
        await store.toggleItem(key: "produce:apples:")
        apiClient.summary = TestShoppingListFixtures.summaryForWeek(nextWeek, itemKey: "produce:bananas:")

        await store.loadCurrentWeek(
            household: TestShoppingListFixtures.household,
            weekStartDate: nextWeek,
            force: true
        )

        #expect(apiClient.updateRequests.count == 1)
        #expect(apiClient.updateRequests[0].householdID == TestShoppingListFixtures.household.id)
        #expect(apiClient.updateRequests[0].weekStartDate == originalWeek)
        #expect(apiClient.updateRequests[0].checkedItems == ["produce:apples:"])
        #expect(store.summary?.weekStartDate == nextWeek)
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

    /// `.onAppear` and `.task(id: weekStartDate)` in `ShoppingListTabView` both
    /// trigger a load on tab appearance, and `.task` is cancelled/restarted
    /// whenever the view leaves and rejoins the visible hierarchy (switching
    /// tabs, backgrounding). A cancelled in-flight request must not be treated
    /// as a real failure — that used to wipe an already-loaded list and force
    /// the user to tap "Try again" to see data that was already there.
    @Test func cancellationDuringARefreshDoesNotClobberAlreadyLoadedData() async {
        let apiClient = FakeShoppingListStoreAPIClient()
        apiClient.state = ShoppingListSharedState(checkedItems: [], pantryStock: [:], customItems: [])
        let store = ShoppingListStore(
            apiClient: apiClient,
            syncDebounceNanoseconds: 0,
            retryDelayNanoseconds: 60_000_000_000
        )

        await store.loadCurrentWeek(household: TestShoppingListFixtures.household, weekStartDate: TestShoppingListFixtures.weekStartDate)
        #expect(store.errorMessage == nil)
        #expect(!store.groups.isEmpty)

        apiClient.shouldThrowCancellation = true
        store.invalidateCache()
        await store.loadCurrentWeek(household: TestShoppingListFixtures.household, weekStartDate: TestShoppingListFixtures.weekStartDate)

        #expect(store.errorMessage == nil)
        #expect(!store.groups.isEmpty)
    }

    @Test func cancellationOnTheFirstLoadLeavesTheStoreWithoutAnErrorBanner() async {
        let apiClient = FakeShoppingListStoreAPIClient()
        apiClient.state = ShoppingListSharedState(checkedItems: [], pantryStock: [:], customItems: [])
        apiClient.shouldThrowCancellation = true
        let store = ShoppingListStore(
            apiClient: apiClient,
            syncDebounceNanoseconds: 0,
            retryDelayNanoseconds: 60_000_000_000
        )

        await store.loadCurrentWeek(household: TestShoppingListFixtures.household, weekStartDate: TestShoppingListFixtures.weekStartDate)

        #expect(store.errorMessage == nil)
        #expect(store.summary == nil)
    }

    @Test func shareTextIsNilForEmptyShoppingList() {
        let text = ShoppingListShareText.make(
            title: "Shopping list",
            contextLine: "V.26",
            groups: [],
            staples: [],
            checkedItems: []
        )

        #expect(text == nil)
    }

    @Test func shareTextIncludesCustomItemsStaplesAndAmounts() {
        let groups = [
            ShoppingListGroup(
                category: "Produce",
                items: [
                    ShoppingListItem(
                        itemKey: "custom:milk",
                        label: "Milk",
                        amount: nil,
                        unit: nil,
                        checked: false,
                        isCustom: true
                    ),
                    ShoppingListItem(
                        itemKey: "produce:apples:",
                        label: "Apples",
                        amount: "2",
                        unit: "st",
                        checked: false
                    ),
                ]
            )
        ]
        let staples = [
            ShoppingListItem(
                itemKey: "pantry:salt:",
                label: "Salt",
                amount: nil,
                unit: nil,
                checked: false
            )
        ]

        let text = ShoppingListShareText.make(
            title: "Shopping list",
            contextLine: "V.26 · 2 meals",
            groups: groups,
            staples: staples,
            checkedItems: ["produce:apples:"]
        )

        #expect(text?.contains("Shopping list") == true)
        #expect(text?.contains("V.26 · 2 meals") == true)
        #expect(text?.contains(ShoppingCategory.produce.displayLabel) == true)
        #expect(text?.contains("- [ ] Milk") == true)
        #expect(text?.contains("- [x] Apples 2 st") == true)
        #expect(text?.contains(L10n.string("shopping.likelyAtHome")) == true)
        #expect(text?.contains("- [ ] Salt") == true)
    }

    @Test func reminderShareItemsIncludeOnlyUncheckedMainItems() {
        let groups = [
            ShoppingListGroup(
                category: "Produce",
                items: [
                    ShoppingListItem(
                        itemKey: "produce:avocado:",
                        label: "Avocado",
                        amount: "0.5",
                        unit: "pc",
                        checked: false
                    ),
                    ShoppingListItem(
                        itemKey: "produce:apples:",
                        label: "Apples",
                        amount: "2",
                        unit: "st",
                        checked: false
                    ),
                ]
            ),
            ShoppingListGroup(
                category: "Pantry",
                items: [
                    ShoppingListItem(
                        itemKey: "pantry:rice:g",
                        label: "Rice",
                        amount: "100",
                        unit: "g",
                        checked: false
                    ),
                ]
            ),
        ]

        let items = ShoppingListShareText.reminderItems(
            groups: groups,
            checkedItems: ["produce:apples:"]
        )

        #expect(items == ["Avocado 0.5 pc", "Rice 100 g"])
        #expect(!items.contains("Shopping list"))
        #expect(!items.contains(where: { $0.contains("Apples") }))
    }

    @Test func handoffStateIsNilForEmptyMainList() {
        #expect(ShoppingListHandoffState.make(groups: [], checkedItems: []) == nil)
    }

    @Test func handoffStateIsReadyUntilMainItemsAreChecked() {
        let groups = [
            ShoppingListGroup(
                category: "Produce",
                items: [
                    ShoppingListItem(itemKey: "produce:apples:", label: "Apples", amount: "4", unit: nil, checked: false),
                    ShoppingListItem(itemKey: "produce:bananas:", label: "Bananas", amount: "6", unit: nil, checked: false),
                ]
            )
        ]

        #expect(ShoppingListHandoffState.make(groups: groups, checkedItems: ["produce:apples:"]) == .ready(totalItems: 2, checkedItems: 1))
    }

    @Test func handoffStateCompletesWhenAllMainItemsAreChecked() {
        let groups = [
            ShoppingListGroup(
                category: "Produce",
                items: [
                    ShoppingListItem(itemKey: "produce:apples:", label: "Apples", amount: "4", unit: nil, checked: false),
                    ShoppingListItem(itemKey: "produce:bananas:", label: "Bananas", amount: "6", unit: nil, checked: false),
                ]
            )
        ]

        #expect(ShoppingListHandoffState.make(
            groups: groups,
            checkedItems: ["produce:apples:", "produce:bananas:", "pantry:salt:"]
        ) == .completed(totalItems: 2))
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

    static func summaryWithCustomItem(_ customItem: ShoppingListItem) -> ShoppingListSummary {
        ShoppingListSummary(
            household: SummaryHousehold(id: household.id, name: household.name),
            weekStartDate: weekStartDate,
            updatedAt: "2026-06-22T09:00:00.000Z",
            groups: [
                ShoppingListGroup(
                    category: "Other",
                    items: [customItem]
                )
            ]
        )
    }

    static let summaryWithDuplicateCustomItemKey = ShoppingListSummary(
        household: SummaryHousehold(id: household.id, name: household.name),
        weekStartDate: weekStartDate,
        updatedAt: "2026-06-22T09:00:00.000Z",
        groups: [
            ShoppingListGroup(
                category: "Other",
                items: [
                    ShoppingListItem(itemKey: "custom:duplicate-servetter", label: "Servetter", amount: nil, unit: nil, checked: false, isCustom: true),
                    ShoppingListItem(itemKey: "custom:duplicate-servetter", label: "Servetter", amount: nil, unit: nil, checked: false, isCustom: true),
                ]
            )
        ]
    )

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
    var shouldThrowCancellation = false
    var stateDelayNanoseconds: UInt64 = 0
    var commitFailedUpdateCount = 0
    private(set) var summaryFetchCount = 0
    private(set) var updateRequests: [UpdateRequest] = []
    private var shoppingListStateCallCount = 0

    func shoppingListSummary(householdID: String, weekStartDate: String) async throws -> ShoppingListSummary {
        if shouldThrowCancellation { throw CancellationError() }
        summaryFetchCount += 1
        return summary
    }

    func shoppingListState(householdID: String, weekStartDate: String) async throws -> (state: ShoppingListSharedState?, updatedAt: String?) {
        if shouldThrowCancellation { throw CancellationError() }
        shoppingListStateCallCount += 1
        let response = shoppingListStateCallCount == 1
            ? (state, summary.updatedAt)
            : (refetchedState ?? state, "2026-06-22T10:00:00.000Z")
        if stateDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: stateDelayNanoseconds)
        }
        return response
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
            if commitFailedUpdateCount > 0 {
                commitFailedUpdateCount -= 1
                state = ShoppingListSharedState(
                    checkedItems: checkedItems.sorted(),
                    pantryStock: pantryStock,
                    customItems: customItems
                )
            }
            throw error
        }
    }
}

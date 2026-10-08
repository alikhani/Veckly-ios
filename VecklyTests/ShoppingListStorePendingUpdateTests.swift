import Foundation
import Testing
@testable import Veckly

/// "Updates available" for the shopping list: a background refresh that
/// differs from what is on screen waits behind a banner.
@MainActor
struct ShoppingListStorePendingUpdateTests {
    private let household = Household(id: "11111111-1111-1111-1111-111111111111", name: "Test household", role: .owner)
    private let otherHousehold = Household(id: "99999999-9999-9999-9999-999999999999", name: "Other", role: .owner)
    private let week = "2026-10-05"

    private func makeStore(api: PendingShoppingAPIClient, cache: PendingShoppingCache = PendingShoppingCache()) -> ShoppingListStore {
        ShoppingListStore(
            apiClient: api,
            syncDebounceNanoseconds: 0,
            retryDelayNanoseconds: 60_000_000_000,
            cacheStore: cache,
            currentUserID: { "user-1" },
            currentLanguage: { "sv" }
        )
    }

    private func labels(_ store: ShoppingListStore) -> [String] {
        store.groups.flatMap(\.items).map(\.label).sorted()
    }

    // Row 1
    @Test func whenNoCacheWasShownTheResponseIsAppliedDirectly() async {
        let api = PendingShoppingAPIClient(labels: ["Mjölk"])
        let store = makeStore(api: api)

        await store.loadCurrentWeek(household: household, weekStartDate: week)

        #expect(labels(store) == ["Mjölk"])
        #expect(store.pendingUpdate == nil)
    }

    // Row 2
    @Test func anEqualResponseDoesNothing() async {
        let api = PendingShoppingAPIClient(labels: ["Mjölk"])
        let store = makeStore(api: api)
        await store.loadCurrentWeek(household: household, weekStartDate: week)

        await store.loadCurrentWeek(household: household, weekStartDate: week, force: true)

        #expect(store.pendingUpdate == nil)
        #expect(labels(store) == ["Mjölk"])
    }

    @Test func anEqualResponseListedInAnotherOrderDoesNothing() async {
        let api = PendingShoppingAPIClient(labels: ["Mjölk"])
        api.state = ShoppingListSharedState(checkedItems: ["a", "b"], pantryStock: [:], customItems: [])
        let store = makeStore(api: api)
        await store.loadCurrentWeek(household: household, weekStartDate: week)
        api.state = ShoppingListSharedState(checkedItems: ["b", "a"], pantryStock: [:], customItems: [])

        await store.loadCurrentWeek(household: household, weekStartDate: week, force: true)

        #expect(store.pendingUpdate == nil)
    }

    // Row 3
    @Test func aDifferingResponseWaitsAsAPendingUpdateAndLeavesTheScreenAlone() async {
        let api = PendingShoppingAPIClient(labels: ["Mjölk"])
        let store = makeStore(api: api)
        await store.loadCurrentWeek(household: household, weekStartDate: week)
        api.labels = ["Mjölk", "Pasta"]
        api.version = "s2"

        await store.loadCurrentWeek(household: household, weekStartDate: week, force: true)

        #expect(labels(store) == ["Mjölk"])
        #expect(store.pendingUpdate?.value.summary.updatedAt == "s2")
        #expect(store.hasPendingUpdate)
    }

    @Test func aCheckMadeElsewhereAlsoWaitsBehindTheBanner() async {
        let api = PendingShoppingAPIClient(labels: ["Mjölk"])
        let store = makeStore(api: api)
        await store.loadCurrentWeek(household: household, weekStartDate: week)
        api.state = ShoppingListSharedState(checkedItems: ["dairy:mjölk:"], pantryStock: [:], customItems: [])
        api.stateVersion = "t2"

        await store.loadCurrentWeek(household: household, weekStartDate: week, force: true)

        #expect(store.checkedItems.isEmpty)
        #expect(store.hasPendingUpdate)
    }

    // Row 4
    @Test func tappingTheBannerAppliesThePendingUpdateAndClearsIt() async {
        let api = PendingShoppingAPIClient(labels: ["Mjölk"])
        let store = makeStore(api: api)
        await store.loadCurrentWeek(household: household, weekStartDate: week)
        api.labels = ["Mjölk", "Pasta"]
        api.state = ShoppingListSharedState(checkedItems: ["dairy:pasta:"], pantryStock: [:], customItems: [])
        api.version = "s2"
        await store.loadCurrentWeek(household: household, weekStartDate: week, force: true)

        store.applyPendingUpdate()

        #expect(labels(store) == ["Mjölk", "Pasta"])
        #expect(store.checkedItems == ["dairy:pasta:"])
        #expect(store.pendingUpdate == nil)
    }

    // Row 5
    @Test func pullToRefreshAppliesDirectlyAndDropsAnyPendingUpdate() async {
        let api = PendingShoppingAPIClient(labels: ["Mjölk"])
        let store = makeStore(api: api)
        await store.loadCurrentWeek(household: household, weekStartDate: week)
        api.labels = ["Mjölk", "Pasta"]
        api.version = "s2"
        await store.loadCurrentWeek(household: household, weekStartDate: week, force: true)
        #expect(store.hasPendingUpdate)
        api.labels = ["Mjölk", "Pasta", "Ris"]
        api.version = "s3"

        await store.loadCurrentWeek(household: household, weekStartDate: week, force: true, origin: .userInitiated)

        #expect(labels(store) == ["Mjölk", "Pasta", "Ris"])
        #expect(store.pendingUpdate == nil)
    }

    // Row 6
    @Test func anOwnSyncedChangeDiscardsAnOlderPendingUpdateAndNeverRaisesOne() async throws {
        let api = PendingShoppingAPIClient(labels: ["Mjölk", "Pasta"])
        let store = makeStore(api: api)
        await store.loadCurrentWeek(household: household, weekStartDate: week)

        // Checking an item here never raises the banner, even though the
        // server's copy changes underneath.
        store.setItemChecked(key: "dairy:mjölk:", isChecked: true)
        try await waitUntil { !store.hasPendingSync }
        await store.loadCurrentWeek(household: household, weekStartDate: week, force: true)
        #expect(store.pendingUpdate == nil)
        #expect(store.checkedItems == ["dairy:mjölk:"])

        // An older pending update is dropped once the user's own write lands.
        api.labels = ["Mjölk", "Pasta", "Ris"]
        api.version = "s2"
        await store.loadCurrentWeek(household: household, weekStartDate: week, force: true)
        #expect(store.hasPendingUpdate)
        store.setItemChecked(key: "dairy:pasta:", isChecked: true)
        try await waitUntil { !store.hasPendingSync }
        #expect(store.pendingUpdate == nil)
    }

    @Test func aReloadAfterOwnWeekChangeAppliesDirectly() async {
        let api = PendingShoppingAPIClient(labels: ["Mjölk"])
        let store = makeStore(api: api)
        await store.loadCurrentWeek(household: household, weekStartDate: week)
        api.labels = ["Mjölk", "Pasta"]
        api.version = "s2"
        store.invalidateCache()

        await store.loadCurrentWeek(household: household, weekStartDate: week, origin: .userInitiated)

        #expect(labels(store) == ["Mjölk", "Pasta"])
        #expect(store.pendingUpdate == nil)
    }

    // Row 7
    @Test func aFailedBackgroundRefreshKeepsTheCachedListWithoutAnError() async {
        let api = PendingShoppingAPIClient(labels: ["Mjölk"])
        let store = makeStore(api: api)
        await store.loadCurrentWeek(household: household, weekStartDate: week)
        api.failure = URLError(.notConnectedToInternet)

        await store.loadCurrentWeek(household: household, weekStartDate: week, force: true)

        #expect(labels(store) == ["Mjölk"])
        #expect(store.errorMessage == nil)
        #expect(store.pendingUpdate == nil)
    }

    @Test func aFailedBackgroundRefreshKeepsAnExistingPendingUpdate() async {
        let api = PendingShoppingAPIClient(labels: ["Mjölk"])
        let store = makeStore(api: api)
        await store.loadCurrentWeek(household: household, weekStartDate: week)
        api.labels = ["Mjölk", "Pasta"]
        api.version = "s2"
        await store.loadCurrentWeek(household: household, weekStartDate: week, force: true)
        api.failure = URLError(.notConnectedToInternet)

        await store.loadCurrentWeek(household: household, weekStartDate: week, force: true)

        #expect(store.hasPendingUpdate)
        #expect(store.errorMessage == nil)
    }

    // Row 8
    @Test func switchingHouseholdOrWeekDiscardsThePendingUpdate() async {
        let api = PendingShoppingAPIClient(labels: ["Mjölk"])
        let store = makeStore(api: api)
        await store.loadCurrentWeek(household: household, weekStartDate: week)
        api.labels = ["Mjölk", "Pasta"]
        api.version = "s2"
        await store.loadCurrentWeek(household: household, weekStartDate: week, force: true)
        #expect(store.hasPendingUpdate)

        await store.loadCurrentWeek(household: otherHousehold, weekStartDate: week, force: true)
        #expect(store.pendingUpdate == nil)
        // The other household's list was applied directly: nothing of it was shown before.
        #expect(store.summary?.household.id == otherHousehold.id)
    }

    @Test func movingToAnotherWeekDiscardsThePendingUpdate() async {
        let api = PendingShoppingAPIClient(labels: ["Mjölk"])
        let store = makeStore(api: api)
        await store.loadCurrentWeek(household: household, weekStartDate: week)
        api.labels = ["Mjölk", "Pasta"]
        api.version = "s2"
        await store.loadCurrentWeek(household: household, weekStartDate: week, force: true)
        #expect(store.hasPendingUpdate)

        await store.loadCurrentWeek(household: household, weekStartDate: "2026-10-12", force: true)

        #expect(store.pendingUpdate == nil)
    }

    @Test func resettingDiscardsThePendingUpdate() async {
        let api = PendingShoppingAPIClient(labels: ["Mjölk"])
        let store = makeStore(api: api)
        await store.loadCurrentWeek(household: household, weekStartDate: week)
        api.labels = ["Mjölk", "Pasta"]
        api.version = "s2"
        await store.loadCurrentWeek(household: household, weekStartDate: week, force: true)

        store.reset(discardPendingMutations: true)

        #expect(store.pendingUpdate == nil)
    }

    // Around the table
    @Test func aDeferredResponseIsStillWrittenToDisk() async {
        let cache = PendingShoppingCache()
        let api = PendingShoppingAPIClient(labels: ["Mjölk"])
        let store = makeStore(api: api, cache: cache)
        await store.loadCurrentWeek(household: household, weekStartDate: week)
        api.labels = ["Mjölk", "Pasta"]
        api.version = "s2"

        await store.loadCurrentWeek(household: household, weekStartDate: week, force: true)

        #expect(cache.latest?.summary.updatedAt == "s2")
    }

    @Test func aListRestoredFromDiskIsProtectedFromASilentSwap() async {
        let cache = PendingShoppingCache()
        let api = PendingShoppingAPIClient(labels: ["Mjölk", "Pasta"])
        cache.latest = ShoppingListSnapshot(
            summary: api.makeSummary(householdID: household.id, labels: ["Mjölk"], version: "d1"),
            state: ShoppingListSharedState(checkedItems: [], pantryStock: [:], customItems: []),
            stateUpdatedAt: "t0",
            categoryOrder: nil
        )
        let store = makeStore(api: api, cache: cache)

        await store.loadCurrentWeek(household: household, weekStartDate: week)

        #expect(labels(store) == ["Mjölk"])
        #expect(store.hasPendingUpdate)
    }

    @Test func aResponseThatMatchesTheScreenAgainDropsTheStalePendingUpdate() async {
        let api = PendingShoppingAPIClient(labels: ["Mjölk"])
        let store = makeStore(api: api)
        await store.loadCurrentWeek(household: household, weekStartDate: week)
        api.labels = ["Mjölk", "Pasta"]
        api.version = "s2"
        await store.loadCurrentWeek(household: household, weekStartDate: week, force: true)
        api.labels = ["Mjölk"]
        api.version = "s1"

        await store.loadCurrentWeek(household: household, weekStartDate: week, force: true)

        #expect(store.pendingUpdate == nil)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<200 where !condition() {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(condition())
    }
}

private final class PendingShoppingCache: ShoppingListStoreCachePersisting {
    var latest: ShoppingListSnapshot?
    func loadList(scope: CacheScope, weekStartDate: String) -> ShoppingListSnapshot? {
        latest?.summary.weekStartDate == weekStartDate && latest?.summary.household.id == scope.householdID ? latest : nil
    }
    func saveList(_ snapshot: ShoppingListSnapshot, scope: CacheScope) { latest = snapshot }
    func removeList(scope: CacheScope, weekStartDate: String) { latest = nil }
    func deleteAll() { latest = nil }
}

private final class PendingShoppingAPIClient: ShoppingListStoreAPIClient {
    var labels: [String]
    var version = "s1"
    var state: ShoppingListSharedState? = ShoppingListSharedState(checkedItems: [], pantryStock: [:], customItems: [])
    var stateVersion = "t1"
    var failure: Error?

    init(labels: [String]) { self.labels = labels }

    func makeSummary(householdID: String, labels: [String], version: String) -> ShoppingListSummary {
        ShoppingListSummary(
            household: SummaryHousehold(id: householdID, name: "Test household"),
            weekStartDate: "2026-10-05",
            updatedAt: version,
            groups: [ShoppingListGroup(category: "Dairy", items: labels.map {
                ShoppingListItem(itemKey: "dairy:\($0.lowercased()):", label: $0, amount: nil, unit: nil, checked: false)
            })]
        )
    }

    func shoppingListSummary(householdID: String, weekStartDate: String) async throws -> ShoppingListSummary {
        if let failure { throw failure }
        var summary = makeSummary(householdID: householdID, labels: labels, version: version)
        if weekStartDate != summary.weekStartDate {
            summary = ShoppingListSummary(household: summary.household, weekStartDate: weekStartDate, updatedAt: version, groups: summary.groups)
        }
        return summary
    }

    func shoppingListState(householdID: String, weekStartDate: String) async throws -> (state: ShoppingListSharedState?, updatedAt: String?) {
        if let failure { throw failure }
        return (state, stateVersion)
    }

    func updateShoppingListState(
        householdID: String, weekStartDate: String, checkedItems: [String], pantryStock: [String: Double],
        expectedUpdatedAt: String?, customItems: [ShoppingCustomItem]
    ) async throws -> String? {
        state = ShoppingListSharedState(checkedItems: checkedItems, pantryStock: pantryStock, customItems: customItems)
        stateVersion += "+"
        return stateVersion
    }

    func shoppingPreferences(householdID: String) async throws -> ShoppingPreferences {
        ShoppingPreferences(categoryOrder: ShoppingCategory.allCases.map(\.preferenceValue), updatedAt: nil)
    }
}

import Foundation
import Testing
@testable import Veckly

/// Cold start: the shopping list the household last saw is on screen before
/// the network answers, and every authoritative response is written back.
@MainActor
struct ShoppingListStoreDiskCacheTests {
    private let household = Household(id: "11111111-1111-1111-1111-111111111111", name: "Test household", role: .owner)
    private let otherHousehold = Household(id: "99999999-9999-9999-9999-999999999999", name: "Other", role: .owner)
    private let userID = "33333333-3333-3333-3333-333333333333"
    private let week = "2026-10-05"
    private var scope: CacheScope { CacheScope(userID: userID, householdID: household.id, language: "sv") }

    private func makeStore(
        api: DiskCacheShoppingAPIClient,
        cache: any ShoppingListStoreCachePersisting,
        userID: String? = "33333333-3333-3333-3333-333333333333",
        language: String = "sv"
    ) -> ShoppingListStore {
        ShoppingListStore(
            apiClient: api,
            syncDebounceNanoseconds: 0,
            retryDelayNanoseconds: 60_000_000_000,
            cacheStore: cache,
            currentUserID: { userID },
            currentLanguage: { language }
        )
    }

    private func summary(household: Household? = nil, week: String? = nil, labels: [String] = ["Mjölk", "Pasta"], updatedAt: String = "s1") -> ShoppingListSummary {
        ShoppingListSummary(
            household: SummaryHousehold(id: (household ?? self.household).id, name: "Test household"),
            weekStartDate: week ?? self.week,
            updatedAt: updatedAt,
            groups: [
                ShoppingListGroup(category: "Dairy", items: labels.map {
                    ShoppingListItem(itemKey: "dairy:\($0.lowercased()):", label: $0, amount: nil, unit: nil, checked: false)
                }),
            ]
        )
    }

    private func snapshot(
        _ summary: ShoppingListSummary,
        checked: [String] = [],
        pantry: [String: Double] = [:],
        stateUpdatedAt: String? = "s1",
        categoryOrder: [String]? = nil
    ) -> ShoppingListSnapshot {
        ShoppingListSnapshot(
            summary: summary,
            state: ShoppingListSharedState(checkedItems: checked, pantryStock: pantry, customItems: []),
            stateUpdatedAt: stateUpdatedAt,
            categoryOrder: categoryOrder
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ShoppingListStoreDiskCacheTests-\(UUID().uuidString)", isDirectory: true)
    }

    // MARK: Cold start

    @Test func theCachedListIsOnScreenBeforeTheNetworkAnswers() async {
        let cache = InMemoryShoppingCache()
        cache.seed(snapshot(summary(), checked: ["dairy:pasta:"], categoryOrder: ["dairy", "produce", "protein", "pantry", "frozen", "bakery", "other"]), scope: scope)
        let api = DiskCacheShoppingAPIClient()
        api.holdFetches = true
        let store = makeStore(api: api, cache: cache)

        let load = Task { await store.loadCurrentWeek(household: household, weekStartDate: week) }
        await api.waitUntilFetchStarted()

        #expect(store.groups.flatMap(\.items).map(\.label).sorted() == ["Mjölk", "Pasta"])
        #expect(store.checkedItems == ["dairy:pasta:"])
        #expect(store.categoryOrder.first == .dairy)
        #expect(!store.isLoading)
        #expect(store.errorMessage == nil)

        api.releaseFetches()
        await load.value
    }

    @Test func restoringWithoutTheNetworkShowsTheCachedList() {
        let cache = InMemoryShoppingCache()
        cache.seed(snapshot(summary()), scope: scope)
        let store = makeStore(api: DiskCacheShoppingAPIClient(), cache: cache)

        store.restoreCurrentWeekFromCache(household: household, weekStartDate: week)

        #expect(store.groups.flatMap(\.items).count == 2)
        #expect(store.hasLoadedOnce)
        #expect(store.isShowingRestoredList)
    }

    @Test func aSuccessfulFetchIsWrittenToDisk() async {
        let cache = InMemoryShoppingCache()
        let api = DiskCacheShoppingAPIClient()
        api.summary = summary(updatedAt: "s7")
        api.state = ShoppingListSharedState(checkedItems: ["dairy:pasta:"], pantryStock: ["pantry:rice:g": 250], customItems: [])
        api.stateUpdatedAt = "t7"
        let store = makeStore(api: api, cache: cache)

        await store.loadCurrentWeek(household: household, weekStartDate: week)

        let saved = cache.load(scope: scope, week: week)
        #expect(saved?.summary.updatedAt == "s7")
        #expect(saved?.state?.checkedItems == ["dairy:pasta:"])
        #expect(saved?.state?.pantryStock == ["pantry:rice:g": 250])
        #expect(saved?.stateUpdatedAt == "t7")
        #expect(saved?.categoryOrder == ShoppingCategory.allCases.map(\.preferenceValue))
        #expect(!store.isShowingRestoredList)
    }

    @Test func withoutAUserNothingIsReadOrWritten() async {
        let cache = InMemoryShoppingCache()
        cache.seed(snapshot(summary()), scope: scope)
        let api = DiskCacheShoppingAPIClient()
        api.holdFetches = true
        let store = makeStore(api: api, cache: cache, userID: nil)

        let load = Task { await store.loadCurrentWeek(household: household, weekStartDate: week) }
        await api.waitUntilFetchStarted()
        #expect(store.summary == nil)
        #expect(store.isLoading)

        api.releaseFetches()
        await load.value
        #expect(cache.saveCount == 0)
        #expect(cache.loadCount == 0)
    }

    @Test func aFailedFetchKeepsTheCachedListAndShowsNoError() async {
        let cache = InMemoryShoppingCache()
        cache.seed(snapshot(summary()), scope: scope)
        let api = DiskCacheShoppingAPIClient()
        api.failure = URLError(.cannotConnectToHost)
        let store = makeStore(api: api, cache: cache)

        await store.loadCurrentWeek(household: household, weekStartDate: week, force: true)

        #expect(store.groups.flatMap(\.items).count == 2)
        #expect(store.errorMessage == nil)
        #expect(store.isShowingRestoredList)
    }

    @Test func aFailedFetchWithoutACacheStillShowsTheError() async {
        let api = DiskCacheShoppingAPIClient()
        api.failure = URLError(.cannotConnectToHost)
        let store = makeStore(api: api, cache: InMemoryShoppingCache())

        await store.loadCurrentWeek(household: household, weekStartDate: week)

        #expect(store.summary == nil)
        #expect(store.errorMessage != nil)
    }

    // MARK: Misses

    @Test func anotherUsersOrLanguagesCacheIsAMiss() async {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = ShoppingListStoreDiskCache(baseDirectory: directory)
        disk.saveList(snapshot(summary()), scope: scope)

        for (user, language) in [("someone-else", "sv"), (userID, "en")] {
            let api = DiskCacheShoppingAPIClient()
            api.holdFetches = true
            let store = makeStore(api: api, cache: disk, userID: user, language: language)

            let load = Task { await store.loadCurrentWeek(household: household, weekStartDate: week) }
            await api.waitUntilFetchStarted()
            #expect(store.summary == nil)
            #expect(store.isLoading)

            api.releaseFetches()
            await load.value
        }
    }

    @Test func aListFiledUnderTheWrongWeekOrHouseholdIsAMiss() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = ShoppingListStoreDiskCache(baseDirectory: directory)
        let raw = HouseholdWeekDiskCache<ShoppingListSnapshot>(folder: "shopping-lists", baseDirectory: directory)
        raw.save(snapshot(summary(household: otherHousehold)), scope: scope, weekStartDate: week)
        #expect(disk.loadList(scope: scope, weekStartDate: week) == nil)

        raw.save(snapshot(summary(week: "2026-10-12")), scope: scope, weekStartDate: week)
        #expect(disk.loadList(scope: scope, weekStartDate: week) == nil)
    }

    @Test func aFileThatCannotBeDecodedIsAMiss() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let folder = directory.appendingPathComponent("Veckly/shopping-lists", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("{ broken".utf8).write(to: folder.appendingPathComponent("\(household.id).json"))
        let api = DiskCacheShoppingAPIClient()
        api.holdFetches = true
        let store = makeStore(api: api, cache: ShoppingListStoreDiskCache(baseDirectory: directory))

        let load = Task { await store.loadCurrentWeek(household: household, weekStartDate: week) }
        await api.waitUntilFetchStarted()
        #expect(store.summary == nil)
        #expect(store.isLoading)

        api.releaseFetches()
        await load.value
        #expect(store.summary != nil)
    }

    @Test func anotherHouseholdsCachedListIsNeverShown() async {
        let cache = InMemoryShoppingCache()
        let api = DiskCacheShoppingAPIClient()
        api.summary = summary()
        let store = makeStore(api: api, cache: cache)
        await store.loadCurrentWeek(household: household, weekStartDate: week)
        #expect(store.summary?.household.id == household.id)

        api.summary = summary(household: otherHousehold, labels: ["Annat"])
        api.holdNextFetch()
        let load = Task { await store.loadCurrentWeek(household: otherHousehold, weekStartDate: week, force: true) }
        await api.waitUntilFetchStarted()

        #expect(store.summary == nil)
        #expect(store.groups.isEmpty)

        api.releaseFetches()
        await load.value
        #expect(store.groups.flatMap(\.items).map(\.label) == ["Annat"])
    }

    // MARK: Writes

    @Test func aSyncedCheckIsWrittenToDisk() async throws {
        let cache = InMemoryShoppingCache()
        let api = DiskCacheShoppingAPIClient()
        api.summary = summary()
        let store = makeStore(api: api, cache: cache)
        await store.loadCurrentWeek(household: household, weekStartDate: week)

        store.setItemChecked(key: "dairy:pasta:", isChecked: true)
        try await waitUntil { !store.hasPendingSync }

        let saved = cache.load(scope: scope, week: week)
        #expect(saved?.state?.checkedItems == ["dairy:pasta:"])
        #expect(saved?.stateUpdatedAt == api.stateUpdatedAt)
    }

    @Test func invalidatingTheListAlsoDropsTheDiskCopy() async {
        let cache = InMemoryShoppingCache()
        let api = DiskCacheShoppingAPIClient()
        api.summary = summary()
        let store = makeStore(api: api, cache: cache)
        await store.loadCurrentWeek(household: household, weekStartDate: week)
        #expect(cache.load(scope: scope, week: week) != nil)

        store.invalidateCache()

        #expect(cache.load(scope: scope, week: week) == nil)
    }

    @Test func clearingThePersistedCacheDeletesEverything() {
        let cache = InMemoryShoppingCache()
        cache.seed(snapshot(summary()), scope: scope)
        let store = makeStore(api: DiskCacheShoppingAPIClient(), cache: cache)

        store.clearPersistedCache()

        #expect(cache.isEmpty)
    }

    // MARK: Writing from an out-of-date cache

    @Test func aCheckBuiltOnTheCachedListTakesTheExistingStaleRecoveryAndKeepsTheServersChanges() async throws {
        let cache = InMemoryShoppingCache()
        cache.seed(snapshot(summary(), checked: [], stateUpdatedAt: "t0"), scope: scope)
        let api = DiskCacheShoppingAPIClient()
        api.summary = summary()
        // Someone else checked Mjölk and stocked rice since the cache was written.
        api.state = ShoppingListSharedState(checkedItems: ["dairy:mjölk:"], pantryStock: ["pantry:rice:g": 250], customItems: [])
        api.stateUpdatedAt = "t3"
        api.requiresMatchingStateVersion = true
        let store = makeStore(api: api, cache: cache)
        // Unreachable network: the screen shows the cached v0 list.
        api.failure = URLError(.notConnectedToInternet)
        await store.loadCurrentWeek(household: household, weekStartDate: week, force: true)
        #expect(store.checkedItems.isEmpty)
        api.failure = nil

        store.setItemChecked(key: "dairy:pasta:", isChecked: true)
        try await waitUntil { !store.hasPendingSync }

        // First write used the cached version and was rejected; the retry was
        // built on the server's current state, so nothing was overwritten.
        #expect(api.updateAttempts.map(\.expectedUpdatedAt) == ["t0", "t3"])
        #expect(api.state?.checkedItems.sorted() == ["dairy:mjölk:", "dairy:pasta:"])
        #expect(api.state?.pantryStock == ["pantry:rice:g": 250])
        #expect(store.checkedItems == ["dairy:mjölk:", "dairy:pasta:"])
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<200 where !condition() {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(condition())
    }
}

// MARK: - Fakes

private final class InMemoryShoppingCache: ShoppingListStoreCachePersisting {
    private var entries: [String: ShoppingListSnapshot] = [:]
    private(set) var saveCount = 0
    private(set) var loadCount = 0

    var isEmpty: Bool { entries.isEmpty }

    private func key(_ scope: CacheScope, _ week: String) -> String {
        "\(scope.userID)|\(scope.householdID)|\(scope.language)|\(week)"
    }

    func seed(_ snapshot: ShoppingListSnapshot, scope: CacheScope) {
        entries[key(scope, snapshot.summary.weekStartDate)] = snapshot
    }

    func load(scope: CacheScope, week: String) -> ShoppingListSnapshot? { entries[key(scope, week)] }

    func loadList(scope: CacheScope, weekStartDate: String) -> ShoppingListSnapshot? {
        loadCount += 1
        return load(scope: scope, week: weekStartDate)
    }

    func saveList(_ snapshot: ShoppingListSnapshot, scope: CacheScope) {
        saveCount += 1
        seed(snapshot, scope: scope)
    }

    func removeList(scope: CacheScope, weekStartDate: String) {
        entries.removeValue(forKey: key(scope, weekStartDate))
    }

    func deleteAll() { entries = [:] }
}

private final class DiskCacheShoppingAPIClient: ShoppingListStoreAPIClient {
    struct UpdateAttempt { let expectedUpdatedAt: String? }

    var summary = ShoppingListSummary(
        household: SummaryHousehold(id: "11111111-1111-1111-1111-111111111111", name: "Test household"),
        weekStartDate: "2026-10-05",
        updatedAt: "s0",
        groups: []
    )
    var state: ShoppingListSharedState?
    var stateUpdatedAt: String? = "t1"
    var failure: Error?
    var holdFetches = false
    var requiresMatchingStateVersion = false
    private(set) var fetchStarted = false
    private(set) var updateAttempts: [UpdateAttempt] = []
    private var version = 100

    func waitUntilFetchStarted() async {
        while !fetchStarted { await Task.yield() }
    }

    func releaseFetches() { holdFetches = false }

    func holdNextFetch() {
        fetchStarted = false
        holdFetches = true
    }

    func shoppingListSummary(householdID: String, weekStartDate: String) async throws -> ShoppingListSummary {
        fetchStarted = true
        while holdFetches { await Task.yield() }
        if let failure { throw failure }
        return summary
    }

    func shoppingListState(householdID: String, weekStartDate: String) async throws -> (state: ShoppingListSharedState?, updatedAt: String?) {
        if let failure { throw failure }
        return (state, stateUpdatedAt)
    }

    func updateShoppingListState(
        householdID: String,
        weekStartDate: String,
        checkedItems: [String],
        pantryStock: [String: Double],
        expectedUpdatedAt: String?,
        customItems: [ShoppingCustomItem]
    ) async throws -> String? {
        updateAttempts.append(UpdateAttempt(expectedUpdatedAt: expectedUpdatedAt))
        if requiresMatchingStateVersion, expectedUpdatedAt != stateUpdatedAt {
            throw APIError.stale(latestUpdatedAt: stateUpdatedAt)
        }
        version += 1
        stateUpdatedAt = "t\(version)"
        state = ShoppingListSharedState(checkedItems: checkedItems, pantryStock: pantryStock, customItems: customItems)
        return stateUpdatedAt
    }

    func shoppingPreferences(householdID: String) async throws -> ShoppingPreferences {
        ShoppingPreferences(categoryOrder: ShoppingCategory.allCases.map(\.preferenceValue), updatedAt: nil)
    }
}

import Foundation
import Testing
@testable import Veckly

/// "Updates available": a background refresh that differs from what is on
/// screen waits behind a banner instead of swapping the screen under the user.
@MainActor
struct WeekStorePendingUpdateTests {
    private let household = Household(id: "11111111-1111-1111-1111-111111111111", name: "Test household", role: .owner)
    private let otherHousehold = Household(id: "99999999-9999-9999-9999-999999999999", name: "Other", role: .owner)
    private let userID = "33333333-3333-3333-3333-333333333333"
    private var week: String { WeekCalendar.currentWeekStartDate() }

    private func makeStore(api: PendingWeekAPIClient, cache: PendingWeekCache = PendingWeekCache()) -> WeekStore {
        WeekStore(
            apiClient: api,
            syncDebounceNanoseconds: 0,
            retryDelayNanoseconds: 60_000_000_000,
            cacheStore: cache,
            currentUserID: { "33333333-3333-3333-3333-333333333333" },
            currentLanguage: { "sv" }
        )
    }

    private func titles(_ store: WeekStore) -> [String] { store.dayRows.map(\.mealTitle) }

    // Row 1
    @Test func whenNoCacheWasShownTheResponseIsAppliedDirectly() async {
        let api = PendingWeekAPIClient(titlePrefix: "A", version: "v1")
        let store = makeStore(api: api)

        await store.loadCurrentWeek(household: household)

        #expect(store.summary?.updatedAt == "v1")
        #expect(store.pendingUpdate == nil)
    }

    // Row 2
    @Test func anEqualResponseDoesNothing() async {
        let api = PendingWeekAPIClient(titlePrefix: "A", version: "v1")
        let store = makeStore(api: api)
        await store.loadCurrentWeek(household: household)

        await store.loadCurrentWeek(household: household, force: true)

        #expect(store.pendingUpdate == nil)
        #expect(store.summary?.updatedAt == "v1")
    }

    // Row 3
    @Test func aDifferingResponseWaitsAsAPendingUpdateAndLeavesTheScreenAlone() async {
        let api = PendingWeekAPIClient(titlePrefix: "A", version: "v1")
        let store = makeStore(api: api)
        await store.loadCurrentWeek(household: household)
        let before = titles(store)
        api.titlePrefix = "B"
        api.version = "v2"

        await store.loadCurrentWeek(household: household, force: true)

        #expect(titles(store) == before)
        #expect(store.summary?.updatedAt == "v1")
        #expect(store.pendingUpdate?.value.updatedAt == "v2")
        #expect(store.hasPendingUpdate(for: week))
        #expect(!store.hasPendingUpdate(for: WeekCalendar.addWeeks(to: week, offset: 1)))
    }

    // Row 4
    @Test func tappingTheBannerAppliesThePendingUpdateAndClearsIt() async {
        let api = PendingWeekAPIClient(titlePrefix: "A", version: "v1")
        let store = makeStore(api: api)
        await store.loadCurrentWeek(household: household)
        api.titlePrefix = "B"
        api.version = "v2"
        await store.loadCurrentWeek(household: household, force: true)

        store.applyPendingUpdate()

        #expect(store.summary?.updatedAt == "v2")
        #expect(titles(store).allSatisfy { $0.hasPrefix("B") })
        #expect(store.pendingUpdate == nil)
    }

    // Row 5
    @Test func pullToRefreshAppliesDirectlyAndDropsAnyPendingUpdate() async {
        let api = PendingWeekAPIClient(titlePrefix: "A", version: "v1")
        let store = makeStore(api: api)
        await store.loadCurrentWeek(household: household)
        api.titlePrefix = "B"
        api.version = "v2"
        await store.loadCurrentWeek(household: household, force: true)
        #expect(store.pendingUpdate != nil)
        api.titlePrefix = "C"
        api.version = "v3"

        await store.loadCurrentWeek(household: household, force: true, origin: .userInitiated)

        #expect(store.summary?.updatedAt == "v3")
        #expect(store.pendingUpdate == nil)
    }

    // Row 6
    @Test func anOwnMutationAppliesItsResponseAndDiscardsAnOlderPendingUpdate() async throws {
        let api = PendingWeekAPIClient(titlePrefix: "A", version: "v1")
        let store = makeStore(api: api)
        await store.loadCurrentWeek(household: household)
        api.titlePrefix = "B"
        api.version = "v2"
        await store.loadCurrentWeek(household: household, force: true)
        #expect(store.pendingUpdate?.value.updatedAt == "v2")
        api.titlePrefix = "C"
        api.version = "v3"
        let monday = try #require(store.dayRows.first { $0.weekday == .monday })

        await store.unassignMeal(day: monday, household: household, userID: userID)

        #expect(store.summary?.updatedAt == "v3")
        #expect(store.pendingUpdate == nil)
    }

    // Row 7
    @Test func aFailedBackgroundRefreshKeepsTheCachedWeekWithoutAnError() async {
        let api = PendingWeekAPIClient(titlePrefix: "A", version: "v1")
        let store = makeStore(api: api)
        await store.loadCurrentWeek(household: household)
        api.failure = URLError(.notConnectedToInternet)

        await store.loadCurrentWeek(household: household, force: true)

        #expect(store.summary?.updatedAt == "v1")
        #expect(store.errorMessage == nil)
        #expect(store.pendingUpdate == nil)
    }

    @Test func aFailedBackgroundRefreshKeepsAnExistingPendingUpdate() async {
        let api = PendingWeekAPIClient(titlePrefix: "A", version: "v1")
        let store = makeStore(api: api)
        await store.loadCurrentWeek(household: household)
        api.titlePrefix = "B"
        api.version = "v2"
        await store.loadCurrentWeek(household: household, force: true)
        api.failure = URLError(.notConnectedToInternet)

        await store.loadCurrentWeek(household: household, force: true)

        #expect(store.pendingUpdate?.value.updatedAt == "v2")
        #expect(store.errorMessage == nil)
    }

    // Row 8
    @Test func browsingToAnotherWeekDiscardsThePendingUpdate() async {
        let api = PendingWeekAPIClient(titlePrefix: "A", version: "v1")
        let store = makeStore(api: api)
        await store.loadCurrentWeek(household: household)
        api.titlePrefix = "B"
        api.version = "v2"
        await store.loadCurrentWeek(household: household, force: true)
        #expect(store.pendingUpdate != nil)

        await store.loadWeek(household: household, weekStartDate: WeekCalendar.addWeeks(to: week, offset: 1))

        #expect(store.pendingUpdate == nil)
    }

    @Test func switchingHouseholdDiscardsThePendingUpdate() async {
        let api = PendingWeekAPIClient(titlePrefix: "A", version: "v1")
        let store = makeStore(api: api)
        await store.loadCurrentWeek(household: household)
        api.titlePrefix = "B"
        api.version = "v2"
        await store.loadCurrentWeek(household: household, force: true)
        #expect(store.pendingUpdate != nil)

        await store.loadCurrentWeek(household: otherHousehold, force: true)

        #expect(store.pendingUpdate == nil)
    }

    @Test func resettingDiscardsThePendingUpdate() async {
        let api = PendingWeekAPIClient(titlePrefix: "A", version: "v1")
        let store = makeStore(api: api)
        await store.loadCurrentWeek(household: household)
        api.titlePrefix = "B"
        api.version = "v2"
        await store.loadCurrentWeek(household: household, force: true)

        store.reset()

        #expect(store.pendingUpdate == nil)
    }

    // Further behavior around the table
    @Test func aResponseThatMatchesTheScreenAgainDropsTheStalePendingUpdate() async {
        let api = PendingWeekAPIClient(titlePrefix: "A", version: "v1")
        let store = makeStore(api: api)
        await store.loadCurrentWeek(household: household)
        api.titlePrefix = "B"
        api.version = "v2"
        await store.loadCurrentWeek(household: household, force: true)
        api.titlePrefix = "A"
        api.version = "v1"

        await store.loadCurrentWeek(household: household, force: true)

        #expect(store.pendingUpdate == nil)
    }

    @Test func aNewerDifferingResponseReplacesThePendingUpdate() async {
        let api = PendingWeekAPIClient(titlePrefix: "A", version: "v1")
        let store = makeStore(api: api)
        await store.loadCurrentWeek(household: household)
        api.titlePrefix = "B"
        api.version = "v2"
        await store.loadCurrentWeek(household: household, force: true)
        api.titlePrefix = "C"
        api.version = "v3"

        await store.loadCurrentWeek(household: household, force: true)

        #expect(store.pendingUpdate?.value.updatedAt == "v3")
        #expect(store.summary?.updatedAt == "v1")
    }

    @Test func aDeferredResponseIsStillWrittenToDisk() async {
        let cache = PendingWeekCache()
        let api = PendingWeekAPIClient(titlePrefix: "A", version: "v1")
        let store = makeStore(api: api, cache: cache)
        await store.loadCurrentWeek(household: household)
        api.titlePrefix = "B"
        api.version = "v2"

        await store.loadCurrentWeek(household: household, force: true)

        #expect(cache.latest?.updatedAt == "v2")
    }

    @Test func aCachedWeekRestoredFromDiskIsAlsoProtectedFromASilentSwap() async {
        let cache = PendingWeekCache()
        let restored = PendingWeekAPIClient.makeSummary(householdID: household.id, week: week, titlePrefix: "Disk", version: "d1")
        cache.latest = restored
        let api = PendingWeekAPIClient(titlePrefix: "Net", version: "n1")
        let store = makeStore(api: api, cache: cache)

        await store.loadCurrentWeek(household: household)

        #expect(store.summary?.updatedAt == "d1")
        #expect(store.pendingUpdate?.value.updatedAt == "n1")
    }
}

private final class PendingWeekCache: WeekStoreCachePersisting {
    var latest: WeekSummary?
    func loadWeek(scope: CacheScope, weekStartDate: String) -> WeekSummary? {
        latest?.weekStartDate == weekStartDate && latest?.household.id == scope.householdID ? latest : nil
    }
    func saveWeek(_ summary: WeekSummary, scope: CacheScope) { latest = summary }
    func removeWeek(scope: CacheScope, weekStartDate: String) { if latest?.weekStartDate == weekStartDate { latest = nil } }
    func deleteAll() { latest = nil }
}

private final class PendingWeekAPIClient: WeekStoreAPIClient {
    var titlePrefix: String
    var version: String
    var failure: Error?

    init(titlePrefix: String, version: String) {
        self.titlePrefix = titlePrefix
        self.version = version
    }

    static func makeSummary(householdID: String, week: String, titlePrefix: String, version: String) -> WeekSummary {
        WeekSummary(
            household: SummaryHousehold(id: householdID, name: "Test household"),
            weekStartDate: week,
            updatedAt: version,
            days: Weekday.allCases.enumerated().map { index, weekday in
                WeekSummaryDay(
                    dayOfWeek: weekday,
                    date: WeekCalendar.addDays(to: week, offset: index),
                    state: .planned,
                    recipe: WeekSummaryRecipe(id: "r\(index)", title: "\(titlePrefix) \(index)", description: "", servings: 4, prepTimeMinutes: 10, cookTimeMinutes: 10, tags: [])
                )
            }
        )
    }

    func weekSummary(householdID: String, weekStartDate: String) async throws -> WeekSummary {
        if let failure { throw failure }
        return Self.makeSummary(householdID: householdID, week: weekStartDate, titlePrefix: titlePrefix, version: version)
    }

    func appendWeekPlanEvent(householdID: String, weekStartDate: String, userID: String, event: WeekPlanEventInput) async throws {}
    func generateWeekPlan(householdID: String, weekStartDate: String, regenerate: Bool) async throws {}
    func recipe(householdID: String, recipeID: String) async throws -> FullRecipe { throw APIError.notFound }
}

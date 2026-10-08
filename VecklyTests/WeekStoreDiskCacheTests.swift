import Foundation
import Testing
@testable import Veckly

/// Cold start: the week the household last saw is on screen before the
/// network answers, and every authoritative response is written back.
@MainActor
struct WeekStoreDiskCacheTests {
    private let household = Household(id: "11111111-1111-1111-1111-111111111111", name: "Test household", role: .owner)
    private let otherHousehold = Household(id: "99999999-9999-9999-9999-999999999999", name: "Other household", role: .owner)
    private let userID = "33333333-3333-3333-3333-333333333333"
    private var scope: CacheScope { CacheScope(userID: userID, householdID: household.id, language: "sv") }

    private func makeStore(
        api: DiskCacheWeekAPIClient,
        cache: any WeekStoreCachePersisting,
        userID: String? = "33333333-3333-3333-3333-333333333333",
        language: String = "sv"
    ) -> WeekStore {
        WeekStore(
            apiClient: api,
            syncDebounceNanoseconds: 0,
            retryDelayNanoseconds: 60_000_000_000,
            cacheStore: cache,
            currentUserID: { userID },
            currentLanguage: { language }
        )
    }

    private func summary(_ version: String, household: Household? = nil, titlePrefix: String = "Recipe") -> WeekSummary {
        DiskCacheWeekAPIClient.makeSummary(
            householdID: (household ?? self.household).id,
            weekStartDate: WeekCalendar.currentWeekStartDate(),
            version: version,
            titlePrefix: titlePrefix
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("WeekStoreDiskCacheTests-\(UUID().uuidString)", isDirectory: true)
    }

    // MARK: Cold start

    @Test func theCachedWeekIsOnScreenBeforeTheNetworkAnswers() async {
        let cache = InMemoryWeekCache()
        cache.seed(summary("v1"), scope: scope)
        let api = DiskCacheWeekAPIClient()
        api.holdFetches = true
        let store = makeStore(api: api, cache: cache)

        let load = Task { await store.loadCurrentWeek(household: household) }
        await api.waitUntilFetchStarted()

        #expect(store.summary?.updatedAt == "v1")
        #expect(!store.dayRows.isEmpty)
        #expect(!store.isLoading)
        #expect(store.errorMessage == nil)

        api.releaseFetches()
        await load.value
    }

    @Test func aSuccessfulFetchIsWrittenToDisk() async {
        let cache = InMemoryWeekCache()
        let api = DiskCacheWeekAPIClient()
        api.response = summary("v7")
        let store = makeStore(api: api, cache: cache)

        await store.loadCurrentWeek(household: household)

        #expect(cache.saved.map(\.summary.updatedAt) == ["v7"])
        #expect(cache.saved.first?.scope == scope)
        #expect(cache.load(scope: scope, week: WeekCalendar.currentWeekStartDate())?.updatedAt == "v7")
    }

    @Test func withoutAUserNothingIsReadOrWritten() async {
        let cache = InMemoryWeekCache()
        cache.seed(summary("v1"), scope: scope)
        let api = DiskCacheWeekAPIClient()
        api.holdFetches = true
        let store = makeStore(api: api, cache: cache, userID: nil)

        let load = Task { await store.loadCurrentWeek(household: household) }
        await api.waitUntilFetchStarted()
        #expect(store.summary == nil)
        #expect(store.isLoading)

        api.releaseFetches()
        await load.value
        #expect(cache.saved.isEmpty)
        #expect(cache.loadCount == 0)
    }

    @Test func aFailedFetchKeepsTheCachedWeekAndShowsNoError() async {
        let cache = InMemoryWeekCache()
        cache.seed(summary("v1"), scope: scope)
        let api = DiskCacheWeekAPIClient()
        api.failure = URLError(.cannotConnectToHost)
        let store = makeStore(api: api, cache: cache)

        await store.loadCurrentWeek(household: household, force: true)

        #expect(store.summary?.updatedAt == "v1")
        #expect(store.errorMessage == nil)
        #expect(!store.dayRows.isEmpty)
        #expect(store.hasLoadedOnce)
    }

    @Test func aFailedFetchWithoutACacheStillShowsTheError() async {
        let api = DiskCacheWeekAPIClient()
        api.failure = URLError(.cannotConnectToHost)
        let store = makeStore(api: api, cache: InMemoryWeekCache())

        await store.loadCurrentWeek(household: household)

        #expect(store.summary == nil)
        #expect(store.errorMessage != nil)
    }

    // MARK: Misses

    @Test func anotherUsersCacheIsAMiss() async {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = WeekStoreDiskCache(baseDirectory: directory)
        disk.saveWeek(summary("v1"), scope: scope)
        let api = DiskCacheWeekAPIClient()
        api.holdFetches = true
        let store = makeStore(api: api, cache: disk, userID: "someone-else")

        let load = Task { await store.loadCurrentWeek(household: household) }
        await api.waitUntilFetchStarted()
        #expect(store.summary == nil)
        #expect(store.isLoading)

        api.releaseFetches()
        await load.value
    }

    @Test func aCacheWrittenInAnotherLanguageIsAMiss() async {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = WeekStoreDiskCache(baseDirectory: directory)
        disk.saveWeek(summary("v1"), scope: scope)
        let api = DiskCacheWeekAPIClient()
        api.holdFetches = true
        let store = makeStore(api: api, cache: disk, language: "en")

        let load = Task { await store.loadCurrentWeek(household: household) }
        await api.waitUntilFetchStarted()
        #expect(store.summary == nil)

        api.releaseFetches()
        await load.value
    }

    @Test func aSummaryForAnotherWeekOrHouseholdIsAMiss() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = WeekStoreDiskCache(baseDirectory: directory)
        let week = WeekCalendar.currentWeekStartDate()
        // Stored under this household's file, but the payload belongs to another household.
        HouseholdWeekDiskCache<WeekSummary>(folder: "week-summaries", baseDirectory: directory)
            .save(summary("v1", household: otherHousehold), scope: scope, weekStartDate: week)
        #expect(disk.loadWeek(scope: scope, weekStartDate: week) == nil)

        // Stored under another week's key, but the payload is for this week.
        HouseholdWeekDiskCache<WeekSummary>(folder: "week-summaries", baseDirectory: directory)
            .save(summary("v1"), scope: scope, weekStartDate: "2000-01-03")
        #expect(disk.loadWeek(scope: scope, weekStartDate: "2000-01-03") == nil)
    }

    @Test func aFileThatCannotBeDecodedIsAMiss() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let folder = directory.appendingPathComponent("Veckly/week-summaries", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("{ broken".utf8).write(to: folder.appendingPathComponent("\(household.id).json"))
        let api = DiskCacheWeekAPIClient()
        api.holdFetches = true
        let store = makeStore(api: api, cache: WeekStoreDiskCache(baseDirectory: directory))

        let load = Task { await store.loadCurrentWeek(household: household) }
        await api.waitUntilFetchStarted()
        #expect(store.summary == nil)
        #expect(store.isLoading)

        api.releaseFetches()
        await load.value
        #expect(store.summary != nil)
    }

    @Test func anotherHouseholdsCachedWeekIsNeverShown() async {
        let cache = InMemoryWeekCache()
        let api = DiskCacheWeekAPIClient()
        api.response = summary("v1")
        let store = makeStore(api: api, cache: cache)
        await store.loadCurrentWeek(household: household)
        #expect(store.summary?.household.id == household.id)

        api.response = summary("v1", household: otherHousehold, titlePrefix: "Other")
        api.holdNextFetch()
        let load = Task { await store.loadCurrentWeek(household: otherHousehold, force: true) }
        await api.waitUntilFetchStarted()

        #expect(store.summary == nil)
        #expect(store.dayRows.isEmpty)

        api.releaseFetches()
        await load.value
        #expect(store.summary?.household.id == otherHousehold.id)
    }

    // MARK: Writes after mutations

    @Test func aMutationWritesTheRefreshedWeekToDisk() async throws {
        let cache = InMemoryWeekCache()
        let api = DiskCacheWeekAPIClient()
        api.response = summary("v0")
        let store = makeStore(api: api, cache: cache)
        await store.loadCurrentWeek(household: household)
        api.response = summary("v1")
        let monday = try #require(store.dayRows.first { $0.weekday == .monday })

        await store.unassignMeal(day: monday, household: household, userID: userID)

        #expect(cache.load(scope: scope, week: WeekCalendar.currentWeekStartDate())?.updatedAt == "v1")
    }

    @Test func aMutationWhoseRefetchFailsLeavesNoStaleEntryOnDisk() async throws {
        let cache = InMemoryWeekCache()
        let api = DiskCacheWeekAPIClient()
        api.response = summary("v0")
        let store = makeStore(api: api, cache: cache)
        await store.loadCurrentWeek(household: household)
        #expect(cache.load(scope: scope, week: WeekCalendar.currentWeekStartDate())?.updatedAt == "v0")
        api.failure = URLError(.notConnectedToInternet)
        let monday = try #require(store.dayRows.first { $0.weekday == .monday })

        await store.unassignMeal(day: monday, household: household, userID: userID)

        #expect(cache.load(scope: scope, week: WeekCalendar.currentWeekStartDate()) == nil)
    }

    @Test func clearingThePersistedCacheDeletesEverything() {
        let cache = InMemoryWeekCache()
        cache.seed(summary("v1"), scope: scope)
        let store = makeStore(api: DiskCacheWeekAPIClient(), cache: cache)

        store.clearPersistedCache()

        #expect(cache.isEmpty)
    }

    // MARK: Writing from an out-of-date cache

    @Test func aPreviewBuiltOnTheCachedSummaryTakesTheExistingStaleRecoveryAndWritesNothing() async throws {
        let cache = InMemoryWeekCache()
        cache.seed(summary("v0"), scope: scope)
        let api = DiskCacheWeekAPIClient()
        api.response = summary("v3") // someone else changed the week since the cache was written
        api.requiresMatchingVersionForPreview = true
        let store = makeStore(api: api, cache: cache)
        // The network is unreachable at first: the screen shows the cached v0.
        api.failure = URLError(.notConnectedToInternet)
        await store.loadCurrentWeek(household: household, force: true)
        #expect(store.summary?.updatedAt == "v0")
        api.failure = nil
        let monday = try #require(store.dayRows.first { $0.weekday == .monday })

        let preview = try await store.previewRescue(
            day: monday, household: household, weekStartDate: store.weekStartDate,
            intent: .quick, missingIngredient: "", rescueID: "rescue",
            expectedUpdatedAt: store.summary?.updatedAt
        )

        #expect(api.previewExpectedVersions == ["v0", "v3"])
        #expect(preview.expectedUpdatedAt == "v3")
        #expect(api.writeCount == 0)
        #expect(store.summary?.updatedAt == "v3")
    }

    @Test func applyingAPreviewWithTheCachedVersionIsRejectedAsStaleAndDoesNotOverwrite() async throws {
        let api = DiskCacheWeekAPIClient()
        api.response = summary("v3")
        api.requiresMatchingVersionForApply = true
        let store = makeStore(api: api, cache: InMemoryWeekCache())
        await store.loadCurrentWeek(household: household)
        let monday = try #require(store.dayRows.first { $0.weekday == .monday })
        let outdated = WeekRescuePreview(
            rescueID: "rescue", intent: .quick,
            primaryChange: WeekRescueChange(date: monday.date, beforeTitle: "A", afterTitle: "B", beforeServings: 4, afterServings: 4),
            followUpChanges: [], addedShoppingItems: [], removedShoppingItems: [],
            expectedUpdatedAt: "v0"
        )

        do {
            try await store.applyRescue(day: monday, household: household, weekStartDate: store.weekStartDate, preview: outdated, missingIngredient: "")
            Issue.record("Expected a stale rejection")
        } catch {
            #expect(WeekStore.isStaleWeekPlan(error))
        }
        #expect(api.writeCount == 0)
    }
}

// MARK: - Fakes

private final class InMemoryWeekCache: WeekStoreCachePersisting {
    struct Saved { let summary: WeekSummary; let scope: CacheScope }
    private var entries: [String: WeekSummary] = [:]
    private(set) var saved: [Saved] = []
    private(set) var loadCount = 0

    var isEmpty: Bool { entries.isEmpty }

    private func key(_ scope: CacheScope, _ week: String) -> String {
        "\(scope.userID)|\(scope.householdID)|\(scope.language)|\(week)"
    }

    func seed(_ summary: WeekSummary, scope: CacheScope) {
        entries[key(scope, summary.weekStartDate)] = summary
    }

    func load(scope: CacheScope, week: String) -> WeekSummary? { entries[key(scope, week)] }

    func loadWeek(scope: CacheScope, weekStartDate: String) -> WeekSummary? {
        loadCount += 1
        return load(scope: scope, week: weekStartDate)
    }

    func saveWeek(_ summary: WeekSummary, scope: CacheScope) {
        saved.append(Saved(summary: summary, scope: scope))
        seed(summary, scope: scope)
    }

    func removeWeek(scope: CacheScope, weekStartDate: String) {
        entries.removeValue(forKey: key(scope, weekStartDate))
    }

    func deleteAll() { entries = [:] }
}

private final class DiskCacheWeekAPIClient: WeekStoreAPIClient {
    var response: WeekSummary?
    var failure: Error?
    var holdFetches = false
    var requiresMatchingVersionForPreview = false
    var requiresMatchingVersionForApply = false
    private(set) var fetchStarted = false
    private(set) var previewExpectedVersions: [String?] = []
    private(set) var writeCount = 0

    static func makeSummary(householdID: String, weekStartDate: String, version: String, titlePrefix: String) -> WeekSummary {
        WeekSummary(
            household: SummaryHousehold(id: householdID, name: "Test household"),
            weekStartDate: weekStartDate,
            updatedAt: version,
            days: Weekday.allCases.enumerated().map { index, weekday in
                WeekSummaryDay(
                    dayOfWeek: weekday,
                    date: WeekCalendar.addDays(to: weekStartDate, offset: index),
                    state: .planned,
                    recipe: WeekSummaryRecipe(id: "r\(index)", title: "\(titlePrefix) \(index)", description: "", servings: 4, prepTimeMinutes: 10, cookTimeMinutes: 10, tags: [])
                )
            }
        )
    }

    func waitUntilFetchStarted() async {
        while !fetchStarted { await Task.yield() }
    }

    func releaseFetches() { holdFetches = false }

    func holdNextFetch() {
        fetchStarted = false
        holdFetches = true
    }

    func weekSummary(householdID: String, weekStartDate: String) async throws -> WeekSummary {
        fetchStarted = true
        while holdFetches { await Task.yield() }
        if let failure { throw failure }
        if let response, response.household.id == householdID { return response }
        return Self.makeSummary(householdID: householdID, weekStartDate: weekStartDate, version: "fresh", titlePrefix: "Fresh")
    }

    func appendWeekPlanEvent(householdID: String, weekStartDate: String, userID: String, event: WeekPlanEventInput) async throws {
        writeCount += 1
    }

    func generateWeekPlan(householdID: String, weekStartDate: String, regenerate: Bool) async throws { writeCount += 1 }
    func recipe(householdID: String, recipeID: String) async throws -> FullRecipe { throw APIError.notFound }

    func previewWeekRescue(
        householdID: String, weekStartDate: String, date: String,
        intent: WeekRescueIntent, missingIngredient: String?, rescueID: String,
        expectedUpdatedAt: String?
    ) async throws -> WeekRescuePreview {
        previewExpectedVersions.append(expectedUpdatedAt)
        if requiresMatchingVersionForPreview, expectedUpdatedAt != response?.updatedAt {
            throw APIError.server(statusCode: 409)
        }
        return WeekRescuePreview(
            rescueID: rescueID, intent: intent,
            primaryChange: WeekRescueChange(date: date, beforeTitle: "A", afterTitle: "B", beforeServings: 4, afterServings: 4),
            followUpChanges: [], addedShoppingItems: [], removedShoppingItems: [],
            expectedUpdatedAt: response?.updatedAt
        )
    }

    func applyWeekRescue(
        householdID: String, weekStartDate: String, date: String,
        intent: WeekRescueIntent, missingIngredient: String?, rescueID: String,
        expectedUpdatedAt: String?
    ) async throws {
        if requiresMatchingVersionForApply, expectedUpdatedAt != response?.updatedAt {
            throw APIError.server(statusCode: 409)
        }
        writeCount += 1
    }
}

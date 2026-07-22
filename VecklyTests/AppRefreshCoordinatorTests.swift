import Foundation
import Testing
@testable import Veckly

@MainActor
struct AppRefreshCoordinatorTests {
    @Test func coldLaunchMakesAtMostOneCallPerCoreResource() async {
        let apiClient = FakeAppRefreshAPIClient()
        let coordinator = TestCoordinatorFactory.make(apiClient: apiClient)

        await coordinator.refreshCoreReader(trigger: .coldLaunch)

        #expect(await apiClient.bootstrapCount == 1)
        #expect(await apiClient.listHouseholdsCount == 1)
        #expect(await apiClient.listMembersCount == 1)
        #expect(await apiClient.weekSummaryCount == 1)
        #expect(await apiClient.shoppingListSummaryCount == 1)
        #expect(await apiClient.listPrepBatchesCount == 1)
        #expect(await apiClient.mealFeedbackCount == 1)
        #expect(await apiClient.householdMealSignalsCount == 1)
        #expect(await apiClient.listHouseholdRecipesCount == 1)
    }

    /// "Suggestions for you" (`RecipeRecommendationStore`) is a ~10s AI call
    /// — starting it only once the user opens a day's meal picker is why the
    /// reason text used to pop in visibly late. It should instead be kicked
    /// off as soon as core-reader data (household profile + recipes) is
    /// ready, so it's usually done well before the picker ever opens.
    @Test func coreReaderRefreshPrefetchesRecipeRecommendationsInTheBackground() async {
        let apiClient = FakeAppRefreshAPIClient()
        let coordinator = TestCoordinatorFactory.make(apiClient: apiClient)

        await coordinator.refreshCoreReader(trigger: .coldLaunch)
        await apiClient.waitUntilRecommendMealsCalled()

        #expect(await apiClient.recommendMealsCount == 1)
    }

    /// The exact Fas 7 bug: `RootView`'s cold-launch bootstrap and
    /// `WeekTabView`'s own `.task(id:)` load used to both fire moments
    /// apart, each triggering a real `weekSummary` fetch for the same
    /// household/week. The coordinator's single-flight `run` must collapse
    /// two overlapping callers into one real network call.
    @Test func concurrentCallersForTheSameResourceCoalesceIntoOneNetworkCall() async {
        let apiClient = FakeAppRefreshAPIClient()
        await apiClient.pauseNextWeekSummary()
        let coordinator = TestCoordinatorFactory.make(apiClient: apiClient)

        let first = Task { await coordinator.refreshWeek(household: TestAppRefreshFixtures.household, trigger: .coldLaunch) }
        await apiClient.waitUntilWeekSummaryStarted()

        // A second, concurrent caller — e.g. a tab reappearing while the
        // cold-launch refresh is still in flight — must await the same
        // in-flight fetch rather than starting its own.
        let second = Task { await coordinator.refreshWeek(household: TestAppRefreshFixtures.household, trigger: .sceneActive) }

        await apiClient.resumeWeekSummary()
        await first.value
        await second.value

        #expect(await apiClient.weekSummaryCount == 1)
    }

    /// Acceptance: "Background → active coalesces concurrent refresh
    /// requests." Two `scenePhase`-active refreshes arriving close together
    /// (e.g. the app briefly leaving and re-entering the foreground) must
    /// not double-fetch every core resource.
    @Test func backgroundToActiveCoalescesConcurrentCoreReaderRefreshes() async {
        let apiClient = FakeAppRefreshAPIClient()
        await apiClient.pauseNextWeekSummary()
        let coordinator = TestCoordinatorFactory.make(apiClient: apiClient)

        let first = Task { await coordinator.refreshCoreReader(trigger: .sceneActive) }
        await apiClient.waitUntilWeekSummaryStarted()

        let second = Task { await coordinator.refreshCoreReader(trigger: .sceneActive) }

        await apiClient.resumeWeekSummary()
        await first.value
        await second.value

        #expect(await apiClient.bootstrapCount == 1)
        #expect(await apiClient.weekSummaryCount == 1)
    }

    /// `sceneActive` is the "no-op if fresh" trigger — a second scene-active
    /// refresh shortly after a completed one shouldn't touch the network at
    /// all, coalescing being the fallback for the concurrent case above.
    @Test func sceneActiveIsANoOpWhenCoreReaderDataIsFresh() async {
        let apiClient = FakeAppRefreshAPIClient()
        let coordinator = TestCoordinatorFactory.make(apiClient: apiClient)

        await coordinator.refreshCoreReader(trigger: .coldLaunch)
        await coordinator.refreshCoreReader(trigger: .sceneActive)

        #expect(await apiClient.bootstrapCount == 1)
        #expect(await apiClient.weekSummaryCount == 1)
    }

    /// `householdChanged` must force a real reload even moments after a
    /// fresh load — the underlying data changed (a different household),
    /// not just gone stale.
    @Test func householdChangedForcesARealReloadEvenWhenFresh() async {
        let apiClient = FakeAppRefreshAPIClient()
        let coordinator = TestCoordinatorFactory.make(apiClient: apiClient)

        await coordinator.refreshActiveHouseholdData(household: TestAppRefreshFixtures.household, trigger: .householdChanged)
        await coordinator.refreshActiveHouseholdData(household: TestAppRefreshFixtures.household, trigger: .householdChanged)

        #expect(await apiClient.weekSummaryCount == 2)
        #expect(await apiClient.shoppingListSummaryCount == 2)
    }

    /// `pullToRefresh` (the toolbar refresh button / an error retry) must
    /// also force a real reload, unlike `sceneActive`.
    @Test func pullToRefreshForcesARealReloadEvenWhenFresh() async {
        let apiClient = FakeAppRefreshAPIClient()
        let coordinator = TestCoordinatorFactory.make(apiClient: apiClient)

        await coordinator.refreshWeek(household: TestAppRefreshFixtures.household, trigger: .coldLaunch)
        await coordinator.refreshWeek(household: TestAppRefreshFixtures.household, trigger: .pullToRefresh)

        #expect(await apiClient.weekSummaryCount == 2)
    }

    /// Fas 7's centralized network-free gate: every coordinator method must
    /// no-op under seeded UI-test mode, regardless of trigger.
    @Test func seededCoreReaderModeMakesNoNetworkCalls() async {
        let apiClient = FakeAppRefreshAPIClient()
        let coordinator = TestCoordinatorFactory.make(apiClient: apiClient, usesSeededCoreReader: true)

        await coordinator.refreshCoreReader(trigger: .coldLaunch)
        await coordinator.refreshActiveHouseholdData(household: TestAppRefreshFixtures.household, trigger: .householdChanged)
        await coordinator.refreshWeek(household: TestAppRefreshFixtures.household, trigger: .pullToRefresh)

        #expect(await apiClient.bootstrapCount == 0)
        #expect(await apiClient.weekSummaryCount == 0)
        #expect(await apiClient.shoppingListSummaryCount == 0)
        #expect(await apiClient.listPrepBatchesCount == 0)
        #expect(await apiClient.mealFeedbackCount == 0)
        #expect(await apiClient.householdMealSignalsCount == 0)
        #expect(await apiClient.listHouseholdRecipesCount == 0)
    }

    /// `refreshWeek` shares its de-dup/freshness key with the `week`
    /// resource inside `refreshActiveHouseholdData` — a narrow tab request
    /// racing the full bundle must not double-fetch the same week.
    @Test func refreshWeekSharesItsFreshnessWithTheFullBundle() async {
        let apiClient = FakeAppRefreshAPIClient()
        let coordinator = TestCoordinatorFactory.make(apiClient: apiClient)

        await coordinator.refreshActiveHouseholdData(household: TestAppRefreshFixtures.household, trigger: .coldLaunch)
        await coordinator.refreshWeek(household: TestAppRefreshFixtures.household, trigger: .sceneActive)

        #expect(await apiClient.weekSummaryCount == 1)
    }

    /// The Last/Next-week-and-back regression: `WeekTabView`'s own
    /// `loadWeek` (Last/Next browsing) writes directly into `WeekStore`'s
    /// shared `summary`/`dayRows` slot — the same slot `refreshWeek` tracks
    /// freshness for — without going through this coordinator, so the
    /// coordinator can't see it happen on its own. `invalidateWeek` still
    /// makes sure the next `sceneActive` trigger actually *calls*
    /// `WeekStore.loadCurrentWeek` again instead of trusting its own stale
    /// "recently refreshed" stamp — but `WeekStore` now caches each week's
    /// summary by `weekStartDate` (see `loadWeekData`), so that call finds a
    /// still-fresh cached copy of the *current* week (from the cold launch)
    /// and applies it immediately without a 3rd network round trip. Fewer
    /// network calls than the original bug fix, same correct result.
    @Test func invalidateWeekLetsTheCoordinatorReapplyTheCachedCurrentWeekWithoutARefetch() async {
        let apiClient = FakeAppRefreshAPIClient()
        let (coordinator, weekStore) = TestCoordinatorFactory.makeWithWeekStore(apiClient: apiClient)

        await coordinator.refreshWeek(household: TestAppRefreshFixtures.household, trigger: .coldLaunch)
        #expect(await apiClient.weekSummaryCount == 1)
        #expect(weekStore.summary?.weekStartDate == WeekCalendar.currentWeekStartDate())

        // Simulates `WeekTabView.reloadViewedWeek`'s browsing branch: calls
        // `loadWeek` directly (bypassing the coordinator) for a different,
        // not-yet-cached week, then invalidates — exactly what the real call
        // site does. That week was never cached, so this is itself the 2nd
        // `weekSummary` call.
        let lastWeekStart = WeekCalendar.addWeeks(to: WeekCalendar.currentWeekStartDate(), offset: -1)
        await weekStore.loadWeek(household: TestAppRefreshFixtures.household, weekStartDate: lastWeekStart)
        #expect(await apiClient.weekSummaryCount == 2)
        #expect(weekStore.summary?.weekStartDate == lastWeekStart)
        coordinator.invalidateWeek(householdID: TestAppRefreshFixtures.household.id)

        // The coordinator is forced to call `loadCurrentWeek` again (its own
        // freshness stamp was invalidated), but `WeekStore`'s per-week cache
        // still has a fresh entry for the current week from the cold launch
        // — so the display corrects itself instantly and no 3rd network call
        // happens.
        await coordinator.refreshWeek(household: TestAppRefreshFixtures.household, trigger: .sceneActive)
        #expect(await apiClient.weekSummaryCount == 2)
        #expect(weekStore.summary?.weekStartDate == WeekCalendar.currentWeekStartDate())
    }

    /// The other half of the same regression: without `invalidateWeek`, the
    /// coordinator's stale freshness stamp must reproduce the bug — proving
    /// the fix above is actually load-bearing, not incidental.
    @Test func withoutInvalidateWeekTheBrowsedWeekStaysStuckOnSceneActiveReturn() async {
        let apiClient = FakeAppRefreshAPIClient()
        let (coordinator, weekStore) = TestCoordinatorFactory.makeWithWeekStore(apiClient: apiClient)

        await coordinator.refreshWeek(household: TestAppRefreshFixtures.household, trigger: .coldLaunch)
        let lastWeekStart = WeekCalendar.addWeeks(to: WeekCalendar.currentWeekStartDate(), offset: -1)
        await weekStore.loadWeek(household: TestAppRefreshFixtures.household, weekStartDate: lastWeekStart)
        // 2 calls so far: cold launch + the browsing fetch above.

        // No `invalidateWeek` call here — the coordinator still thinks
        // `.week` is fresh from the cold launch, so this should no-op and
        // leave the browsed week's data on screen — the bug.
        await coordinator.refreshWeek(household: TestAppRefreshFixtures.household, trigger: .sceneActive)

        #expect(await apiClient.weekSummaryCount == 2)
        #expect(weekStore.summary?.weekStartDate == lastWeekStart)
    }
}

@MainActor
private enum TestCoordinatorFactory {
    static func make(apiClient: FakeAppRefreshAPIClient, usesSeededCoreReader: Bool = false) -> AppRefreshCoordinator {
        let householdStore = HouseholdStore(apiClient: apiClient, selectionStore: FakeAppRefreshSelectionStore())
        let weekStore = WeekStore(apiClient: apiClient)
        let shoppingListStore = ShoppingListStore(apiClient: apiClient)
        let prepBatchStore = PrepBatchStore(apiClient: apiClient, cacheStore: FakeAppRefreshPrepBatchCache())
        let feedbackStore = FeedbackStore(apiClient: apiClient)
        let householdMealSignalStore = HouseholdMealSignalStore(apiClient: apiClient)
        let recipeStore = RecipeStore(apiClient: apiClient, cacheStore: FakeAppRefreshRecipeCache())
        let recipeRecommendationStore = RecipeRecommendationStore(apiClient: apiClient)

        return AppRefreshCoordinator(
            usesSeededCoreReader: usesSeededCoreReader,
            householdStore: householdStore,
            weekStore: weekStore,
            shoppingListStore: shoppingListStore,
            prepBatchStore: prepBatchStore,
            feedbackStore: feedbackStore,
            householdMealSignalStore: householdMealSignalStore,
            recipeStore: recipeStore,
            recipeRecommendationStore: recipeRecommendationStore
        )
    }

    /// Like `make`, but also hands back the `WeekStore` instance the
    /// coordinator was built with — needed by tests that (like
    /// `WeekTabView.reloadViewedWeek`'s browsing branch) call `loadWeek`
    /// directly on the store, bypassing the coordinator, to reproduce a
    /// mismatch between the store's cached week and the coordinator's
    /// freshness bookkeeping.
    static func makeWithWeekStore(apiClient: FakeAppRefreshAPIClient, usesSeededCoreReader: Bool = false) -> (AppRefreshCoordinator, WeekStore) {
        let householdStore = HouseholdStore(apiClient: apiClient, selectionStore: FakeAppRefreshSelectionStore())
        let weekStore = WeekStore(apiClient: apiClient)
        let shoppingListStore = ShoppingListStore(apiClient: apiClient)
        let prepBatchStore = PrepBatchStore(apiClient: apiClient, cacheStore: FakeAppRefreshPrepBatchCache())
        let feedbackStore = FeedbackStore(apiClient: apiClient)
        let householdMealSignalStore = HouseholdMealSignalStore(apiClient: apiClient)
        let recipeStore = RecipeStore(apiClient: apiClient, cacheStore: FakeAppRefreshRecipeCache())

        let coordinator = AppRefreshCoordinator(
            usesSeededCoreReader: usesSeededCoreReader,
            householdStore: householdStore,
            weekStore: weekStore,
            shoppingListStore: shoppingListStore,
            prepBatchStore: prepBatchStore,
            feedbackStore: feedbackStore,
            householdMealSignalStore: householdMealSignalStore,
            recipeStore: recipeStore
        )
        return (coordinator, weekStore)
    }
}

private enum TestAppRefreshFixtures {
    static let household = Household(id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", name: "Test household", role: .owner)
}

private final class FakeAppRefreshSelectionStore: HouseholdSelectionPersisting {
    private var selectedID: String?
    func selectedHouseholdID() -> String? { selectedID }
    func setSelectedHouseholdID(_ householdID: String) { selectedID = householdID }
    func clearSelectedHouseholdID() { selectedID = nil }
}

private final class FakeAppRefreshPrepBatchCache: PrepBatchStoreCachePersisting {
    func loadBatches(householdID: String, weekStartDate: String) -> PersistedPrepBatchCache? { nil }
    func saveBatches(_ cache: PersistedPrepBatchCache) {}
    func deleteBatches(householdID: String, weekStartDate: String) {}
}

private final class FakeAppRefreshRecipeCache: RecipeStoreCachePersisting {
    func loadRecipes(householdID: String) -> PersistedRecipeCache? { nil }
    func saveRecipes(_ cache: PersistedRecipeCache) {}
    func deleteRecipes(householdID: String) {}
}

/// One fake covering every store protocol `AppRefreshCoordinator` composes
/// with. An `actor` (rather than the plain-class fakes used elsewhere in
/// this target) since the coalescing tests above need to pause a specific
/// in-flight call and observe/resume it from a second concurrent `Task` —
/// the same continuation-gating pattern `HouseholdStoreTests`'
/// `SlowFakeHouseholdStoreAPIClient` uses for its single-store reentrancy
/// test, generalized here across every core-reader resource at once.
private actor FakeAppRefreshAPIClient:
    HouseholdStoreAPIClient,
    WeekStoreAPIClient,
    ShoppingListStoreAPIClient,
    PrepBatchStoreAPIClient,
    FeedbackStoreAPIClient,
    HouseholdMealSignalStoreAPIClient,
    RecipeStoreAPIClient,
    RecipeRecommendationAPIClient
{
    private(set) var bootstrapCount = 0
    private(set) var listHouseholdsCount = 0
    private(set) var listMembersCount = 0
    private(set) var weekSummaryCount = 0
    private(set) var shoppingListSummaryCount = 0
    private(set) var listPrepBatchesCount = 0
    private(set) var mealFeedbackCount = 0
    private(set) var householdMealSignalsCount = 0
    private(set) var listHouseholdRecipesCount = 0

    private var shouldPauseNextWeekSummary = false
    private var weekSummaryHasStarted = false
    private var weekSummaryStartedContinuation: CheckedContinuation<Void, Never>?
    private var weekSummaryResumeContinuation: CheckedContinuation<Void, Never>?

    func pauseNextWeekSummary() {
        shouldPauseNextWeekSummary = true
    }

    func waitUntilWeekSummaryStarted() async {
        if weekSummaryHasStarted { return }
        await withCheckedContinuation { weekSummaryStartedContinuation = $0 }
    }

    func resumeWeekSummary() {
        weekSummaryResumeContinuation?.resume()
        weekSummaryResumeContinuation = nil
    }

    // MARK: HouseholdStoreAPIClient

    func bootstrapHousehold() async throws -> Household {
        bootstrapCount += 1
        return TestAppRefreshFixtures.household
    }

    func listHouseholds() async throws -> [Household] {
        listHouseholdsCount += 1
        return [TestAppRefreshFixtures.household]
    }

    func listMembers(householdID: String) async throws -> [HouseholdMember] {
        listMembersCount += 1
        return [HouseholdMember(userId: "11111111-1111-1111-1111-111111111111", role: .owner, givenName: nil, familyName: nil)]
    }

    func getProfile(householdID: String) async throws -> HouseholdProfile? {
        HouseholdProfile(householdId: householdID, adults: 2, children: 1, priorities: [], avoidIngredients: [], selectedDays: [])
    }

    func saveProfile(
        householdID: String,
        adults: Int,
        children: Int,
        priorities: [HouseholdPriority],
        avoidIngredients: [String],
        selectedDays: [HouseholdDaySelection]
    ) async throws -> HouseholdProfile {
        HouseholdProfile(householdId: householdID, adults: adults, children: children, priorities: priorities, avoidIngredients: avoidIngredients, selectedDays: selectedDays)
    }

    func createInvite(householdID: String) async throws -> HouseholdInvite {
        HouseholdInvite(id: "invite-1", token: "token", email: nil, status: "pending", expiresAt: "2026-06-30T00:00:00.000Z")
    }

    func listInvites(householdID: String) async throws -> [HouseholdInvite] { [] }
    func revokeInvite(householdID: String, inviteID: String) async throws {}
    func lookupInvite(token: String) async throws -> InviteLanding { InviteLanding(householdName: "Test household", status: "pending") }
    func acceptInvite(token: String) async throws -> String { TestAppRefreshFixtures.household.id }
    func renameHousehold(householdID: String, name: String) async throws {}
    func removeMember(householdID: String, userID: String) async throws {}
    func deleteHousehold(householdID: String) async throws {}

    // MARK: WeekStoreAPIClient

    func weekSummary(householdID: String, weekStartDate: String) async throws -> WeekSummary {
        weekSummaryCount += 1
        weekSummaryHasStarted = true
        weekSummaryStartedContinuation?.resume()
        weekSummaryStartedContinuation = nil

        if shouldPauseNextWeekSummary {
            shouldPauseNextWeekSummary = false
            await withCheckedContinuation { weekSummaryResumeContinuation = $0 }
        }

        return WeekSummary(household: SummaryHousehold(id: householdID, name: "Test household"), weekStartDate: weekStartDate, updatedAt: nil, days: [])
    }

    func appendWeekPlanEvent(householdID: String, weekStartDate: String, userID: String, event: WeekPlanEventInput) async throws {}
    func generateWeekPlan(householdID: String, weekStartDate: String, regenerate: Bool) async throws {}

    // MARK: ShoppingListStoreAPIClient

    func shoppingListSummary(householdID: String, weekStartDate: String) async throws -> ShoppingListSummary {
        shoppingListSummaryCount += 1
        return ShoppingListSummary(household: SummaryHousehold(id: householdID, name: "Test household"), weekStartDate: weekStartDate, updatedAt: nil, groups: [])
    }

    func shoppingListState(householdID: String, weekStartDate: String) async throws -> (state: ShoppingListSharedState?, updatedAt: String?) {
        (nil, nil)
    }

    func updateShoppingListState(
        householdID: String,
        weekStartDate: String,
        checkedItems: [String],
        pantryStock: [String: Double],
        expectedUpdatedAt: String?,
        customItems: [ShoppingCustomItem]
    ) async throws -> String? { nil }

    // MARK: PrepBatchStoreAPIClient

    func listPrepBatches(householdID: String, from: String, to: String) async throws -> [PrepBatch] {
        listPrepBatchesCount += 1
        return []
    }

    func createPrepBatch(
        householdID: String,
        recipeId: String?,
        cookDate: String,
        totalPortions: Int,
        assignments: [(date: String, mealType: MealType)]
    ) async throws -> PrepBatch {
        throw APIError.notFound
    }

    func deletePrepBatch(householdID: String, batchID: String) async throws {}
    func removeAssignment(householdID: String, batchID: String, date: String, mealType: MealType) async throws {}

    // MARK: FeedbackStoreAPIClient

    func mealFeedback(householdID: String) async throws -> [String: MealVote] {
        mealFeedbackCount += 1
        return [:]
    }

    func removeMealFeedback(householdID: String, mealID: String) async throws {}
    func submitMealFeedback(householdID: String, mealID: String, vote: MealVote) async throws {}

    // MARK: HouseholdMealSignalStoreAPIClient

    func householdMealSignals(householdID: String) async throws -> [String: HouseholdMealSignal] {
        householdMealSignalsCount += 1
        return [:]
    }

    func removeHouseholdMealSignal(householdID: String, mealID: String) async throws {}
    func setHouseholdMealSignal(householdID: String, mealID: String, signal: HouseholdMealSignal) async throws {}

    // MARK: RecipeStoreAPIClient

    func listHouseholdRecipes(householdID: String, includePublic: Bool) async throws -> [FullRecipe] {
        listHouseholdRecipesCount += 1
        return [
            FullRecipe(
                id: "recipe-1",
                title: "Tacos",
                description: "",
                servings: 4,
                prepTimeMinutes: 10,
                cookTimeMinutes: 10,
                tags: [],
                ingredients: [],
                steps: [],
                userVote: nil
            ),
        ]
    }

    func recipe(householdID: String, recipeID: String) async throws -> FullRecipe { throw APIError.notFound }
    func createRecipe(householdID: String, draft: RecipeDraft) async throws -> FullRecipe { throw APIError.notFound }
    func updateRecipe(householdID: String, recipeID: String, draft: RecipeDraft) async throws -> FullRecipe { throw APIError.notFound }
    func archiveRecipe(householdID: String, recipeID: String) async throws -> FullRecipe { throw APIError.notFound }
    func fillInRecipe(title: String, existingIngredients: [DraftIngredient], existingSteps: [String]) async throws -> RecipeDraft { throw APIError.notFound }
    func importRecipeFromURL(_ urlString: String) async throws -> RecipeDraft { throw APIError.notFound }
    func importRecipeFromText(_ text: String, sourceURL: String?) async throws -> RecipeDraft { throw APIError.notFound }

    // MARK: RecipeRecommendationAPIClient

    private(set) var recommendMealsCount = 0
    private var recommendMealsContinuation: CheckedContinuation<Void, Never>?

    func waitUntilRecommendMealsCalled() async {
        if recommendMealsCount > 0 { return }
        await withCheckedContinuation { recommendMealsContinuation = $0 }
    }

    func recommendMeals(
        householdProfile: HouseholdProfile,
        feedbackSummary: [MealRecommendationFeedbackItem],
        candidateMeals: [MealRecommendationCandidate]
    ) async throws -> [MealRecommendation] {
        recommendMealsCount += 1
        recommendMealsContinuation?.resume()
        recommendMealsContinuation = nil
        return []
    }
}

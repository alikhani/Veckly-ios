import Foundation
import Observation

/// Owns *when* and *how often* the app's core-reader data — household list +
/// everything scoped to the active household (week, shopping, prep,
/// feedback, household meal signals, recipes, household details) — actually
/// gets (re)loaded.
///
/// Before Fas 7 this decision was scattered: `RootView` reloaded on cold
/// launch and on every `scenePhase` becoming `.active`, and `WeekTabView`
/// separately reloaded a subset (week/prep/household details) from both its
/// `.task(id:)` and its own `scenePhase` handler — with four ad hoc
/// `usesSeededCoreReader` guards standing in for the network-free
/// UI-test-mode contract each of those call sites needed individually. This
/// coordinator replaces all of that with one owner: callers describe *why*
/// they want a refresh (`Trigger`), and the coordinator decides whether the
/// resource is fresh enough to skip and de-dupes concurrent callers asking
/// for the same resource into a single in-flight `Task`.
///
/// It never duplicates a store's own loading logic — `run(_:trigger:_:)`
/// only decides *whether* to call the store method the caller hands it.
@MainActor
final class AppRefreshCoordinator {
    enum Trigger {
        /// App launched, or a session was just (re)established (sign-in,
        /// sign-up, token refresh). Always forces a real reload.
        case coldLaunch
        /// `scenePhase` turned `.active`, or a view that shows core-reader
        /// data reappeared and just wants to make sure it isn't stale.
        /// The cheapest trigger: a no-op if the resource was refreshed
        /// within `freshnessWindow`.
        case sceneActive
        /// An explicit user action — a refresh button, an error retry, a
        /// `.refreshable` pull. Always forces a real reload.
        case pullToRefresh
        /// The active household itself changed (switch/join/leave/delete).
        /// Always forces a real reload — the underlying data actually
        /// changed, not just gone stale.
        case householdChanged

        fileprivate var forcesRealReload: Bool {
            switch self {
            case .sceneActive: false
            case .coldLaunch, .pullToRefresh, .householdChanged: true
            }
        }
    }

    private enum Resource: Hashable {
        case householdBootstrap
        case householdDetails(String)
        case week(String)
        case shopping(String)
        case prep(String)
        case feedback(String)
        case signals(String)
        case recipes(String)
    }

    /// Fas 7's single home for the seeded-UI-test-mode network gate. Every
    /// method on this coordinator checks it before doing anything, so
    /// callers (`RootView`, `WeekTabView`) no longer need their own ad hoc
    /// `guard !usesSeededCoreReader` before reaching for a refresh — the
    /// four scattered guards this replaces all protected exactly this.
    ///
    /// `AppModel.usesSeededCoreReader` stays the source of truth (it also
    /// gates unrelated things — UI-test seeding at init, product-event
    /// recording, the Sunday reminder — that aren't this coordinator's
    /// concern); this is handed in once at construction time since the flag
    /// never changes during a process's lifetime.
    let usesSeededCoreReader: Bool

    private let householdStore: HouseholdStore
    private let weekStore: WeekStore
    private let shoppingListStore: ShoppingListStore
    private let prepBatchStore: PrepBatchStore
    private let feedbackStore: FeedbackStore
    private let householdMealSignalStore: HouseholdMealSignalStore
    private let recipeStore: RecipeStore
    private let recipeRecommendationStore: RecipeRecommendationStore?
    /// Household tab's own quiet, secondary data (B2b) — prefetched here in
    /// the background for the same reason as `recipeRecommendationStore`
    /// below: cheap calls (a name, a cookbook summary), so by the time the
    /// user actually taps into Household it's usually already warm, without
    /// adding to the Week tab's cold-launch critical path. Each store's own
    /// cache/`loadIfNeeded` is the de-dup guard, so firing this on every
    /// trigger is harmless.
    private let familyCookbookStore: FamilyCookbookStore?
    private let userProfileStore: UserProfileStore?

    private let freshnessWindow: TimeInterval
    private var inFlight: [Resource: Task<Void, Never>] = [:]
    private var lastCompletedAt: [Resource: Date] = [:]

    init(
        usesSeededCoreReader: Bool,
        householdStore: HouseholdStore,
        weekStore: WeekStore,
        shoppingListStore: ShoppingListStore,
        prepBatchStore: PrepBatchStore,
        feedbackStore: FeedbackStore,
        householdMealSignalStore: HouseholdMealSignalStore,
        recipeStore: RecipeStore,
        recipeRecommendationStore: RecipeRecommendationStore? = nil,
        familyCookbookStore: FamilyCookbookStore? = nil,
        userProfileStore: UserProfileStore? = nil,
        freshnessWindow: TimeInterval = 300
    ) {
        self.usesSeededCoreReader = usesSeededCoreReader
        self.householdStore = householdStore
        self.weekStore = weekStore
        self.shoppingListStore = shoppingListStore
        self.prepBatchStore = prepBatchStore
        self.feedbackStore = feedbackStore
        self.householdMealSignalStore = householdMealSignalStore
        self.recipeStore = recipeStore
        self.recipeRecommendationStore = recipeRecommendationStore
        self.familyCookbookStore = familyCookbookStore
        self.userProfileStore = userProfileStore
        self.freshnessWindow = freshnessWindow
    }

    /// Full core-reader bootstrap: the household list, then everything
    /// scoped to the household that ends up active. What a cold launch, a
    /// scene becoming active, or an explicit retry all ultimately need.
    func refreshCoreReader(trigger: Trigger) async {
        guard !usesSeededCoreReader else { return }

        await run(.householdBootstrap, trigger: trigger) {
            await self.householdStore.bootstrapAndLoadHouseholds()
        }

        guard let household = householdStore.activeHousehold else { return }
        await refreshActiveHouseholdData(household: household, trigger: trigger)
    }

    /// The household-scoped subset of core-reader data, without re-listing
    /// households — used directly by callers that already know which
    /// household is active (switch/join/leave/delete).
    func refreshActiveHouseholdData(household: Household, trigger: Trigger) async {
        guard !usesSeededCoreReader else { return }
        let weekStartDate = WeekCalendar.currentWeekStartDate()
        // Each store below runs its own freshness check keyed only on
        // time (and, for week/shopping, the requested week) — none of them
        // know *why* a caller wants data, so a forcing trigger has to pass
        // `force: true` through explicitly or it would silently no-op
        // against a load that completed moments ago.
        let force = trigger.forcesRealReload

        async let details: Void = run(.householdDetails(household.id), trigger: trigger) {
            await self.householdStore.loadHouseholdDetails(householdID: household.id, force: force)
        }
        async let week: Void = run(.week(household.id), trigger: trigger) {
            await self.weekStore.loadCurrentWeek(household: household, force: force)
        }
        async let shopping: Void = run(.shopping(household.id), trigger: trigger) {
            await self.shoppingListStore.loadCurrentWeek(household: household, weekStartDate: weekStartDate, force: force)
        }
        async let prep: Void = run(.prep(household.id), trigger: trigger) {
            await self.prepBatchStore.load(householdID: household.id, weekStartDate: weekStartDate, force: force)
        }
        async let feedback: Void = run(.feedback(household.id), trigger: trigger) {
            await self.feedbackStore.loadFeedback(householdID: household.id)
        }
        async let signals: Void = run(.signals(household.id), trigger: trigger) {
            await self.householdMealSignalStore.loadSignals(householdID: household.id)
        }
        async let recipes: Void = run(.recipes(household.id), trigger: trigger) {
            await self.recipeStore.loadRecipes(householdID: household.id, force: force)
        }
        _ = await (details, week, shopping, prep, feedback, signals, recipes)

        // Fired, not awaited: the "Suggestions for you" AI call takes on the
        // order of 10s, far longer than anything else this bundle loads —
        // waiting on it here would make every cold launch and scene-active
        // refresh that much slower. Starting it now, as soon as the profile
        // and recipe list it needs are ready, means it's usually done (or
        // much further along) by the time the user actually opens a day's
        // meal picker, instead of only starting then. `loadIfNeeded` is its
        // own de-dup guard, so calling this on every trigger is harmless.
        if let recipeRecommendationStore, let profile = householdStore.cachedProfile(for: household.id) {
            let recipesSnapshot = recipeStore.recipes
            let feedbackVotes = feedbackStore.allVotes
            Task {
                await recipeRecommendationStore.loadIfNeeded(
                    householdID: household.id,
                    householdProfile: profile,
                    feedbackVotes: feedbackVotes,
                    recipes: recipesSnapshot
                )
            }
        }

        // Same fire-and-forget shape as the recommendation prefetch above,
        // for Household tab's own quiet, secondary data (B2b) — cheap
        // enough (a name, a cookbook summary) that there's no need to wait
        // for anything else in the bundle first.
        if let familyCookbookStore {
            Task { await familyCookbookStore.loadIfNeeded(householdID: household.id) }
        }
        if let userProfileStore {
            Task { await userProfileStore.loadIfNeeded() }
        }
    }

    /// A narrower request for views that only need the current week kept
    /// fresh (e.g. the Week tab reappearing, its toolbar refresh button, or
    /// an error retry) without forcing the entire household bundle above —
    /// recipes/signals/feedback rarely need re-fetching just because the
    /// week view reappeared. Shares the same de-dup/freshness key as the
    /// `week` resource in `refreshActiveHouseholdData`, so the two never
    /// race into a double fetch.
    func refreshWeek(household: Household, trigger: Trigger) async {
        guard !usesSeededCoreReader else { return }
        await run(.week(household.id), trigger: trigger) {
            await self.weekStore.loadCurrentWeek(household: household, force: trigger.forcesRealReload)
        }
    }

    /// De-dupes concurrent callers of the same resource into one in-flight
    /// `Task`, and — unless `trigger` demands a real reload — skips the work
    /// entirely if it already ran within `freshnessWindow`. No `await`
    /// happens between checking and populating `inFlight`, so two callers
    /// racing for the same resource on this `@MainActor` can't both slip
    /// past the check and start their own `Task`.
    private func run(_ resource: Resource, trigger: Trigger, _ operation: @escaping () async -> Void) async {
        if !trigger.forcesRealReload, isFresh(resource) { return }

        if let existing = inFlight[resource] {
            await existing.value
            return
        }

        let task = Task { await operation() }
        inFlight[resource] = task
        await task.value
        inFlight[resource] = nil
        lastCompletedAt[resource] = Date()
    }

    private func isFresh(_ resource: Resource) -> Bool {
        guard let last = lastCompletedAt[resource] else { return false }
        return Date().timeIntervalSince(last) <= freshnessWindow
    }

    /// `WeekStore.dayRows`/`summary` is a single shared "currently displayed
    /// week" slot, written not only by this coordinator's own
    /// `loadCurrentWeek` but also directly by `WeekTabView`'s Last/Next
    /// browsing (`loadWeek`), which this coordinator doesn't own and can't
    /// see. Without this call, browsing away and back within the freshness
    /// window looks "fresh" to `refreshWeek`/`refreshActiveHouseholdData` —
    /// the coordinator has no idea the slot was clobbered with a different
    /// week's data in between — so a `sceneActive` return to the current
    /// week would silently no-op and leave the browsed week's rows on screen
    /// under a header that's already moved back to "this week". Callers that
    /// write into that slot outside the coordinator must invalidate it here
    /// so the next `sceneActive` request actually calls back into
    /// `WeekStore`. That doesn't necessarily mean a real network fetch,
    /// though: `WeekStore` keeps its own per-week cache (see
    /// `loadWeekData`), so a call this forces through often just re-applies
    /// an already-fresh cached copy of the current week instead of hitting
    /// the network — this method's job is only to make sure the call
    /// happens, not to force the network round trip itself.
    func invalidateWeek(householdID: String) {
        lastCompletedAt[.week(householdID)] = nil
    }
}

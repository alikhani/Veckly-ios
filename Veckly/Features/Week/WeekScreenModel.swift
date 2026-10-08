import Foundation
import Observation

/// Snapshot of the days a "Regenerate" run is about to overwrite, captured
/// just before the API call — restoring from it is how the undo banner puts
/// the previous plan back without the backend needing an undo endpoint.
struct RegenerateUndoContext: Identifiable {
    let rows: [WeekDayRowViewModel]
    let weekStartDate: String
    var id: String { weekStartDate }
}

/// Pairs a recipe with the day it belongs to, so RecipeDetailView can offer
/// day-level actions (skip/plan) in context.
struct SelectedDayRecipe: Identifiable {
    let day: WeekDayRowViewModel
    let recipe: WeekSummaryRecipe
    var id: String { recipe.id + day.id }
}

/// Seeds a new prep batch from a day that's already planned — "we made
/// extra of this, mark it as eaten again on other days" — without making
/// the user re-pick the recipe or cook date in `PrepBatchFormSheet`.
struct PrepBatchSeed: Identifiable {
    let recipeID: String
    let cookDate: String
    let weekStartDate: String
    var assignedDate: String? = nil
    var id: String { recipeID + cookDate + weekStartDate + (assignedDate ?? "") }
}

/// The app-level deep-link slots the Week tab consumes, as closures so the
/// model never depends on `AppModel` itself.
struct WeekDeepLinkInbox {
    var pendingWeekPlan: () -> Bool
    var clearPendingWeekPlan: () -> Void
    var pendingDeepLink: () -> AppDeepLink?
    var clearPendingDeepLink: () -> Void
}

struct WeekBriefPresentation: Identifiable {
    let weekStartDate: String
    let regenerate: Bool
    var id: String { "\(weekStartDate):\(regenerate)" }
}

/// Owns the Week tab's user intents and the orchestration between stores
/// (week plan, shopping list, prep batches, household, auth) that used to
/// live inline in `WeekTabView`. The view renders; this decides.
///
/// Depends on concrete stores (each already testable with a fake API
/// client) plus closures for product events and unauthorized handling —
/// never on `AppModel`, so it can be built directly in unit tests.
@MainActor
@Observable
final class WeekScreenModel {
    // MARK: Dependencies

    private let weekStore: WeekStore
    private let householdStore: HouseholdStore
    private let shoppingListStore: ShoppingListStore
    private let prepBatchStore: PrepBatchStore
    private let recipeStore: RecipeStore
    private let authSessionStore: AuthSessionStore
    private let mealOutcomeStore: MealOutcomeStore
    private let retroClient: any RetroCardAPIClient
    private let weekBriefClient: any WeekBriefAPIClient
    private let usesSeededCoreReader: Bool
    private let refreshCurrentWeek: (Household, AppRefreshCoordinator.Trigger) async -> Void
    private let invalidateWeekFreshness: (_ householdID: String) -> Void
    private let deepLinks: WeekDeepLinkInbox
    private let defaults: UserDefaults
    private let recordEvent: (ProductEventName, String?, ProductEventProperties) -> Void
    private let onUnauthorized: () async -> Void

    static let weekendNudgeDismissalKey = "veckly.week.weekendNudgeDismissedDate"
    static let dismissedQualitySuggestionKeysKey = "dismissedWeekQualitySuggestionKeys"

    // MARK: Screen state

    var viewedWeekOffset: ViewedWeekOffset = .current
    /// "Veckan är klar" — a one-time, dismissible beat shown the moment the
    /// last empty day of the current week gets filled or skipped (see
    /// `checkForSessionEnd`). Not persisted anywhere: scoped to this
    /// session, gone once dismissed or the CTA is tapped.
    private(set) var showSessionEndBeat = false
    private(set) var regenerateUndo: RegenerateUndoContext?
    private(set) var fillCompletionNotice: WeekFillCompletionNotice?
    private(set) var failedFillWeekStartDate: String?
    var weekBriefPresentation: WeekBriefPresentation?
    /// nil until checked — see `refreshNextWeekEmptyState`.
    private(set) var nextWeekIsEmpty: Bool?
    private(set) var weekendNudgeDismissedToday = false
    /// Mirrors the persisted `dismissedWeekQualitySuggestionKeys` value
    /// (formerly the view's `@AppStorage`), kept here so the view re-renders
    /// when a suggestion is dismissed.
    private(set) var dismissedQualitySuggestionKeys: Set<String>
    /// The Sunday retro on last week's dinners.
    let retro = RetroCardViewModel()
    @ObservationIgnored private var regenerateUndoDismissTask: Task<Void, Never>?
    /// How long the undo banner stays up after a regenerate. Injectable so
    /// tests don't have to wait out the real 8 seconds.
    private let regenerateUndoDuration: Duration

    /// The work started by the most recent fire-and-forget intent (or the
    /// unauthorized handling it triggered). The view never awaits it — it
    /// exists so tests can wait for an intent's effects deterministically.
    private(set) var lastTask: Task<Void, Never>?

    init(
        weekStore: WeekStore,
        householdStore: HouseholdStore,
        shoppingListStore: ShoppingListStore,
        prepBatchStore: PrepBatchStore,
        recipeStore: RecipeStore,
        authSessionStore: AuthSessionStore,
        mealOutcomeStore: MealOutcomeStore,
        retroClient: any RetroCardAPIClient,
        weekBriefClient: any WeekBriefAPIClient,
        usesSeededCoreReader: Bool,
        refreshCurrentWeek: @escaping (Household, AppRefreshCoordinator.Trigger) async -> Void,
        invalidateWeekFreshness: @escaping (_ householdID: String) -> Void,
        deepLinks: WeekDeepLinkInbox,
        defaults: UserDefaults = .standard,
        recordEvent: @escaping (ProductEventName, String?, ProductEventProperties) -> Void,
        onUnauthorized: @escaping () async -> Void,
        regenerateUndoDuration: Duration = .seconds(8)
    ) {
        self.weekStore = weekStore
        self.householdStore = householdStore
        self.shoppingListStore = shoppingListStore
        self.prepBatchStore = prepBatchStore
        self.recipeStore = recipeStore
        self.authSessionStore = authSessionStore
        self.mealOutcomeStore = mealOutcomeStore
        self.retroClient = retroClient
        self.weekBriefClient = weekBriefClient
        self.usesSeededCoreReader = usesSeededCoreReader
        self.refreshCurrentWeek = refreshCurrentWeek
        self.invalidateWeekFreshness = invalidateWeekFreshness
        self.deepLinks = deepLinks
        self.defaults = defaults
        self.dismissedQualitySuggestionKeys = Set(
            (defaults.string(forKey: Self.dismissedQualitySuggestionKeysKey) ?? "")
                .split(separator: "|")
                .map(String.init)
        )
        self.recordEvent = recordEvent
        self.onUnauthorized = onUnauthorized
        self.regenerateUndoDuration = regenerateUndoDuration
    }

    // MARK: Viewed week

    var viewedWeekStartDate: String {
        viewedWeekOffset.weekStartDate
    }

    var isViewingCurrentWeek: Bool { viewedWeekOffset == .current }
    var isViewingLastWeek: Bool { viewedWeekOffset == .last }

    // MARK: Derived week state

    /// Whether leftovers from a prep batch cover this day's dinner — checked
    /// here so `WeekStore`/`PrepBatchStore` stay decoupled. The week view is
    /// dinner-only today (one meal slot per day), so `.dinner` is the
    /// correct meal type explicitly, not just a date-based guess.
    func coverage(for day: WeekDayRowViewModel) -> PrepBatchCoverage? {
        prepBatchCoverage(for: day.date, mealType: .dinner, batches: prepBatchStore.batches, recipes: recipeStore.recipes)
    }

    /// Planning-days-are-the-truth (beslut 1): built from the household's
    /// profile so open-day counts, the quality card, session-end, and the
    /// generate/regenerate CTA all agree on which days actually count.
    var weekPlanningScope: WeekPlanningScope {
        WeekPlanningScope(profile: householdStore.cachedProfile(
            for: householdStore.activeHousehold?.id ?? ""
        ))
    }

    /// Dates covered by a prep/leftovers batch but with no recipe of their
    /// own — same rule `weekQualityCard` already used, now shared with the
    /// scope so a prep-covered day counts as "done" everywhere.
    var prepCoveredDates: Set<String> {
        Set(weekStore.dayRows.compactMap { day in
            coverage(for: day) == nil ? nil : day.date
        })
    }

    /// Scope-aware replacement for `WeekStore.hasEmptyDays`: true only when a
    /// *relevant* planning day is still open. Days outside the household's
    /// selected planning days never make this true.
    var hasOpenRelevantDays: Bool {
        !weekPlanningScope.isComplete(days: weekStore.dayRows, coveredDates: prepCoveredDates)
    }

    var openDayCount: Int {
        weekPlanningScope.openDays(in: weekStore.dayRows, coveredDates: prepCoveredDates).count
    }

    var fillAction: WeekFillAction {
        WeekFillAction(plannedDinnerCount: plannedDinnerCount, openDayCount: openDayCount)
    }

    var firstOpenPlanningDay: WeekDayRowViewModel? {
        weekPlanningScope.openDays(
            in: weekStore.dayRows,
            coveredDates: prepCoveredDates
        ).first
    }

    var isFillingViewedWeek: Bool {
        weekStore.generatingWeekStartDate == viewedWeekStartDate
    }

    /// Single source for the "veckan är klar" counts — shared with
    /// `WeekQualitySummary` via `RecipeTimingSignals` so "quick" and
    /// "prep-friendly" mean the same thing on both surfaces.
    var weekSessionSummary: WeekSessionSummary {
        WeekSessionSummary.make(
            relevantDays: weekPlanningScope.relevantDays(in: weekStore.dayRows),
            prepCoveredDates: prepCoveredDates
        )
    }

    var plannedDinnerCount: Int { weekSessionSummary.plannedDinnerCount }

    /// The four hero states (beslut 16) — only meaningful for the current
    /// week (Last/Next week have zero `isToday` rows by definition, and are
    /// rendered by `nextWeekHeroCard`/`nextWeekSummaryCard`/`lastWeekSummaryCard`
    /// instead, which predate this phase and aren't "today"-framed).
    var heroMode: TonightMealCardMode {
        TonightMealCardMode.compute(
            dayRows: weekStore.dayRows,
            scope: weekPlanningScope,
            hasCoverage: { self.coverage(for: $0) != nil }
        )
    }

    /// True when the hero card is already showing *today's* row — in that
    /// case the matching row in the week list below must not duplicate the
    /// hero's actions (beslut 3). In the other two modes (`.upcomingMeal`,
    /// `.weekDone`) the hero isn't representing today, so today's row (if
    /// shown at all) behaves like any other row.
    var todayRowIsHeroOwned: Bool {
        switch heroMode {
        case .tonightMeal, .openTonight: true
        case .upcomingMeal, .weekDone: false
        }
    }

    var weekListPresentation: WeekListPresentation {
        WeekListPresentation(
            days: weekStore.dayRows,
            viewedWeekOffset: viewedWeekOffset,
            includesWeekend: weekPlanningScope.includesWeekend
        )
    }

    func canEditDay(_ day: WeekDayRowViewModel) -> Bool {
        weekListPresentation.interaction(for: day) == .editDay
    }

    func canMutateDay(_ day: WeekDayRowViewModel) -> Bool {
        switch weekListPresentation.interaction(for: day) {
        case .editDay, .planDay:
            true
        case .none, .viewRecipe:
            false
        }
    }

    // MARK: Session

    /// The one place the Week tab resolves "who is acting on which
    /// household". No active household is a silent no-op; a missing user
    /// means the session is gone, so unauthorized handling starts.
    /// Synchronous on purpose: several callers dismiss a sheet only once a
    /// session is known to exist, in the same tap.
    func session() -> (household: Household, userID: String)? {
        guard let household = householdStore.activeHousehold else { return nil }
        guard let userID = authSessionStore.userID else {
            lastTask = Task { await onUnauthorized() }
            return nil
        }
        return (household, userID)
    }

    // MARK: Week mutations

    /// Returns whether the skip was started (a session existed), so the
    /// caller can dismiss whatever sheet it came from. `checksSessionEnd`
    /// is set by the callers that can close the week's last open day.
    @discardableResult
    func toggleSkip(_ day: WeekDayRowViewModel, checksSessionEnd: Bool = false) -> Bool {
        guard let (household, userID) = session() else { return false }
        let wasEmptyBefore = hasOpenRelevantDays
        lastTask = Task {
            await weekStore.toggleSkip(day: day, household: household, userID: userID, viewedWeekStartDate: viewedWeekStartDate)
            if checksSessionEnd {
                checkForSessionEnd(wasEmptyBefore: wasEmptyBefore)
            }
        }
        return true
    }

    /// Clears any stale mutation error first, like the other lock entry
    /// points. Returns whether the toggle was started, so the view can show
    /// its one-time lock explanation.
    @discardableResult
    func toggleLock(_ day: WeekDayRowViewModel) -> Bool {
        guard let (household, userID) = session() else { return false }
        weekStore.clearMutationError()
        lastTask = Task {
            await weekStore.toggleLock(day: day, household: household, userID: userID)
        }
        return true
    }

    @discardableResult
    func assignMeal(_ day: WeekDayRowViewModel, recipe: WeekSummaryRecipe) -> Bool {
        guard let (household, userID) = session() else { return false }
        let wasEmptyBefore = hasOpenRelevantDays
        lastTask = Task {
            shoppingListStore.invalidateCache()
            await weekStore.assignMeal(day: day, recipe: recipe, household: household, userID: userID, viewedWeekStartDate: viewedWeekStartDate)
            await refreshShoppingListAfterWeekMutation(household: household, weekStartDate: viewedWeekStartDate)
            checkForSessionEnd(wasEmptyBefore: wasEmptyBefore)
        }
        return true
    }

    @discardableResult
    func unassignMeal(_ day: WeekDayRowViewModel) -> Bool {
        guard let (household, userID) = session() else { return false }
        lastTask = Task {
            shoppingListStore.invalidateCache()
            await weekStore.unassignMeal(day: day, household: household, userID: userID, viewedWeekStartDate: viewedWeekStartDate)
            await refreshShoppingListAfterWeekMutation(household: household, weekStartDate: viewedWeekStartDate)
        }
        return true
    }

    /// Silent `false` without a session (no unauthorized handling) — the
    /// portion-suggestion card just reports that the change didn't apply.
    func applyPortionSuggestion(_ day: WeekDayRowViewModel, servings: Int) async -> Bool {
        guard let household = householdStore.activeHousehold,
              let userID = authSessionStore.userID else { return false }
        do {
            try await weekStore.changeServings(
                day: day,
                servings: servings,
                household: household,
                userID: userID,
                viewedWeekStartDate: viewedWeekStartDate,
                consumesPortionSuggestion: true
            )
            shoppingListStore.invalidateCache()
            await refreshShoppingListAfterWeekMutation(household: household, weekStartDate: viewedWeekStartDate)
            return true
        } catch {
            return false
        }
    }

    func ignorePortionSuggestion(_ day: WeekDayRowViewModel) async -> Bool {
        guard let household = householdStore.activeHousehold,
              let recipeID = day.recipe?.id else { return false }
        return await weekStore.ignorePortionSuggestion(
            recipeID: recipeID,
            household: household,
            weekStartDate: viewedWeekStartDate
        )
    }

    func resetPortionMemory(_ day: WeekDayRowViewModel) async -> Bool {
        guard let household = householdStore.activeHousehold,
              let recipeID = day.recipe?.id else { return false }
        return await weekStore.resetPortionMemory(
            recipeID: recipeID,
            household: household,
            weekStartDate: viewedWeekStartDate
        )
    }

    /// Removes a leftovers assignment from a day. Returns whether it was
    /// started (an active household existed).
    @discardableResult
    func removeCoverage(_ day: WeekDayRowViewModel, coverage dayCoverage: PrepBatchCoverage) -> Bool {
        guard let household = householdStore.activeHousehold else { return false }
        lastTask = Task {
            try? await prepBatchStore.removeAssignment(
                householdID: household.id,
                batchID: dayCoverage.batchID,
                date: day.date,
                mealType: dayCoverage.mealType
            )
        }
        return true
    }

    /// For flows that change the week plan through their own sheet
    /// (rescue, reuse last week): the shopping list must follow.
    func weekPlanChangedElsewhere(household: Household) async {
        shoppingListStore.invalidateCache()
        await refreshShoppingListAfterWeekMutation(household: household, weekStartDate: viewedWeekStartDate)
    }

    func refreshShoppingListAfterWeekMutation(household: Household, weekStartDate: String) async {
        guard weekStore.mutationError == nil else { return }
        shoppingListStore.invalidateCache()
        await shoppingListStore.loadCurrentWeek(household: household, weekStartDate: weekStartDate)
    }

    // MARK: Generate / regenerate

    /// Opens the Week Brief for the viewed week — the step every
    /// Generate/Regenerate goes through before `performGenerate`.
    func presentWeekBrief(regenerate: Bool) {
        guard session() != nil else { return }
        weekBriefPresentation = WeekBriefPresentation(
            weekStartDate: viewedWeekStartDate,
            regenerate: regenerate
        )
    }

    /// Runs Generate/Regenerate. When replacing an already-full week, snapshots
    /// the unlocked/unskipped rows first so a successful run can offer "Undo" —
    /// there's no backend undo endpoint, so restoring is just re-issuing the
    /// same assign/clear calls a user would make by hand.
    func performGenerate(
        regenerate: Bool,
        weekStartDate: String? = nil,
        pantryItemKeys: [String] = [],
        portionAdjustments: [WeekPortionAdjustment] = []
    ) async {
        guard weekStore.generatingWeekStartDate == nil else { return }
        guard let household = householdStore.activeHousehold else { return }
        guard let userID = authSessionStore.userID else {
            await onUnauthorized()
            return
        }

        // Captured once, up front — `viewedWeekStartDate` is a computed
        // property that tracks live navigation, and the API call below can
        // take long enough for the user to browse to a different week
        // before it resolves. Everything about *this* generate run (the
        // snapshot, the API call, and the undo banner it may offer) must
        // stay pinned to the week it was actually generated for.
        let targetWeekStartDate = weekStartDate ?? viewedWeekStartDate
        let rowsBeforeFill = weekStore.dayRows
        let preRegenerateSnapshot = regenerate
            ? weekStore.dayRows.filter { !$0.isPast && !$0.isLocked && !$0.isSkipped }
            : []
        let wasEmptyBefore = hasOpenRelevantDays
        let hadWeekContentBefore = weekStore.hasWeekContent

        if !regenerate {
            failedFillWeekStartDate = nil
            fillCompletionNotice = nil
        }

        shoppingListStore.invalidateCache()
        await weekStore.generateWeek(
            household: household,
            userID: userID,
            regenerate: regenerate,
            viewedWeekStartDate: targetWeekStartDate,
            pantryItemKeys: pantryItemKeys
        )
        let generateSucceeded = weekStore.mutationError == nil
        if !regenerate, viewedWeekStartDate == targetWeekStartDate {
            if weekStore.mutationError == nil {
                fillCompletionNotice = WeekFillCompletionNotice.make(
                    before: rowsBeforeFill,
                    after: weekStore.dayRows
                )
            } else {
                failedFillWeekStartDate = targetWeekStartDate
            }
        }
        // After generating, so only days that kept the suggestion's recipe
        // get the new portions (see `applyPortionAdjustments`).
        await weekStore.applyPortionAdjustments(
            portionAdjustments,
            household: household,
            userID: userID,
            weekStartDate: targetWeekStartDate
        )
        await refreshShoppingListAfterWeekMutation(household: household, weekStartDate: targetWeekStartDate)
        if !regenerate, !hadWeekContentBefore, generateSucceeded {
            recordEvent(.firstWeekGenerated, targetWeekStartDate, [
                "plannedDinners": .int(plannedDinnerCount)
            ])
        }
        checkForSessionEnd(wasEmptyBefore: wasEmptyBefore)

        guard regenerate, generateSucceeded, !preRegenerateSnapshot.isEmpty else { return }
        // Only offer undo if the user is still looking at the week that was
        // just regenerated — otherwise there's nothing sensible to restore
        // into the currently-visible week, and no banner should appear for
        // a week that isn't on screen.
        guard viewedWeekStartDate == targetWeekStartDate else { return }
        presentRegenerateUndo(rows: preRegenerateSnapshot, weekStartDate: targetWeekStartDate)
    }

    private func presentRegenerateUndo(rows: [WeekDayRowViewModel], weekStartDate: String) {
        regenerateUndoDismissTask?.cancel()
        regenerateUndo = RegenerateUndoContext(rows: rows, weekStartDate: weekStartDate)
        let duration = regenerateUndoDuration
        regenerateUndoDismissTask = Task {
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            regenerateUndo = nil
        }
    }

    func undoRegenerate(_ context: RegenerateUndoContext) {
        regenerateUndoDismissTask?.cancel()
        regenerateUndo = nil
        guard let household = householdStore.activeHousehold,
              let userID = authSessionStore.userID else { return }
        // Defense in depth alongside the `viewedWeekDidChange` dismissal
        // below — never replay a snapshot into a week other than the one it
        // was taken from.
        guard context.weekStartDate == viewedWeekStartDate else { return }

        lastTask = Task {
            shoppingListStore.invalidateCache()
            for row in context.rows {
                if let recipe = row.recipe {
                    await weekStore.assignMeal(day: row, recipe: recipe, household: household, userID: userID, viewedWeekStartDate: context.weekStartDate)
                } else {
                    await weekStore.unassignMeal(day: row, household: household, userID: userID, viewedWeekStartDate: context.weekStartDate)
                }
            }
            await refreshShoppingListAfterWeekMutation(household: household, weekStartDate: context.weekStartDate)
        }
    }

    /// Called by the view whenever the viewed week actually changes.
    ///
    /// The undo banner replays writes against `context.weekStartDate`
    /// by matching rows on weekday only, with no check that the
    /// currently-loaded `dayRows` still belong to that week — so if
    /// the user browses to a different week while the banner is still
    /// up, a tap on "Undo" would overwrite the *other* week's rows
    /// with the regenerated week's snapshot. Simplest safe fix: the
    /// banner only makes sense for the week it was generated for, so
    /// drop it the moment the user navigates away from that week.
    func viewedWeekDidChange() {
        regenerateUndoDismissTask?.cancel()
        regenerateUndo = nil
        failedFillWeekStartDate = nil
        fillCompletionNotice = nil
    }

    /// Dismissing the week error banner also forgets which fill failed, so
    /// its "Try again" doesn't outlive the message it belongs to.
    func dismissWeekMutationError() {
        failedFillWeekStartDate = nil
        weekStore.clearMutationError()
    }

    // MARK: Loading

    /// Default trigger (`.sceneActive`) is a "make sure it's fresh" request —
    /// used when the tab reappears or the week picker re-selects the current
    /// week, both of which happen far more often than the data actually
    /// needs refetching. Explicit user actions (the toolbar refresh button,
    /// an error retry) pass `.pullToRefresh` instead, which always forces a
    /// real reload through `AppRefreshCoordinator`. Browsing to a different
    /// week (Last/Next) isn't a coordinator-owned resource — `loadWeek`
    /// still checks `usesSeededCoreReader` itself here, since nothing else
    /// on that path does — but it writes into the same `WeekStore.dayRows`
    /// slot `refreshWeek` tracks freshness for, so it must invalidate that
    /// tracking on the way out. Without this, browsing to Last/Next week and
    /// back to This week inside the coordinator's freshness window left the
    /// view stuck showing the browsed week's rows: the coordinator saw a
    /// recent "current week" fetch and no-op'd the `.sceneActive` return,
    /// never noticing `loadWeek` had overwritten the slot in between.
    func reloadViewedWeek(trigger: AppRefreshCoordinator.Trigger = .sceneActive) async {
        guard let household = householdStore.activeHousehold else { return }
        if isViewingCurrentWeek {
            await refreshCurrentWeek(household, trigger)
        } else {
            guard !usesSeededCoreReader else { return }
            await weekStore.loadWeek(household: household, weekStartDate: viewedWeekStartDate)
            invalidateWeekFreshness(household.id)
        }
    }

    /// Jumps to next week and loads it — the weekend nudge's CTA and the
    /// hero's "Plan next week".
    func planNextWeek() {
        viewedWeekOffset = .next
        lastTask = Task { await reloadViewedWeek() }
    }

    /// nil until checked. Populated by a lightweight prefetch only on
    /// weekend days while viewing the current week — it's not needed
    /// otherwise.
    func refreshNextWeekEmptyState() async {
        guard !usesSeededCoreReader else { return }
        guard isViewingCurrentWeek else { return }
        let weekday = Calendar.current.component(.weekday, from: Date())
        guard weekday == 1 || weekday == 7 else { return }
        guard let household = householdStore.activeHousehold else { return }
        let nextWeekStart = ViewedWeekOffset.next.weekStartDate
        let hasContent = await weekStore.peekHasContent(household: household, weekStartDate: nextWeekStart)
        nextWeekIsEmpty = !hasContent
    }

    /// Week/prep/household-details are core-reader resources —
    /// `RootView`'s `AppRefreshCoordinator.refreshCoreReader` (cold
    /// launch) and `AppModel.loadActiveHouseholdReaderData`
    /// (household switch/join/leave) already guarantee them fresh by
    /// the time this fires. Re-fetching them here too was Fas 7's
    /// core bug: a genuine second network call for the same data,
    /// not just a redundant guard. Retro and the next-week-empty peek
    /// aren't coordinator-owned resources (Retro is this screen's own
    /// `RetroCardViewModel`, reading *last* week; the peek is a
    /// cheap, weekend-only check — see `refreshNextWeekEmptyState`),
    /// so they stay here.
    ///
    /// The view runs this from `.task(id: activeHousehold?.id)`, i.e.
    /// whenever `activeHousehold?.id` actually changes (nil → set, or a
    /// household switch). That is also what `onAppear`'s own calls to these
    /// two can't reliably cover on cold launch: `onAppear` fires once, as
    /// soon as the tab mounts, which on cold launch can be *before*
    /// `householdStore.activeHousehold` is known — its own guards then
    /// silently no-op, and nothing re-tries until the next unrelated
    /// `scenePhase` change or tab reappearance. On a weekend day that left
    /// the "Plan next week" CTA (see `shouldOfferPlanNextWeekFromWeekDone`)
    /// waiting far longer than the actual network call took (2026-08-03 bug
    /// report) — this reliably firing the moment the household *is* known
    /// closes that gap.
    func activeHouseholdDidChange() async {
        guard !usesSeededCoreReader else { return }
        guard let household = householdStore.activeHousehold else { return }
        await refreshNextWeekEmptyState()
        await retro.load(household: household, weekStore: weekStore, outcomeStore: mealOutcomeStore, apiClient: retroClient)
    }

    func sceneDidBecomeActive() {
        // Handles the app being backgrounded over a week/day boundary
        // without needing a live timer.
        refreshWeekendNudgeDismissalState()
        // Week/shopping/prep/etc. are refreshed centrally by
        // `RootView`'s own scene-active handler through
        // `AppRefreshCoordinator` — this only covers what the
        // coordinator doesn't own: the weekend next-week peek and the
        // Sunday retro (see `activeHouseholdDidChange`).
        guard !usesSeededCoreReader, isViewingCurrentWeek,
              let household = householdStore.activeHousehold else { return }
        lastTask = Task {
            await refreshNextWeekEmptyState()
            await retro.load(household: household, weekStore: weekStore, outcomeStore: mealOutcomeStore, apiClient: retroClient)
        }
    }

    func retroResolved() {
        recordEvent(.retroCompleted, WeekCalendar.addWeeks(to: WeekCalendar.currentWeekStartDate(), offset: -1), [:])
        retro.clear()
    }

    func makeWeekBriefStore() -> WeekBriefStore {
        WeekBriefStore(apiClient: weekBriefClient)
    }

    // MARK: Deep links

    /// One-shot consumption of the "plan next week" deep link set by
    /// `AppNotificationDelegate` when the user tapped the Sunday planning
    /// reminder. Returns whether it actually fired, so callers can decide
    /// whether to fall back to their own default week selection.
    @discardableResult
    func consumePendingWeekPlanDeepLink() -> Bool {
        guard deepLinks.pendingWeekPlan() else { return false }
        deepLinks.clearPendingWeekPlan()
        viewedWeekOffset = .next
        return true
    }

    /// Consumes a pending widget/notification meal link: switches to its
    /// week, loads it, and returns the day + recipe to open — or nil when
    /// the link doesn't (or no longer) match a planned dinner. Either way
    /// the link is cleared, so it's acted on exactly once.
    func consumePendingMealDeepLink() async -> SelectedDayRecipe? {
        guard case let .meal(date, recipeID) = deepLinks.pendingDeepLink() else { return nil }
        guard let targetDate = WeekCalendar.date(from: date) else {
            deepLinks.clearPendingDeepLink()
            return nil
        }
        let currentStart = WeekCalendar.date(from: WeekCalendar.currentWeekStartDate()) ?? targetDate
        let targetStartString = WeekCalendar.currentWeekStartDate(now: targetDate)
        let targetStart = WeekCalendar.date(from: targetStartString) ?? targetDate
        let days = WeekCalendar.calendar.dateComponents([.day], from: currentStart, to: targetStart).day ?? 0
        let weeks = days / 7
        guard let offset = ViewedWeekOffset(rawValue: weeks) else {
            deepLinks.clearPendingDeepLink()
            return nil
        }
        viewedWeekOffset = offset
        await reloadViewedWeek()
        guard let row = weekStore.dayRows.first(where: { $0.date == date }),
              let recipe = row.recipe,
              recipeID == nil || recipe.id == recipeID else {
            deepLinks.clearPendingDeepLink()
            return nil
        }
        deepLinks.clearPendingDeepLink()
        return SelectedDayRecipe(day: row, recipe: recipe)
    }

    // MARK: Weekend nudge

    var shouldShowWeekendNudge: Bool {
        guard isViewingCurrentWeek, !weekendNudgeDismissedToday, nextWeekIsEmpty == true else { return false }
        let weekday = Calendar.current.component(.weekday, from: Date())
        let isWeekend = weekday == 1 || weekday == 7 // Sunday = 1, Saturday = 7
        return isWeekend
    }

    /// Gate for the "Plan next week" CTA inside the hero's `.weekDone`
    /// state: only worth surfacing once the household is actually near the
    /// week boundary (Sat/Sun) or already knows next week is unplanned —
    /// not on an ordinary Tuesday when "the week is done" just means
    /// today's the last relevant planning day for a household that doesn't
    /// cook every night. Unlike the weekend nudge, this isn't
    /// per-day-dismissible: it's the one durable exit from an otherwise
    /// dead-end completion state (see the 2026-08-02 TestFlight bug report
    /// — a household landed here from the Sunday reminder notification
    /// with no visible way to start planning next week).
    var shouldOfferPlanNextWeekFromWeekDone: Bool {
        guard isViewingCurrentWeek, heroMode == .weekDone else { return false }
        let weekday = Calendar.current.component(.weekday, from: Date())
        let isLateInWeek = weekday == 1 || weekday == 7 // Sunday = 1, Saturday = 7
        return isLateInWeek || nextWeekIsEmpty == true
    }

    func refreshWeekendNudgeDismissalState() {
        guard let dismissedDate = defaults.object(forKey: Self.weekendNudgeDismissalKey) as? Date else {
            weekendNudgeDismissedToday = false
            return
        }
        weekendNudgeDismissedToday = Calendar.current.isDateInToday(dismissedDate)
    }

    func dismissWeekendNudgeForToday() {
        defaults.set(Date(), forKey: Self.weekendNudgeDismissalKey)
        weekendNudgeDismissedToday = true
    }

    // MARK: Quality suggestion

    var qualitySuggestion: WeekQualitySuggestion? {
        WeekQualitySuggestion.make(
            days: weekPlanningScope.relevantDays(in: weekStore.dayRows),
            recipes: recipeStore.recipes,
            prepCoveredDates: prepCoveredDates
        )
    }

    var visibleQualitySuggestion: WeekQualitySuggestion? {
        guard let suggestion = qualitySuggestion else { return nil }
        return dismissedQualitySuggestionKeys.contains(qualitySuggestionWeekKey) ? nil : suggestion
    }

    private var qualitySuggestionWeekKey: String {
        let householdID = householdStore.activeHousehold?.id ?? ""
        return "\(householdID):\(viewedWeekStartDate)"
    }

    func dismissQualitySuggestionsForViewedWeek() {
        var keys = dismissedQualitySuggestionKeys
        keys.insert(qualitySuggestionWeekKey)
        defaults.set(keys.sorted().joined(separator: "|"), forKey: Self.dismissedQualitySuggestionKeysKey)
        dismissedQualitySuggestionKeys = keys
    }

    /// A leftovers suggestion is reviewed in the prep-batch sheet, so it
    /// returns the seed for the caller to present; a replacement suggestion
    /// is applied right away (and only dismissed once the write succeeded).
    func applyQualitySuggestion(_ suggestion: WeekQualitySuggestion) -> PrepBatchSeed? {
        guard canMutateDay(suggestion.day) else { return nil }
        if suggestion.kind == .useLeftovers,
           let source = suggestion.sourceDay,
           let recipe = source.recipe {
            dismissQualitySuggestionsForViewedWeek()
            return PrepBatchSeed(
                recipeID: recipe.id,
                cookDate: source.date,
                weekStartDate: viewedWeekStartDate,
                assignedDate: suggestion.day.date
            )
        }

        guard let recipe = suggestion.replacement else { return nil }
        guard let (household, userID) = session() else { return nil }
        let wasEmptyBefore = hasOpenRelevantDays
        lastTask = Task {
            shoppingListStore.invalidateCache()
            await weekStore.assignMeal(
                day: suggestion.day,
                recipe: WeekSummaryRecipe(fullRecipe: recipe),
                household: household,
                userID: userID,
                viewedWeekStartDate: viewedWeekStartDate
            )
            await refreshShoppingListAfterWeekMutation(household: household, weekStartDate: viewedWeekStartDate)
            guard weekStore.mutationError == nil else { return }
            dismissQualitySuggestionsForViewedWeek()
            checkForSessionEnd(wasEmptyBefore: wasEmptyBefore)
        }
        return nil
    }

    // MARK: Planning session end

    /// Fires the "Veckan är klar" beat the instant the last *relevant* open
    /// day gets filled or skipped by a real user action — never on merely
    /// browsing to an already-full week (only mutators that can close the
    /// last gap call this, each with `hasOpenRelevantDays` captured just
    /// before they ran).
    func checkForSessionEnd(wasEmptyBefore: Bool) {
        guard isViewingCurrentWeek else { return }
        let summary = weekSessionSummary
        guard SessionEndTrigger.shouldShow(
            wasEmptyBeforeMutation: wasEmptyBefore,
            isCompleteNow: !hasOpenRelevantDays,
            plannedDinnerCount: summary.plannedDinnerCount
        ) else { return }
        showSessionEndBeat = true
        recordEvent(.weekCompleted, viewedWeekStartDate, [
            "plannedDinners": .int(summary.plannedDinnerCount),
            "quickDinners": .int(summary.quickDinnerCount),
            "prepFriendlyDinners": .int(summary.prepFriendlyDinnerCount)
        ])
    }

    func dismissSessionEndBeat() {
        showSessionEndBeat = false
    }
}

extension WeekScreenModel {
    static func live(_ app: AppModel) -> WeekScreenModel {
        WeekScreenModel(
            weekStore: app.weekStore,
            householdStore: app.householdStore,
            shoppingListStore: app.shoppingListStore,
            prepBatchStore: app.prepBatchStore,
            recipeStore: app.recipeStore,
            authSessionStore: app.authSessionStore,
            mealOutcomeStore: app.mealOutcomeStore,
            retroClient: app.apiClient,
            weekBriefClient: app.apiClient,
            usesSeededCoreReader: app.usesSeededCoreReader,
            refreshCurrentWeek: { household, trigger in
                await app.refreshCoordinator.refreshWeek(household: household, trigger: trigger)
            },
            invalidateWeekFreshness: { householdID in
                app.refreshCoordinator.invalidateWeek(householdID: householdID)
            },
            deepLinks: WeekDeepLinkInbox(
                pendingWeekPlan: { app.pendingWeekPlanDeepLink },
                clearPendingWeekPlan: { app.pendingWeekPlanDeepLink = false },
                pendingDeepLink: { app.pendingDeepLink },
                clearPendingDeepLink: { app.pendingDeepLink = nil }
            ),
            recordEvent: { eventName, weekStartDate, properties in
                app.recordProductEvent(eventName, weekStartDate: weekStartDate, properties: properties)
            },
            onUnauthorized: { await app.handleUnauthorized() }
        )
    }
}

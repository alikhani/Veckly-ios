import Foundation
import Observation

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
    private let recordEvent: (ProductEventName, String?, ProductEventProperties) -> Void
    private let onUnauthorized: () async -> Void

    // MARK: Screen state

    var viewedWeekOffset: ViewedWeekOffset = .current
    /// "Veckan är klar" — a one-time, dismissible beat shown the moment the
    /// last empty day of the current week gets filled or skipped (see
    /// `checkForSessionEnd`). Not persisted anywhere: scoped to this
    /// session, gone once dismissed or the CTA is tapped.
    private(set) var showSessionEndBeat = false

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
        recordEvent: @escaping (ProductEventName, String?, ProductEventProperties) -> Void,
        onUnauthorized: @escaping () async -> Void
    ) {
        self.weekStore = weekStore
        self.householdStore = householdStore
        self.shoppingListStore = shoppingListStore
        self.prepBatchStore = prepBatchStore
        self.recipeStore = recipeStore
        self.authSessionStore = authSessionStore
        self.recordEvent = recordEvent
        self.onUnauthorized = onUnauthorized
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
            recordEvent: { eventName, weekStartDate, properties in
                app.recordProductEvent(eventName, weekStartDate: weekStartDate, properties: properties)
            },
            onUnauthorized: { await app.handleUnauthorized() }
        )
    }
}

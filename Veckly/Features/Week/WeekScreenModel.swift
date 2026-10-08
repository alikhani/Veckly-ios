import Foundation
import Observation

/// The 3-week browsing window. Last week is view-only (no planning actions);
/// This/Next week behave like the active week but addressed explicitly.
/// Not `private` — `WeekHeaderView` (Fas 3 extraction) needs it too.
enum ViewedWeekOffset: Int, CaseIterable, Identifiable {
    case last = -1
    case current = 0
    case next = 1

    var id: Int { rawValue }

    var relativeLabelKey: String {
        switch self {
        case .last: "week.lastWeek"
        case .current: "week.thisWeek"
        case .next: "week.nextWeek"
        }
    }

    var isViewOnly: Bool { self == .last }
}

extension ViewedWeekOffset {
    var weekStartDate: String {
        WeekCalendar.addWeeks(to: WeekCalendar.currentWeekStartDate(), offset: rawValue)
    }

    func subtitleLabel() -> String {
        let start = weekStartDate
        let weekNumber = WeekCalendar.weekNumber(for: start)
        let range = WeekCalendar.dateRangeLabel(weekStartDate: start)
        return "\(L10n.format("format.week", weekNumber)) · \(range)"
    }
}

/// The app-level deep-link slots the Week tab consumes, as closures so the
/// model never depends on `AppModel` itself.
struct WeekDeepLinkInbox {
    var pendingWeekPlan: () -> Bool
    var clearPendingWeekPlan: () -> Void
    var pendingDeepLink: () -> AppDeepLink?
    var clearPendingDeepLink: () -> Void
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
    // The model is split by responsibility across `WeekScreenModel+*.swift`.
    // Swift's `private` doesn't reach extensions in other files, so the
    // dependencies and screen state below are internal: only the model's own
    // extensions write them — views read them and call intents.

    // MARK: Dependencies

    let weekStore: WeekStore
    let householdStore: HouseholdStore
    let shoppingListStore: ShoppingListStore
    let prepBatchStore: PrepBatchStore
    let recipeStore: RecipeStore
    let authSessionStore: AuthSessionStore
    let mealOutcomeStore: MealOutcomeStore
    let retroClient: any RetroCardAPIClient
    let weekBriefClient: any WeekBriefAPIClient
    let usesSeededCoreReader: Bool
    let refreshCurrentWeek: (Household, AppRefreshCoordinator.Trigger) async -> Void
    let invalidateWeekFreshness: (_ householdID: String) -> Void
    let deepLinks: WeekDeepLinkInbox
    let defaults: UserDefaults
    let recordEvent: (ProductEventName, String?, ProductEventProperties) -> Void
    let onUnauthorized: () async -> Void

    static let weekendNudgeDismissalKey = "veckly.week.weekendNudgeDismissedDate"
    static let dismissedQualitySuggestionKeysKey = "dismissedWeekQualitySuggestionKeys"

    // MARK: Screen state

    var viewedWeekOffset: ViewedWeekOffset = .current
    /// "Veckan är klar" — a one-time, dismissible beat shown the moment the
    /// last empty day of the current week gets filled or skipped (see
    /// `checkForSessionEnd`). Not persisted anywhere: scoped to this
    /// session, gone once dismissed or the CTA is tapped.
    var showSessionEndBeat = false
    var regenerateUndo: RegenerateUndoContext?
    var fillCompletionNotice: WeekFillCompletionNotice?
    var failedFillWeekStartDate: String?
    /// The one sheet the Week tab is presenting, if any.
    var sheet: WeekSheet?
    /// nil until checked — see `refreshNextWeekEmptyState`.
    var nextWeekIsEmpty: Bool?
    var weekendNudgeDismissedToday = false
    /// Mirrors the persisted `dismissedWeekQualitySuggestionKeys` value
    /// (formerly the view's `@AppStorage`), kept here so the view re-renders
    /// when a suggestion is dismissed.
    var dismissedQualitySuggestionKeys: Set<String>
    /// The Sunday retro on last week's dinners.
    let retro = RetroCardViewModel()
    @ObservationIgnored var regenerateUndoDismissTask: Task<Void, Never>?
    /// How long the undo banner stays up after a regenerate. Injectable so
    /// tests don't have to wait out the real 8 seconds.
    let regenerateUndoDuration: Duration

    /// The work started by the most recent fire-and-forget intent (or the
    /// unauthorized handling it triggered). The view never awaits it — it
    /// exists so tests can wait for an intent's effects deterministically.
    var lastTask: Task<Void, Never>?

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

    // MARK: Sheets

    /// Closes `sheet` only if it is still the one identified by `id` — a
    /// sheet's own close/dismiss callback must never close a different
    /// sheet that has since replaced it (as separate `.sheet` modifiers
    /// each guaranteed before this enum existed).
    func dismissSheet(_ id: String) {
        guard sheet?.id == id else { return }
        sheet = nil
    }

    /// Sheets in SwiftUI can't be swapped directly — presenting a new one
    /// while another is still dismissing is silently dropped. A short delay
    /// lets the dismiss animation finish first; centralized here so all
    /// "close this sheet, then open that one" flows share the same timing.
    /// `makeSheet` runs after the delay, so it sees state as of then; a nil
    /// result presents nothing.
    func presentAfterDismiss(_ makeSheet: @escaping () -> WeekSheet?) {
        lastTask = Task {
            try? await Task.sleep(for: .milliseconds(50))
            if let next = makeSheet() {
                sheet = next
            }
        }
    }

    // MARK: Day intents

    /// Shared tap handling for both the main list and the collapsed weekend
    /// section — a day already owned by the hero (today, when the hero is
    /// showing today) has no tap target of its own (beslut 3); the hero
    /// itself carries the actions.
    func openDay(_ day: WeekDayRowViewModel) {
        if isViewingCurrentWeek, day.isToday, todayRowIsHeroOwned { return }
        switch weekListPresentation.interaction(for: day) {
        case .none:
            break
        case .viewRecipe:
            viewRecipe(day)
        case .editDay:
            sheet = .dayDetail(day)
        case .planDay:
            sheet = .mealPicker(day)
        }
    }

    func viewRecipe(_ day: WeekDayRowViewModel) {
        if let recipe = day.recipe {
            sheet = .recipe(SelectedDayRecipe(day: day, recipe: recipe))
        }
    }

    /// The hero's "Swap" and "Plan tonight".
    func pickMeal(for day: WeekDayRowViewModel) {
        guard canMutateDay(day) else { return }
        sheet = .mealPicker(day)
    }

    func rescue(_ day: WeekDayRowViewModel) {
        guard canMutateDay(day), !day.isLocked else { return }
        sheet = .rescue(day)
    }

    /// The hero's "Cook extra": a prep batch seeded from tonight's dinner.
    func cookExtra(_ day: WeekDayRowViewModel) {
        guard canMutateDay(day) else { return }
        if let recipe = day.recipe {
            sheet = .prepBatch(PrepBatchSeed(
                recipeID: recipe.id,
                cookDate: day.date,
                weekStartDate: viewedWeekStartDate
            ))
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

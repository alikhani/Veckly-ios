import SwiftUI

/// Pairs a recipe with the day it belongs to, so RecipeDetailView can offer
/// day-level actions (skip/plan) in context.
private struct SelectedDayRecipe: Identifiable {
    let day: WeekDayRowViewModel
    let recipe: WeekSummaryRecipe
    var id: String { recipe.id + day.id }
}

/// Seeds a new prep batch from a day that's already planned — "we made
/// extra of this, mark it as eaten again on other days" — without making
/// the user re-pick the recipe or cook date in `PrepBatchFormSheet`.
private struct PrepBatchSeed: Identifiable {
    let recipeID: String
    let cookDate: String
    var id: String { recipeID + cookDate }
}

/// Snapshot of the days a "Regenerate" run is about to overwrite, captured
/// just before the API call — restoring from it is how the undo banner puts
/// the previous plan back without the backend needing an undo endpoint.
private struct RegenerateUndoContext: Identifiable {
    let rows: [WeekDayRowViewModel]
    let weekStartDate: String
    var id: String { weekStartDate }
}

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

private let weekendNudgeDismissalKey = "veckly.week.weekendNudgeDismissedDate"

struct WeekTabView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onGoToShoppingTab: (() -> Void)? = nil
    var onGoToHouseholdTab: (() -> Void)? = nil
    @State private var selectedDayRecipe: SelectedDayRecipe?
    @State private var mealPickerDay: WeekDayRowViewModel?
    @State private var selectedDayForDetail: WeekDayRowViewModel?
    @State private var prepBatchSeed: PrepBatchSeed?
    @State private var viewedWeekOffset: ViewedWeekOffset = .current
    @State private var isWeekPickerPresented = false
    @State private var weekendNudgeDismissedToday = false
    @State private var nextWeekIsEmpty: Bool?
    @AppStorage("hasSeenLockExplanation") private var hasSeenLockExplanation = false
    @State private var showLockExplanation = false
    @State private var showRegenerateConfirmation = false
    @State private var regenerateUndoContext: RegenerateUndoContext?
    @State private var regenerateUndoDismissTask: Task<Void, Never>?
    @State private var retroViewModel = RetroCardViewModel()
    @State private var showSessionEndBeat = false
    @State private var isWeekendExpanded = false

    private var viewedWeekStartDate: String {
        viewedWeekOffset.weekStartDate
    }

    private var isViewingCurrentWeek: Bool { viewedWeekOffset == .current }
    private var isViewingLastWeek: Bool { viewedWeekOffset == .last }
    private var weekPendingSyncMessage: String { L10n.string("week.sync.pending") }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let err = appModel.weekStore.mutationError {
                    HStack(spacing: 10) {
                        Text(err)
                            .font(.subheadline)
                            .foregroundStyle(VecklyDesign.Colors.inkDeep)
                        Spacer()
                        Button {
                            appModel.weekStore.clearMutationError()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(VecklyDesign.Colors.inkMid)
                        }
                        .accessibilityLabel(L10n.string("common.dismissError"))
                    }
                    .padding(12)
                    .background(VecklyDesign.Colors.surfaceStrong)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                if let err = appModel.prepBatchStore.mutationError {
                    HStack(spacing: 10) {
                        Text(err)
                            .font(.subheadline)
                            .foregroundStyle(VecklyDesign.Colors.inkDeep)
                        Spacer()
                        Button {
                            appModel.prepBatchStore.clearMutationError()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(VecklyDesign.Colors.inkMid)
                        }
                        .accessibilityLabel(L10n.string("common.dismissError"))
                    }
                    .padding(12)
                    .background(VecklyDesign.Colors.surfaceStrong)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                WeekHeaderView(
                    householdName: appModel.householdStore.activeHousehold?.name ?? L10n.string("week.yourHousehold"),
                    viewedWeekOffset: $viewedWeekOffset,
                    isWeekPickerPresented: $isWeekPickerPresented,
                    onSelectWeek: { _ in Task { await reloadViewedWeek() } }
                )

                sessionEndBeatCard

                if isViewingCurrentWeek, !retroViewModel.rows.isEmpty {
                    RetroCard(
                        viewModel: retroViewModel,
                        feedbackStore: appModel.feedbackStore,
                        householdID: appModel.householdStore.activeHousehold?.id ?? "",
                        onResolved: {
                            appModel.recordProductEvent(.retroCompleted, weekStartDate: WeekCalendar.addWeeks(to: WeekCalendar.currentWeekStartDate(), offset: -1))
                            retroViewModel.clear()
                        }
                    )
                }

                if appModel.weekStore.hasPendingSync && isViewingCurrentWeek {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(weekPendingSyncMessage)
                            .font(.caption)
                            .foregroundStyle(VecklyDesign.Colors.inkMid)
                    }
                }

                if isViewingCurrentWeek {
                    weekendNudgeBanner
                }

                if appModel.householdStore.isLoading || appModel.weekStore.isLoading {
                    LoadingPanel(title: L10n.string("week.loading"))
                } else if appModel.weekStore.generatingWeekStartDate == viewedWeekStartDate {
                    LoadingPanel(title: L10n.string("week.generating"))
                } else if let errorMessage = appModel.weekStore.errorMessage ?? appModel.householdStore.errorMessage {
                    ErrorPanel(message: errorMessage) {
                        Task { await reloadViewedWeek() }
                    }
                } else if !appModel.weekStore.hasWeekContent {
                    if isViewingCurrentWeek {
                        emptyWeekView
                    } else {
                        tonightHeroCard
                    }
                } else {
                    tonightHeroCard
                    if !isViewingLastWeek {
                        weekPlanningStatusCard
                    }
                    weekQualityCard
                    if !isViewingLastWeek || appModel.weekStore.hasPlannedMeals {
                        weekList
                        collapsedWeekendSection
                    }
                }
            }
            .padding(18)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: hasOpenRelevantDays)
        }
        .background(VecklyDesign.Colors.canvas)
        .navigationBarTitleDisplayMode(.inline)
        // The scroll content's own `.background(canvas)` above only paints
        // what's actually laid out in the ScrollView; it doesn't reach the
        // navigation bar / top safe-area's own scroll-edge material, which
        // otherwise falls back to the system default (opaque black in dark
        // mode) and makes the header/toolbar unreadable against it once
        // content scrolls under it. Pinning both to canvas explicitly is
        // what keeps the two layers visually seamless in both appearances.
        .toolbarBackground(VecklyDesign.Colors.canvas, for: .navigationBar)
        .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        .toolbar {
            // Beslut: "Planera resten" (and, for a complete week, the full
            // "Gör om veckan" redo) now live as CTAs inside
            // `weekPlanningStatusCard`'s content card — the toolbar's only
            // remaining job is refresh, which is why this is a single
            // `ToolbarItem` rather than a `ToolbarItemGroup`: a group with
            // exactly one control renders as an ambiguous empty-looking
            // Liquid Glass pill on iOS 26.
            if appModel.weekStore.generatingWeekStartDate == viewedWeekStartDate {
                ToolbarItem(placement: .topBarTrailing) {
                    ProgressView()
                }
            } else if !isViewingLastWeek {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await reloadViewedWeek() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel(L10n.string("common.refresh"))
                }
            }
        }
        .sheet(item: $selectedDayRecipe) { pair in
            NavigationStack {
                RecipeDetailView(
                    recipe: pair.recipe,
                    householdID: appModel.householdStore.activeHousehold?.id ?? "",
                    isSkipped: pair.day.isSkipped,
                    onSkip: {
                        guard let household = appModel.householdStore.activeHousehold else { return }
                        if let userID = appModel.authSessionStore.userID {
                            selectedDayRecipe = nil
                            Task { await appModel.weekStore.toggleSkip(day: pair.day, household: household, userID: userID, viewedWeekStartDate: viewedWeekStartDate) }
                        } else {
                            Task { await appModel.handleUnauthorized() }
                        }
                    }
                )
            }
        }
        .sheet(item: $mealPickerDay) { day in
            MealPickerSheet(
                day: day,
                isSkipped: day.isSkipped,
                coverage: coverage(for: day),
                householdID: appModel.householdStore.activeHousehold?.id ?? "",
                onSelect: { recipe in
                    guard let household = appModel.householdStore.activeHousehold else { return }
                    if let userID = appModel.authSessionStore.userID {
                        let wasEmptyBefore = hasOpenRelevantDays
                        Task {
                            appModel.shoppingListStore.invalidateCache()
                            await appModel.weekStore.assignMeal(day: day, recipe: recipe.asWeekSummaryRecipe, household: household, userID: userID, viewedWeekStartDate: viewedWeekStartDate)
                            await refreshShoppingListAfterWeekMutation(household: household, weekStartDate: viewedWeekStartDate)
                            checkForSessionEnd(wasEmptyBefore: wasEmptyBefore)
                        }
                    } else {
                        Task { await appModel.handleUnauthorized() }
                    }
                },
                onClear: {
                    guard let household = appModel.householdStore.activeHousehold else { return }
                    if let userID = appModel.authSessionStore.userID {
                        mealPickerDay = nil
                        Task {
                            appModel.shoppingListStore.invalidateCache()
                            await appModel.weekStore.unassignMeal(day: day, household: household, userID: userID, viewedWeekStartDate: viewedWeekStartDate)
                            await refreshShoppingListAfterWeekMutation(household: household, weekStartDate: viewedWeekStartDate)
                        }
                    } else {
                        Task { await appModel.handleUnauthorized() }
                    }
                },
                onSkip: {
                    guard let household = appModel.householdStore.activeHousehold else { return }
                    if let userID = appModel.authSessionStore.userID {
                        let wasEmptyBefore = hasOpenRelevantDays
                        Task {
                            await appModel.weekStore.toggleSkip(day: day, household: household, userID: userID, viewedWeekStartDate: viewedWeekStartDate)
                            checkForSessionEnd(wasEmptyBefore: wasEmptyBefore)
                        }
                    } else {
                        Task { await appModel.handleUnauthorized() }
                    }
                },
                onMarkAsLeftover: { recipeID in
                    mealPickerDay = nil
                    presentAfterDismiss { prepBatchSeed = PrepBatchSeed(recipeID: recipeID, cookDate: day.date) }
                },
                onMarkAsLeftoverNoRecipe: {
                    guard let hid = appModel.householdStore.activeHousehold?.id else { return }
                    mealPickerDay = nil
                    Task {
                        try? await appModel.prepBatchStore.create(
                            householdID: hid,
                            weekStartDate: appModel.weekStore.weekStartDate,
                            recipeId: nil,
                            cookDate: day.date,
                            totalPortions: 4,
                            assignments: [(date: day.date, mealType: .dinner)]
                        )
                    }
                },
                onRemoveCoverage: {
                    guard let hid = appModel.householdStore.activeHousehold?.id,
                          let dayCoverage = coverage(for: day) else { return }
                    mealPickerDay = nil
                    Task {
                        try? await appModel.prepBatchStore.removeAssignment(
                            householdID: hid,
                            batchID: dayCoverage.batchID,
                            date: day.date,
                            mealType: dayCoverage.mealType
                        )
                    }
                },
                onDismiss: { mealPickerDay = nil }
            )
        }
        .sheet(item: $selectedDayForDetail) { day in
            DayDetailSheet(
                day: day,
                householdID: appModel.householdStore.activeHousehold?.id ?? "",
                onViewRecipe: {
                    selectedDayForDetail = nil
                    presentAfterDismiss {
                        if let recipe = day.recipe {
                            selectedDayRecipe = SelectedDayRecipe(day: day, recipe: recipe)
                        }
                    }
                },
                onSwap: {
                    selectedDayForDetail = nil
                    presentAfterDismiss { mealPickerDay = day }
                },
                onSkip: {
                    guard let household = appModel.householdStore.activeHousehold else { return }
                    if let userID = appModel.authSessionStore.userID {
                        Task { await appModel.weekStore.toggleSkip(day: day, household: household, userID: userID, viewedWeekStartDate: viewedWeekStartDate) }
                    } else {
                        Task { await appModel.handleUnauthorized() }
                    }
                },
                onClear: {
                    guard let household = appModel.householdStore.activeHousehold else { return }
                    if let userID = appModel.authSessionStore.userID {
                        selectedDayForDetail = nil
                        Task {
                            appModel.shoppingListStore.invalidateCache()
                            await appModel.weekStore.unassignMeal(day: day, household: household, userID: userID, viewedWeekStartDate: viewedWeekStartDate)
                            await refreshShoppingListAfterWeekMutation(household: household, weekStartDate: viewedWeekStartDate)
                        }
                    } else {
                        Task { await appModel.handleUnauthorized() }
                    }
                },
                onMarkAsLeftover: {
                    selectedDayForDetail = nil
                    if let recipe = day.recipe {
                        presentAfterDismiss { prepBatchSeed = PrepBatchSeed(recipeID: recipe.id, cookDate: day.date) }
                    }
                },
                isLocked: day.isLocked,
                onToggleLock: {
                    guard let household = appModel.householdStore.activeHousehold else { return }
                    guard let userID = appModel.authSessionStore.userID else {
                        Task { await appModel.handleUnauthorized() }
                        return
                    }
                    appModel.weekStore.clearMutationError()
                    if !hasSeenLockExplanation {
                        showLockExplanation = true
                    }
                    Task { await appModel.weekStore.toggleLock(day: day, household: household, userID: userID) }
                },
                onDismiss: { selectedDayForDetail = nil }
            )
        }
        .sheet(item: $prepBatchSeed) { seed in
            PrepBatchFormSheet(initialRecipeID: seed.recipeID, initialCookDate: WeekCalendar.date(from: seed.cookDate) ?? Date())
        }
        .task(id: appModel.householdStore.activeHousehold?.id) {
            // See `reloadViewedWeek` — seeded UI-test data must stay
            // network-free.
            guard !appModel.usesSeededCoreReader else { return }
            guard let household = appModel.householdStore.activeHousehold else { return }
            async let week: Void = appModel.weekStore.loadCurrentWeek(household: household)
            async let prep: Void = appModel.prepBatchStore.load(householdID: household.id, weekStartDate: WeekCalendar.currentWeekStartDate())
            async let retro: Void = retroViewModel.load(household: household, weekStore: appModel.weekStore, feedbackStore: appModel.feedbackStore, apiClient: appModel.apiClient)
            async let details: Void = appModel.householdStore.loadHouseholdDetails(householdID: household.id)
            _ = await (week, prep, retro, details)
            await refreshNextWeekEmptyState()
        }
        .onAppear {
            // Browsing is a transient peek, not a persisted location — always
            // land back on the current week when the tab reappears.
            viewedWeekOffset = .current
            isWeekendExpanded = false
            refreshWeekendNudgeDismissalState()
            Task { await reloadViewedWeek() }
            Task { await refreshNextWeekEmptyState() }
        }
        .onChange(of: viewedWeekOffset) { _, _ in
            // The undo banner replays writes against `context.weekStartDate`
            // by matching rows on weekday only, with no check that the
            // currently-loaded `dayRows` still belong to that week — so if
            // the user browses to a different week while the banner is still
            // up, a tap on "Undo" would overwrite the *other* week's rows
            // with the regenerated week's snapshot. Simplest safe fix: the
            // banner only makes sense for the week it was generated for, so
            // drop it the moment the user navigates away from that week.
            regenerateUndoDismissTask?.cancel()
            regenerateUndoContext = nil
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard !appModel.usesSeededCoreReader else { return }
            guard newPhase == .active else { return }
            // Handles the app being backgrounded over a week/day boundary
            // without needing a live timer.
            refreshWeekendNudgeDismissalState()
            if isViewingCurrentWeek {
                Task {
                    guard let household = appModel.householdStore.activeHousehold else { return }
                    await appModel.weekStore.loadCurrentWeek(household: household)
                    await refreshNextWeekEmptyState()
                    await retroViewModel.load(household: household, weekStore: appModel.weekStore, feedbackStore: appModel.feedbackStore, apiClient: appModel.apiClient)
                }
            }
        }
        .alert(L10n.string("week.lock.explainTitle"), isPresented: $showLockExplanation) {
            Button(L10n.string("common.ok")) { hasSeenLockExplanation = true }
        } message: {
            Text(L10n.string("week.lock.explainMessage"))
        }
        .confirmationDialog(
            L10n.string("week.regenerateConfirm.title"),
            isPresented: $showRegenerateConfirmation,
            titleVisibility: .visible
        ) {
            Button(L10n.string("week.regenerateConfirm.confirm"), role: .destructive) {
                Task { await performGenerate(regenerate: true) }
            }
            Button(L10n.string("common.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.string("week.regenerateConfirm.message"))
        }
        .overlay(alignment: .bottom) {
            if let regenerateUndoContext {
                regenerateUndoBanner(regenerateUndoContext)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: regenerateUndoContext?.id)
    }

    /// Runs Generate/Regenerate. When replacing an already-full week, snapshots
    /// the unlocked/unskipped rows first so a successful run can offer "Undo" —
    /// there's no backend undo endpoint, so restoring is just re-issuing the
    /// same assign/clear calls a user would make by hand.
    private func performGenerate(regenerate: Bool) async {
        guard let household = appModel.householdStore.activeHousehold else { return }
        guard let userID = appModel.authSessionStore.userID else {
            await appModel.handleUnauthorized()
            return
        }

        // Captured once, up front — `viewedWeekStartDate` is a computed
        // property that tracks live navigation, and the API call below can
        // take long enough for the user to browse to a different week
        // before it resolves. Everything about *this* generate run (the
        // snapshot, the API call, and the undo banner it may offer) must
        // stay pinned to the week it was actually generated for.
        let targetWeekStartDate = viewedWeekStartDate
        let preRegenerateSnapshot = regenerate
            ? appModel.weekStore.dayRows.filter { !$0.isLocked && !$0.isSkipped }
            : []
        let wasEmptyBefore = hasOpenRelevantDays
        let hadWeekContentBefore = appModel.weekStore.hasWeekContent

        appModel.shoppingListStore.invalidateCache()
        await appModel.weekStore.generateWeek(
            household: household,
            userID: userID,
            regenerate: regenerate,
            viewedWeekStartDate: targetWeekStartDate
        )
        await refreshShoppingListAfterWeekMutation(household: household, weekStartDate: targetWeekStartDate)
        if !regenerate, !hadWeekContentBefore, appModel.weekStore.mutationError == nil {
            appModel.recordProductEvent(.firstWeekGenerated, weekStartDate: targetWeekStartDate, properties: [
                "plannedDinners": .int(plannedDinnerCount)
            ])
        }
        checkForSessionEnd(wasEmptyBefore: wasEmptyBefore)

        guard regenerate, appModel.weekStore.mutationError == nil, !preRegenerateSnapshot.isEmpty else { return }
        // Only offer undo if the user is still looking at the week that was
        // just regenerated — otherwise there's nothing sensible to restore
        // into the currently-visible week, and no banner should appear for
        // a week that isn't on screen.
        guard viewedWeekStartDate == targetWeekStartDate else { return }
        presentRegenerateUndo(rows: preRegenerateSnapshot, weekStartDate: targetWeekStartDate)
    }

    /// Fires the "Veckan är klar" beat the instant the last *relevant* open
    /// day gets filled or skipped by a real user action — never on merely
    /// browsing to an already-full week (only mutators that can close the
    /// last gap call this, each with `hasOpenRelevantDays` captured just
    /// before they ran).
    private func checkForSessionEnd(wasEmptyBefore: Bool) {
        guard isViewingCurrentWeek, wasEmptyBefore, !hasOpenRelevantDays, plannedDinnerCount > 0 else { return }
        showSessionEndBeat = true
        appModel.recordProductEvent(.weekCompleted, weekStartDate: viewedWeekStartDate, properties: [
            "plannedDinners": .int(plannedDinnerCount),
            "quickDinners": .int(quickDinnerCount),
            "prepFriendlyDinners": .int(prepFriendlyDinnerCount)
        ])
    }

    private func presentRegenerateUndo(rows: [WeekDayRowViewModel], weekStartDate: String) {
        regenerateUndoDismissTask?.cancel()
        regenerateUndoContext = RegenerateUndoContext(rows: rows, weekStartDate: weekStartDate)
        regenerateUndoDismissTask = Task {
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            regenerateUndoContext = nil
        }
    }

    private func undoRegenerate(_ context: RegenerateUndoContext) {
        regenerateUndoDismissTask?.cancel()
        regenerateUndoContext = nil
        guard let household = appModel.householdStore.activeHousehold,
              let userID = appModel.authSessionStore.userID else { return }
        // Defense in depth alongside the `.onChange(of: viewedWeekOffset)`
        // dismissal above — never replay a snapshot into a week other than
        // the one it was taken from.
        guard context.weekStartDate == viewedWeekStartDate else { return }

        Task {
            appModel.shoppingListStore.invalidateCache()
            for row in context.rows {
                if let recipe = row.recipe {
                    await appModel.weekStore.assignMeal(day: row, recipe: recipe, household: household, userID: userID, viewedWeekStartDate: context.weekStartDate)
                } else {
                    await appModel.weekStore.unassignMeal(day: row, household: household, userID: userID, viewedWeekStartDate: context.weekStartDate)
                }
            }
            await refreshShoppingListAfterWeekMutation(household: household, weekStartDate: context.weekStartDate)
        }
    }

    private func refreshShoppingListAfterWeekMutation(household: Household, weekStartDate: String) async {
        guard appModel.weekStore.mutationError == nil else { return }
        appModel.shoppingListStore.invalidateCache()
        await appModel.shoppingListStore.loadCurrentWeek(household: household, weekStartDate: weekStartDate)
    }

    private func regenerateUndoBanner(_ context: RegenerateUndoContext) -> some View {
        HStack(spacing: 12) {
            Text("week.regenerate.undoBanner")
                .font(.subheadline)
                .foregroundStyle(.white)
            Spacer()
            Button(L10n.string("common.undo")) {
                undoRegenerate(context)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(VecklyDesign.Colors.hearthOrange)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(VecklyDesign.Colors.inkDeep)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }

    private func reloadViewedWeek() async {
        // Seeded UI-test data is already final the moment `AppModel` seeds
        // it — a real network reload here would silently overwrite it with
        // a load error, since there's no backend behind it. A proper
        // app-wide network-free UI-test mode is Fas 7 scope; this is the
        // minimal guard `WeekTabView` needs in the meantime.
        guard !appModel.usesSeededCoreReader else { return }
        guard let household = appModel.householdStore.activeHousehold else { return }
        if isViewingCurrentWeek {
            await appModel.weekStore.loadCurrentWeek(household: household)
        } else {
            await appModel.weekStore.loadWeek(household: household, weekStartDate: viewedWeekStartDate)
        }
    }

    /// `WeekHeaderView` (Fas 3 extraction) owns the household/week-title/date
    /// chrome and its own week-picker popover; this stays only because
    /// `nextWeekSummaryCard`/`lastWeekSummaryCard` still need the plain
    /// subtitle string for the currently-viewed offset.
    private var weekSubtitleLabel: String {
        viewedWeekOffset.subtitleLabel()
    }

    private var shouldShowWeekendNudge: Bool {
        guard isViewingCurrentWeek, !weekendNudgeDismissedToday, nextWeekIsEmpty == true else { return false }
        let weekday = Calendar.current.component(.weekday, from: Date())
        let isWeekend = weekday == 1 || weekday == 7 // Sunday = 1, Saturday = 7
        return isWeekend
    }

    /// nil until checked. Populated by a lightweight prefetch (see
    /// `refreshNextWeekEmptyState`) only on weekend days while viewing the
    /// current week — it's not needed otherwise.
    private func refreshNextWeekEmptyState() async {
        guard !appModel.usesSeededCoreReader else { return }
        guard isViewingCurrentWeek else { return }
        let weekday = Calendar.current.component(.weekday, from: Date())
        guard weekday == 1 || weekday == 7 else { return }
        guard let household = appModel.householdStore.activeHousehold else { return }
        let nextWeekStart = ViewedWeekOffset.next.weekStartDate
        let hasContent = await appModel.weekStore.peekHasContent(household: household, weekStartDate: nextWeekStart)
        nextWeekIsEmpty = !hasContent
    }

    @ViewBuilder
    private var weekendNudgeBanner: some View {
        if shouldShowWeekendNudge {
            HStack(spacing: 12) {
                Text("week.weekendNudge.title")
                    .font(.subheadline)
                    .foregroundStyle(VecklyDesign.Colors.inkDeep)
                Spacer()
                Button("week.weekendNudge.cta") {
                    viewedWeekOffset = .next
                    Task { await reloadViewedWeek() }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(VecklyDesign.Colors.hearthOrange)
                Button {
                    dismissWeekendNudgeForToday()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(VecklyDesign.Colors.inkMid)
                }
                .accessibilityLabel(L10n.string("common.dismiss"))
            }
            .padding(12)
            .background(VecklyDesign.Colors.surfaceStrong)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func refreshWeekendNudgeDismissalState() {
        let defaults = UserDefaults.standard
        guard let dismissedDate = defaults.object(forKey: weekendNudgeDismissalKey) as? Date else {
            weekendNudgeDismissedToday = false
            return
        }
        weekendNudgeDismissedToday = Calendar.current.isDateInToday(dismissedDate)
    }

    private func dismissWeekendNudgeForToday() {
        UserDefaults.standard.set(Date(), forKey: weekendNudgeDismissalKey)
        weekendNudgeDismissedToday = true
    }

    /// "Veckan är klar" — a one-time, dismissible beat shown the moment the
    /// last empty day of the current week gets filled or skipped (see
    /// `checkForSessionEnd`). Not persisted anywhere: it's local `@State`,
    /// scoped to this session, gone once dismissed or the CTA is tapped.
    @ViewBuilder
    private var sessionEndBeatCard: some View {
        if showSessionEndBeat, isViewingCurrentWeek {
            VecklyCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("week.sessionEnd.title")
                            .font(VecklyDesign.Typography.displayHeading(size: 20))
                            .foregroundStyle(VecklyDesign.Colors.inkDeep)
                        Spacer()
                        Button {
                            showSessionEndBeat = false
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(VecklyDesign.Colors.inkMid)
                        }
                        .accessibilityLabel(L10n.string("common.dismiss"))
                    }

                    Text(L10n.format(plannedDinnerCount == 1 ? "week.summary.plannedDinners.one" : "week.summary.plannedDinners.other", plannedDinnerCount))
                        .font(.body.weight(.medium))
                        .foregroundStyle(VecklyDesign.Colors.inkMid)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(sessionEndSummaryRows.enumerated()), id: \.offset) { _, row in
                            Label {
                                Text(verbatim: row.text)
                                    .font(.subheadline)
                                    .foregroundStyle(VecklyDesign.Colors.inkMid)
                            } icon: {
                                Image(systemName: row.icon)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(VecklyDesign.Colors.hearthOrange)
                            }
                        }
                    }
                    .padding(.top, 2)

                    Button("week.sessionEnd.cta") {
                        showSessionEndBeat = false
                        appModel.recordProductEvent(.shoppingOpenedAfterWeekCompleted, weekStartDate: viewedWeekStartDate)
                        onGoToShoppingTab?()
                    }
                    .buttonStyle(VecklyPrimaryButtonStyle())
                    .padding(.top, 4)

                    if shouldShowSessionEndInviteNudge {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("week.sessionEnd.inviteHint")
                                .font(.footnote)
                                .foregroundStyle(VecklyDesign.Colors.inkMid)
                            Button("week.sessionEnd.inviteCta") {
                                showSessionEndBeat = false
                                appModel.recordProductEvent(.partnerInviteClicked, weekStartDate: viewedWeekStartDate)
                                onGoToHouseholdTab?()
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(VecklyDesign.Colors.hearthOrange)
                        }
                        .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var emptyWeekView: some View {
        VStack(alignment: .leading, spacing: 16) {
            VecklyCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("week.empty.eyebrow")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(VecklyDesign.Colors.inkFaint)
                        .textCase(.uppercase)

                    Text("week.empty.title")
                        .font(VecklyDesign.Typography.displayHeading(size: 22))
                        .foregroundStyle(VecklyDesign.Colors.inkDeep)

                    Text("week.empty.message")
                        .font(.body)
                        .foregroundStyle(VecklyDesign.Colors.inkMid)

                    Button("week.empty.primary") {
                        Task { await performGenerate(regenerate: false) }
                    }
                    .buttonStyle(VecklyPrimaryButtonStyle())
                    .padding(.top, 4)
                    .disabled(appModel.householdStore.activeHousehold == nil)

                    Button("week.empty.secondary") {
                        mealPickerDay = appModel.weekStore.dayRows.first(where: { $0.isToday })
                            ?? appModel.weekStore.dayRows.first(where: { !$0.isPast })
                    }
                    .disabled(appModel.weekStore.dayRows.isEmpty)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(VecklyDesign.Colors.hearthOrange)
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("week.section")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(VecklyDesign.Colors.inkFaint)
                .padding(.top, 4)

            ForEach(appModel.weekStore.dayRows) { day in
                if !day.isPast {
                    Button { mealPickerDay = day } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(day.weekdayLabel)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(day.isToday ? VecklyDesign.Colors.hearthOrange : VecklyDesign.Colors.inkMid)
                                Text(day.dateLabel)
                                    .font(.caption)
                                    .foregroundStyle(VecklyDesign.Colors.inkFaint)
                            }
                            .frame(width: 72, alignment: .leading)

                            Rectangle()
                                .fill(VecklyDesign.Colors.edgeLight)
                                .frame(height: 1)
                        }
                        .frame(height: 36)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Whether leftovers from a prep batch cover this day's dinner — checked
    /// in the view layer so `WeekStore`/`PrepBatchStore` stay decoupled. The
    /// week view is dinner-only today (one meal slot per day), so `.dinner`
    /// is the correct meal type explicitly, not just a date-based guess.
    private func coverage(for day: WeekDayRowViewModel) -> PrepBatchCoverage? {
        prepBatchCoverage(for: day.date, mealType: .dinner, batches: appModel.prepBatchStore.batches, recipes: appModel.recipeStore.recipes)
    }

    /// Planning-days-are-the-truth (beslut 1): built from the household's
    /// profile so open-day counts, the quality card, session-end, and the
    /// generate/regenerate CTA all agree on which days actually count.
    private var weekPlanningScope: WeekPlanningScope {
        WeekPlanningScope(profile: appModel.householdStore.cachedProfile(
            for: appModel.householdStore.activeHousehold?.id ?? ""
        ))
    }

    /// Dates covered by a prep/leftovers batch but with no recipe of their
    /// own — same rule `weekQualityCard` already used, now shared with the
    /// scope so a prep-covered day counts as "done" everywhere.
    private var prepCoveredDates: Set<String> {
        Set(appModel.weekStore.dayRows.compactMap { day in
            coverage(for: day) == nil ? nil : day.date
        })
    }

    /// Scope-aware replacement for `WeekStore.hasEmptyDays`: true only when a
    /// *relevant* planning day is still open. Days outside the household's
    /// selected planning days never make this true.
    private var hasOpenRelevantDays: Bool {
        !weekPlanningScope.isComplete(days: appModel.weekStore.dayRows, coveredDates: prepCoveredDates)
    }

    /// Sheets in SwiftUI can't be swapped directly — presenting a new one
    /// while another is still dismissing is silently dropped. A short delay
    /// lets the dismiss animation finish first; centralized here so all
    /// "close this sheet, then open that one" flows share the same timing.
    private func presentAfterDismiss(_ present: @escaping () -> Void) {
        Task {
            try? await Task.sleep(for: .milliseconds(50))
            present()
        }
    }

    /// The four hero states (beslut 16) — only meaningful for the current
    /// week (Last/Next week have zero `isToday` rows by definition, and are
    /// rendered by `nextWeekHeroCard`/`nextWeekSummaryCard`/`lastWeekSummaryCard`
    /// instead, which predate this phase and aren't "today"-framed).
    private var heroMode: TonightMealCardMode {
        TonightMealCardMode.compute(
            dayRows: appModel.weekStore.dayRows,
            scope: weekPlanningScope,
            hasCoverage: { coverage(for: $0) != nil }
        )
    }

    /// True when the hero card is already showing *today's* row — in that
    /// case the matching row in the week list below must not duplicate the
    /// hero's actions (beslut 3). In the other two modes (`.upcomingMeal`,
    /// `.weekDone`) the hero isn't representing today, so today's row (if
    /// shown at all) behaves like any other row.
    private var todayRowIsHeroOwned: Bool {
        switch heroMode {
        case .tonightMeal, .openTonight: true
        case .upcomingMeal, .weekDone: false
        }
    }

    private var plannedDinnerCount: Int {
        weekPlanningScope.relevantDays(in: appModel.weekStore.dayRows)
            .filter { !$0.isSkipped && ($0.recipe != nil || coverage(for: $0) != nil) }
            .count
    }

    private var quickDinnerCount: Int {
        appModel.weekStore.dayRows.filter { day in
            guard !day.isSkipped, let recipe = day.recipe, let totalMinutes = totalMinutes(for: recipe) else { return false }
            return totalMinutes <= 30
        }.count
    }

    private var prepFriendlyDinnerCount: Int {
        appModel.weekStore.dayRows.filter { day in
            guard !day.isSkipped else { return false }
            if coverage(for: day) != nil { return true }
            guard let recipe = day.recipe else { return false }
            return recipe.tags.contains { tag in
                let normalized = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return normalized.contains("leftover")
                    || normalized.contains("rester")
                    || normalized.contains("meal prep")
                    || normalized.contains("batch")
                    || normalized.contains("storkok")
            }
        }.count
    }

    private var sessionEndSummaryRows: [(icon: String, text: String)] {
        var rows: [(icon: String, text: String)] = []
        if quickDinnerCount > 0 {
            rows.append((
                icon: "clock",
                text: L10n.format(quickDinnerCount == 1 ? "week.sessionEnd.quick.one" : "week.sessionEnd.quick.other", quickDinnerCount)
            ))
        }
        if prepFriendlyDinnerCount > 0 {
            rows.append((
                icon: "takeoutbag.and.cup.and.straw",
                text: L10n.format(prepFriendlyDinnerCount == 1 ? "week.sessionEnd.prep.one" : "week.sessionEnd.prep.other", prepFriendlyDinnerCount)
            ))
        }
        rows.append((icon: "cart", text: L10n.string("week.sessionEnd.shoppingReady")))
        return rows
    }

    private var shouldShowSessionEndInviteNudge: Bool {
        SessionEndInviteNudgeEligibility.shouldShow(
            activeHousehold: appModel.householdStore.activeHousehold,
            detailsHouseholdID: appModel.householdStore.detailsHouseholdID,
            memberCount: appModel.householdStore.members.count
        )
    }

    private func totalMinutes(for recipe: WeekSummaryRecipe) -> Int? {
        let total = [recipe.prepTimeMinutes, recipe.cookTimeMinutes].compactMap { $0 }.reduce(0, +)
        return total > 0 ? total : nil
    }

    private var openDayCount: Int {
        weekPlanningScope.openDays(in: appModel.weekStore.dayRows, coveredDates: prepCoveredDates).count
    }

    private var weekSummaryLine: String {
        let dinnerCount = plannedDinnerCount
        let dayCount = openDayCount
        let dinnersPart = L10n.format(dinnerCount == 1 ? "week.summary.plannedDinners.one" : "week.summary.plannedDinners.other", dinnerCount)
        let daysPart = L10n.format(dayCount == 1 ? "week.summary.openDays.one" : "week.summary.openDays.other", dayCount)
        return "\(dinnersPart) · \(daysPart)"
    }

    private var weekQualitySummary: WeekQualitySummary {
        WeekQualitySummary.make(
            days: weekPlanningScope.relevantDays(in: appModel.weekStore.dayRows),
            prepCoveredDates: prepCoveredDates
        )
    }

    /// "Veckokoll" is replaced by `weekPlanningStatusCard` (Fas 3) — this
    /// card now only appears for insights that carry an actual warning
    /// (a heavy week, or several low-confidence picks), never for routine
    /// observations like "good variation" that the status card already
    /// covers in spirit.
    private var weekQualityWarnings: [WeekQualitySummary.Insight] {
        weekQualitySummary.insights.filter { insight in
            switch insight.kind {
            case .heavyWeek, .lowConfidence: true
            case .openDays, .quickRhythm, .prepFriendly, .goodVariation, .looksReasonable: false
            }
        }
    }

    @ViewBuilder
    private var weekQualityCard: some View {
        if !isViewingLastWeek, !weekQualityWarnings.isEmpty {
            VecklyCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("week.quality.title")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(VecklyDesign.Colors.inkFaint)
                        .textCase(.uppercase)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(weekQualityWarnings) { insight in
                            Label {
                                Text(verbatim: weekQualityText(for: insight))
                                    .font(.subheadline)
                                    .foregroundStyle(VecklyDesign.Colors.inkMid)
                            } icon: {
                                Image(systemName: insight.icon)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(VecklyDesign.Colors.hearthOrange)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Replaces "Veckokoll" as the primary status surface (Fas 3): a single
    /// primary CTA reflecting whether relevant planning days remain.
    @ViewBuilder
    private var weekPlanningStatusCard: some View {
        if appModel.weekStore.hasWeekContent {
            WeekPlanningStatusCard(
                openDayCount: openDayCount,
                isComplete: !hasOpenRelevantDays,
                onPlanRest: {
                    Task { await performGenerate(regenerate: false) }
                },
                onOpenShoppingList: {
                    onGoToShoppingTab?()
                },
                onRegenerate: {
                    guard appModel.householdStore.activeHousehold != nil else { return }
                    guard appModel.authSessionStore.userID != nil else {
                        Task { await appModel.handleUnauthorized() }
                        return
                    }
                    showRegenerateConfirmation = true
                }
            )
        }
    }

    private func weekQualityText(for insight: WeekQualitySummary.Insight) -> String {
        switch insight.kind {
        case .openDays(let count):
            L10n.format(count == 1 ? "week.quality.openDays.one" : "week.quality.openDays.other", count)
        case .quickRhythm(let count):
            L10n.format(count == 1 ? "week.quality.quick.one" : "week.quality.quick.other", count)
        case .heavyWeek(let count):
            L10n.format(count == 1 ? "week.quality.heavy.one" : "week.quality.heavy.other", count)
        case .prepFriendly(let count):
            L10n.format(count == 1 ? "week.quality.prep.one" : "week.quality.prep.other", count)
        case .lowConfidence(let count):
            L10n.format(count == 1 ? "week.quality.lowConfidence.one" : "week.quality.lowConfidence.other", count)
        case .goodVariation:
            L10n.string("week.quality.variation")
        case .looksReasonable:
            L10n.string("week.quality.reasonable")
        }
    }

    @ViewBuilder
    private var tonightHeroCard: some View {
        switch viewedWeekOffset {
        case .current:
            currentWeekHeroCard
        case .next:
            if appModel.weekStore.hasWeekContent {
                nextWeekSummaryCard
            } else {
                nextWeekHeroCard
            }
        case .last:
            lastWeekSummaryCard
        }
    }

    /// Beslut 16's four hero states, rendered by `TonightMealCard`. Lock
    /// lives in `DayDetailSheet` and the list's status icon now, not here
    /// (beslut 3) — so unlike the pre-Fas-3 hero, this view never needs
    /// `hasSeenLockExplanation`/`showLockExplanation`.
    private var currentWeekHeroCard: some View {
        TonightMealCard(
            mode: heroMode,
            coverage: { coverage(for: $0) },
            onViewRecipe: { day in
                if let recipe = day.recipe {
                    selectedDayRecipe = SelectedDayRecipe(day: day, recipe: recipe)
                }
            },
            onSwap: { day in mealPickerDay = day },
            onPlanTonight: { day in mealPickerDay = day },
            onEatExtra: { day in
                if let recipe = day.recipe {
                    prepBatchSeed = PrepBatchSeed(recipeID: recipe.id, cookDate: day.date)
                }
            },
            onRemoveCoverage: { day, dayCoverage in
                guard let household = appModel.householdStore.activeHousehold else { return }
                Task {
                    try? await appModel.prepBatchStore.removeAssignment(
                        householdID: household.id,
                        batchID: dayCoverage.batchID,
                        date: day.date,
                        mealType: dayCoverage.mealType
                    )
                }
            }
        )
    }

    /// Next week, nothing planned yet: forward-looking copy + a CTA to
    /// generate it now, instead of "Tonight" framing that doesn't apply.
    /// Mirrors emptyWeekView's structure (eyebrow/title/message/CTAs + day
    /// list) so browsing ahead previews the week's structure, not just a CTA.
    private var nextWeekHeroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VecklyCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("week.nextWeek.empty.eyebrow")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(VecklyDesign.Colors.inkFaint)
                        .textCase(.uppercase)

                    Text("week.nextWeek.empty.title")
                        .font(VecklyDesign.Typography.displayHeading(size: 22))
                        .foregroundStyle(VecklyDesign.Colors.inkDeep)

                    Text("week.nextWeek.empty.message")
                        .font(.body)
                        .foregroundStyle(VecklyDesign.Colors.inkMid)

                    Button("week.nextWeek.empty.cta") {
                        Task { await performGenerate(regenerate: false) }
                    }
                    .buttonStyle(VecklyPrimaryButtonStyle())
                    .padding(.top, 4)
                    .disabled(appModel.householdStore.activeHousehold == nil)

                    Button("week.empty.secondary") {
                        mealPickerDay = appModel.weekStore.dayRows.first
                    }
                    .disabled(appModel.weekStore.dayRows.isEmpty)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(VecklyDesign.Colors.hearthOrange)
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("week.section")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(VecklyDesign.Colors.inkFaint)
                .padding(.top, 4)

            ForEach(appModel.weekStore.dayRows) { day in
                Button { mealPickerDay = day } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(day.weekdayLabel)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(VecklyDesign.Colors.inkMid)
                            Text(day.dateLabel)
                                .font(.caption)
                                .foregroundStyle(VecklyDesign.Colors.inkFaint)
                        }
                        .frame(width: 72, alignment: .leading)

                        Rectangle()
                            .fill(VecklyDesign.Colors.edgeLight)
                            .frame(height: 1)
                    }
                    .frame(height: 36)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Next week already has a plan: a compact summary card showing the date
    /// range and a dinner count. No "Tonight" framing and no Generate CTA —
    /// the toolbar Generate/Regenerate button remains available if needed.
    private var nextWeekSummaryCard: some View {
        VecklyCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(weekSubtitleLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VecklyDesign.Colors.inkFaint)
                    .textCase(.uppercase)
                Text(weekSummaryLine)
                    .font(VecklyDesign.Typography.displayHeading(size: 20))
                    .foregroundStyle(VecklyDesign.Colors.inkDeep)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Next week already has a plan, or any state of Last week: a compact
    /// summary, no "Tonight" framing (there's no today in this week), and for
    /// Last week specifically, no actions — viewing only.
    private var lastWeekSummaryCard: some View {
        VecklyCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.string(viewedWeekOffset.relativeLabelKey))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VecklyDesign.Colors.hearthOrange)
                    .textCase(.uppercase)
                Text(weekSummaryLine)
                    .font(VecklyDesign.Typography.displayHeading(size: 20))
                    .foregroundStyle(VecklyDesign.Colors.inkDeep)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Saturday/Sunday rows — only relevant when deciding whether to collapse
    /// them (beslut 8); a household that plans the weekend never collapses it.
    private var weekendDays: [WeekDayRowViewModel] {
        appModel.weekStore.dayRows.filter { $0.weekday == .saturday || $0.weekday == .sunday }
    }

    /// Beslut 8: only households that never plan Sat/Sun get a collapsed
    /// weekend section. A household with the weekend in `selectedDays` sees
    /// it as regular rows in `listDays`, counted in scope like any other day.
    private var shouldCollapseWeekend: Bool {
        !weekPlanningScope.includesWeekend && !weekendDays.isEmpty
    }

    /// The week list always shows every relevant day, in order, with no
    /// holes (beslut 3) — weekend days are the one exception, moved to
    /// `collapsedWeekendSection` when the household doesn't plan them.
    private var listDays: [WeekDayRowViewModel] {
        guard shouldCollapseWeekend else { return appModel.weekStore.dayRows }
        return appModel.weekStore.dayRows.filter { $0.weekday != .saturday && $0.weekday != .sunday }
    }

    /// Shared tap handling for both the main list and the collapsed weekend
    /// section — a day already owned by the hero (today, when the hero is
    /// showing today) has no tap target of its own (beslut 3); the hero
    /// itself carries the actions.
    private func handleDayTap(_ day: WeekDayRowViewModel) {
        if isViewingLastWeek {
            if let recipe = day.recipe { selectedDayRecipe = SelectedDayRecipe(day: day, recipe: recipe) }
            return
        }
        if isViewingCurrentWeek, day.isToday, todayRowIsHeroOwned { return }
        if day.recipe != nil { selectedDayForDetail = day }
        else if !day.isPast { mealPickerDay = day }
    }

    private func dayRow(_ day: WeekDayRowViewModel) -> some View {
        CompactDayRow(
            day: day,
            coverage: coverage(for: day),
            isTodayBadge: day.isToday,
            isHeroOwned: isViewingCurrentWeek && day.isToday && todayRowIsHeroOwned,
            isViewOnly: isViewingLastWeek,
            onTap: { handleDayTap(day) }
        )
    }

    private var weekList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(weekListSectionLabel)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(VecklyDesign.Colors.inkFaint)
                .padding(.bottom, 4)

            ForEach(listDays) { day in
                dayRow(day)
                if day.id != listDays.last?.id {
                    Divider().padding(.leading, 56)
                }
            }
        }
        .accessibilityIdentifier("weekPlanList")
    }

    private var weekListSectionLabel: LocalizedStringKey {
        "week.section"
    }

    /// Beslut 8: a disclosure the household can open to plan an optional
    /// weekend day without it affecting scope, the status card, or the hero.
    @ViewBuilder
    private var collapsedWeekendSection: some View {
        if shouldCollapseWeekend {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        isWeekendExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(isWeekendExpanded ? "week.hideWeekend" : "week.showWeekend")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(VecklyDesign.Colors.hearthOrange)
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(VecklyDesign.Colors.hearthOrange)
                            .rotationEffect(.degrees(isWeekendExpanded ? 180 : 0))
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("weekendToggle")

                if isWeekendExpanded {
                    ForEach(weekendDays) { day in
                        dayRow(day)
                        if day.id != weekendDays.last?.id {
                            Divider().padding(.leading, 56)
                        }
                    }
                }
            }
        }
    }
}

struct CompactDayRow: View {
    let day: WeekDayRowViewModel
    var coverage: PrepBatchCoverage? = nil
    /// Purely informational "I dag" chip — shown whenever this is literally
    /// today's row, independent of whether the hero happens to be showing
    /// today too. Informational redundancy between hero and list is
    /// intentional (beslut 3); only action redundancy is forbidden.
    var isTodayBadge: Bool = false
    /// True when the hero card above is already showing this exact day —
    /// only then does the row give up its tap target and trailing "Plan"
    /// hint, so the hero's actions are never duplicated (beslut 3).
    var isHeroOwned: Bool = false
    var isViewOnly: Bool = false
    let onTap: () -> Void

    var body: some View {
        Group {
            if isHeroOwned {
                rowContent
                    .accessibilityElement(children: .combine)
            } else {
                Button(action: onTap) {
                    rowContent
                }
                .buttonStyle(.plain)
            }
        }
        .opacity(isDimmed ? 0.7 : 1)
    }

    private var isDimmed: Bool { day.isPast || isHeroOwned }

    private var rowContent: some View {
        HStack(alignment: .center, spacing: 12) {
            dateColumn

            if isTodayBadge {
                todayBadge
            }

            if day.isSkipped {
                skippedContent
            } else if day.isEmpty {
                emptyContent
            } else {
                plannedContent
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var todayBadge: some View {
        Text("meal.today")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(VecklyDesign.Colors.hearthOrange)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(Capsule().stroke(VecklyDesign.Colors.hearthOrange, lineWidth: 1))
            .fixedSize()
    }

    private var dateColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(day.weekday.shortDisplayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(day.isToday ? VecklyDesign.Colors.hearthOrange : VecklyDesign.Colors.inkMid)
            Text(day.dateLabel)
                .font(.caption2)
                .foregroundStyle(VecklyDesign.Colors.inkFaint)
        }
        .frame(width: 44, alignment: .leading)
    }

    private var plannedContent: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(day.mealTitle)
                    .font(.body.weight(.medium))
                    .foregroundStyle(VecklyDesign.Colors.inkDeep)
                    .lineLimit(1)
                if let reason = day.reason {
                    Text(reason.label)
                        .font(.caption2)
                        .foregroundStyle(VecklyDesign.Colors.inkFaint)
                        .lineLimit(1)
                }
            }
            Spacer()
            if day.recipe == nil, let _ = coverage {
                Label(L10n.string("prep.fallbackTitle"), systemImage: "arrow.3.trianglepath")
                    .font(.caption)
                    .foregroundStyle(VecklyDesign.Colors.inkMid)
                    .accessibilityLabel(L10n.string("accessibility.coveredByLeftovers"))
            }
            if day.isLocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(VecklyDesign.Colors.hearthOrange)
                    .accessibilityLabel(L10n.string("accessibility.locked"))
            }
        }
    }

    private var emptyContent: some View {
        HStack(alignment: .center, spacing: 8) {
            if let coverage {
                Image(systemName: "arrow.3.trianglepath")
                    .font(.system(size: 12))
                    .foregroundStyle(VecklyDesign.Colors.inkMid)
                    .accessibilityLabel(L10n.string("accessibility.coveredByLeftovers"))
                Text(coverage.recipeTitle)
                    .font(.body.weight(.medium))
                    .foregroundStyle(VecklyDesign.Colors.inkDeep)
                    .lineLimit(1)
            } else {
                Text("meal.addDinner")
                    .font(.body.italic())
                    .foregroundStyle(VecklyDesign.Colors.inkFaint)
            }
            Spacer()
            if !day.isPast && !isViewOnly && !isHeroOwned {
                Text("meal.plan")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(VecklyDesign.Colors.hearthOrange)
            }
        }
    }

    /// A skipped day keeps its assigned meal (see `WeekDayRowViewModel.withSkipped`)
    /// so it's shown here, dimmed, alongside a "Skipped" badge — instead of a
    /// blank row that would make un-skipping look like it lost the plan.
    private var skippedContent: some View {
        HStack(alignment: .center, spacing: 8) {
            if !day.mealTitle.isEmpty {
                Text(day.mealTitle)
                    .font(.body.weight(.medium))
                    .foregroundStyle(VecklyDesign.Colors.inkFaint)
                    .lineLimit(1)
                    .strikethrough(color: VecklyDesign.Colors.inkFaint)
            }
            Text("meal.skipped")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(VecklyDesign.Colors.inkFaint)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(VecklyDesign.Colors.surfaceStrong)
                .clipShape(Capsule())
            Spacer()
            if !day.isPast && !isViewOnly && !isHeroOwned {
                Text("meal.plan")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(VecklyDesign.Colors.hearthOrange)
            }
        }
        .opacity(0.7)
    }
}

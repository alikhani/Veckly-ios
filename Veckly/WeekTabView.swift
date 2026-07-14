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
private enum ViewedWeekOffset: Int, CaseIterable, Identifiable {
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

private let weekendNudgeDismissalKey = "veckly.week.weekendNudgeDismissedDate"

struct WeekTabView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase
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

    private var viewedWeekStartDate: String {
        WeekCalendar.addWeeks(to: WeekCalendar.currentWeekStartDate(), offset: viewedWeekOffset.rawValue)
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

                header

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
                    weekQualityCard
                    if !isViewingLastWeek || appModel.weekStore.hasPlannedMeals {
                        weekList
                    }
                }
            }
            .padding(18)
        }
        .background(VecklyDesign.Colors.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if appModel.weekStore.generatingWeekStartDate == viewedWeekStartDate {
                    ProgressView()
                } else if !isViewingLastWeek {
                    Button {
                        guard appModel.householdStore.activeHousehold != nil else { return }
                        guard appModel.authSessionStore.userID != nil else {
                            Task { await appModel.handleUnauthorized() }
                            return
                        }
                        if appModel.weekStore.hasEmptyDays {
                            Task { await performGenerate(regenerate: false) }
                        } else {
                            showRegenerateConfirmation = true
                        }
                    } label: {
                        Text(appModel.weekStore.hasEmptyDays || !appModel.weekStore.hasWeekContent ? "week.generate" : "week.regenerate")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(VecklyDesign.Colors.hearthOrange)
                    .disabled(appModel.householdStore.activeHousehold == nil)

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
                        let wasEmptyBefore = appModel.weekStore.hasEmptyDays
                        Task {
                            await appModel.weekStore.assignMeal(day: day, recipe: recipe.asWeekSummaryRecipe, household: household, userID: userID, viewedWeekStartDate: viewedWeekStartDate)
                            appModel.shoppingListStore.invalidateCache()
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
                            await appModel.weekStore.unassignMeal(day: day, household: household, userID: userID, viewedWeekStartDate: viewedWeekStartDate)
                            appModel.shoppingListStore.invalidateCache()
                        }
                    } else {
                        Task { await appModel.handleUnauthorized() }
                    }
                },
                onSkip: {
                    guard let household = appModel.householdStore.activeHousehold else { return }
                    if let userID = appModel.authSessionStore.userID {
                        let wasEmptyBefore = appModel.weekStore.hasEmptyDays
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
                            await appModel.weekStore.unassignMeal(day: day, household: household, userID: userID, viewedWeekStartDate: viewedWeekStartDate)
                            appModel.shoppingListStore.invalidateCache()
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
                onDismiss: { selectedDayForDetail = nil }
            )
        }
        .sheet(item: $prepBatchSeed) { seed in
            PrepBatchFormSheet(initialRecipeID: seed.recipeID, initialCookDate: WeekCalendar.date(from: seed.cookDate) ?? Date())
        }
        .task(id: appModel.householdStore.activeHousehold?.id) {
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
        let wasEmptyBefore = appModel.weekStore.hasEmptyDays
        let hadWeekContentBefore = appModel.weekStore.hasWeekContent

        await appModel.weekStore.generateWeek(
            household: household,
            userID: userID,
            regenerate: regenerate,
            viewedWeekStartDate: targetWeekStartDate
        )
        appModel.shoppingListStore.invalidateCache()
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

    /// Fires the "Veckan är klar" beat the instant the last empty day gets
    /// filled or skipped by a real user action — never on merely browsing to
    /// an already-full week (only mutators that can close the last gap call
    /// this, each with `hasEmptyDays` captured just before they ran).
    private func checkForSessionEnd(wasEmptyBefore: Bool) {
        guard isViewingCurrentWeek, wasEmptyBefore, !appModel.weekStore.hasEmptyDays, plannedDinnerCount > 0 else { return }
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
            for row in context.rows {
                if let recipe = row.recipe {
                    await appModel.weekStore.assignMeal(day: row, recipe: recipe, household: household, userID: userID, viewedWeekStartDate: context.weekStartDate)
                } else {
                    await appModel.weekStore.unassignMeal(day: row, household: household, userID: userID, viewedWeekStartDate: context.weekStartDate)
                }
            }
            appModel.shoppingListStore.invalidateCache()
        }
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
        guard let household = appModel.householdStore.activeHousehold else { return }
        if isViewingCurrentWeek {
            await appModel.weekStore.loadCurrentWeek(household: household)
        } else {
            await appModel.weekStore.loadWeek(household: household, weekStartDate: viewedWeekStartDate)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(appModel.householdStore.activeHousehold?.name ?? L10n.string("week.yourHousehold"))
                .font(.subheadline)
                .foregroundStyle(VecklyDesign.Colors.hearthOrange)
                .textCase(.uppercase)

            Button {
                isWeekPickerPresented = true
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(L10n.string(viewedWeekOffset.relativeLabelKey))
                        .font(VecklyDesign.Typography.displayHeading(size: 34))
                        .foregroundStyle(VecklyDesign.Colors.inkDeep)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(VecklyDesign.Colors.inkMid)
                        .rotationEffect(.degrees(isWeekPickerPresented ? 180 : 0))
                        .animation(.easeInOut(duration: 0.15), value: isWeekPickerPresented)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(weekPickerTriggerAccessibilityLabel)
            .accessibilityHint(L10n.string("week.picker.hint"))
            .popover(isPresented: $isWeekPickerPresented, attachmentAnchor: .point(.bottomLeading), arrowEdge: .top) {
                weekPickerMenu
                    .presentationCompactAdaptation(.popover)
            }

            Text(weekSubtitleLabel)
                .font(.subheadline)
                .foregroundStyle(VecklyDesign.Colors.inkFaint)
        }
    }

    private func weekStartDate(for offset: ViewedWeekOffset) -> String {
        WeekCalendar.addWeeks(to: WeekCalendar.currentWeekStartDate(), offset: offset.rawValue)
    }

    private func subtitleLabel(for offset: ViewedWeekOffset) -> String {
        let start = weekStartDate(for: offset)
        let weekNumber = WeekCalendar.weekNumber(for: start)
        let range = WeekCalendar.dateRangeLabel(weekStartDate: start)
        return "\(L10n.format("format.week", weekNumber)) · \(range)"
    }

    private var weekSubtitleLabel: String {
        subtitleLabel(for: viewedWeekOffset)
    }

    private var weekPickerTriggerAccessibilityLabel: String {
        "\(L10n.string(viewedWeekOffset.relativeLabelKey)), \(weekSubtitleLabel)"
    }

    private var weekPickerMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(ViewedWeekOffset.allCases) { offset in
                Button {
                    viewedWeekOffset = offset
                    isWeekPickerPresented = false
                    Task { await reloadViewedWeek() }
                } label: {
                    weekPickerRow(for: offset)
                }
                .buttonStyle(.plain)

                if offset != ViewedWeekOffset.allCases.last {
                    Divider()
                }
            }
        }
        .frame(width: 260)
        .padding(.vertical, 4)
    }

    private func weekPickerRow(for offset: ViewedWeekOffset) -> some View {
        let isSelected = offset == viewedWeekOffset
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(L10n.string(offset.relativeLabelKey))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(VecklyDesign.Colors.inkDeep)
                    if offset.isViewOnly {
                        Text("week.viewOnly")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(VecklyDesign.Colors.inkFaint)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(VecklyDesign.Colors.surfaceStrong)
                            .clipShape(Capsule())
                    }
                }
                Text(subtitleLabel(for: offset))
                    .font(.caption)
                    .foregroundStyle(VecklyDesign.Colors.inkFaint)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(VecklyDesign.Colors.hearthOrange)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            offset.isViewOnly
                ? "\(L10n.string(offset.relativeLabelKey)), \(subtitleLabel(for: offset)), \(L10n.string("week.viewOnly"))"
                : "\(L10n.string(offset.relativeLabelKey)), \(subtitleLabel(for: offset))"
        )
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
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
        guard isViewingCurrentWeek else { return }
        let weekday = Calendar.current.component(.weekday, from: Date())
        guard weekday == 1 || weekday == 7 else { return }
        guard let household = appModel.householdStore.activeHousehold else { return }
        let nextWeekStart = weekStartDate(for: .next)
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

    /// A skipped day keeps its `recipe` (skip is a flag layered on top of an
    /// assignment, not a deletion — see `withSkipped`), so `isSkipped` must be
    /// checked explicitly here or a skipped "today" could still surface as
    /// tonight's hero.
    private func isDayConsideredPlanned(_ day: WeekDayRowViewModel) -> Bool {
        !day.isSkipped && (day.recipe != nil || coverage(for: day) != nil)
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

    /// Only meaningful for the current week — Last/Next week have zero
    /// `isToday` rows by definition, so callers must check `isViewingCurrentWeek`
    /// before relying on this.
    private var tonightHeroDay: WeekDayRowViewModel? {
        let rows = appModel.weekStore.dayRows
        if let today = rows.first(where: { $0.isToday && isDayConsideredPlanned($0) }) {
            return today
        }
        let todayIndex = rows.firstIndex(where: { $0.isToday }) ?? -1
        if todayIndex >= 0, let next = rows[(todayIndex + 1)...].first(where: { isDayConsideredPlanned($0) }) {
            return next
        }
        return rows.first(where: { isDayConsideredPlanned($0) && !$0.isPast })
    }

    private var tonightHeroLabel: String {
        guard let hero = tonightHeroDay else { return "" }
        if hero.isToday { return L10n.string("meal.tonight") }
        let rows = appModel.weekStore.dayRows
        let todayIndex = rows.firstIndex(where: { $0.isToday }) ?? -1
        let heroIndex = rows.firstIndex(where: { $0.id == hero.id }) ?? -1
        return heroIndex > todayIndex
            ? "\(L10n.string("week.nextUp")) · \(hero.weekdayLabel)"
            : "\(L10n.string("week.thisWeek")) · \(hero.weekdayLabel)"
    }

    private var plannedDinnerCount: Int {
        appModel.weekStore.dayRows.filter { !$0.isSkipped && ($0.recipe != nil || coverage(for: $0) != nil) }.count
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
        appModel.weekStore.dayRows.filter { $0.recipe == nil && !$0.isSkipped && coverage(for: $0) == nil }.count
    }

    private var weekSummaryLine: String {
        let dinnerCount = plannedDinnerCount
        let dayCount = openDayCount
        let dinnersPart = L10n.format(dinnerCount == 1 ? "week.summary.plannedDinners.one" : "week.summary.plannedDinners.other", dinnerCount)
        let daysPart = L10n.format(dayCount == 1 ? "week.summary.openDays.one" : "week.summary.openDays.other", dayCount)
        return "\(dinnersPart) · \(daysPart)"
    }

    private var weekQualitySummary: WeekQualitySummary {
        let prepCoveredDates = Set(appModel.weekStore.dayRows.compactMap { day in
            coverage(for: day) == nil ? nil : day.date
        })
        return WeekQualitySummary.make(days: appModel.weekStore.dayRows, prepCoveredDates: prepCoveredDates)
    }

    @ViewBuilder
    private var weekQualityCard: some View {
        if !isViewingLastWeek, !weekQualitySummary.insights.isEmpty {
            VecklyCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("week.quality.title")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(VecklyDesign.Colors.inkFaint)
                        .textCase(.uppercase)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(weekQualitySummary.insights) { insight in
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

    @ViewBuilder
    private var currentWeekHeroCard: some View {
        if let day = tonightHeroDay {
            // A day with no recipe of its own can still be tonight's hero if
            // leftovers cover it — show the covering dish instead of the
            // (empty) day fields, and hide the recipe/swap actions that
            // assume a bound `WeekSummaryRecipe`.
            let dayCoverage = day.recipe == nil ? coverage(for: day) : nil
            VecklyCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(tonightHeroLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(VecklyDesign.Colors.hearthOrange)
                            .textCase(.uppercase)
                        Spacer()
                        if day.isToday {
                            Text("meal.today")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(VecklyDesign.Colors.hearthOrange)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .overlay(Capsule().stroke(VecklyDesign.Colors.hearthOrange, lineWidth: 1))
                        }
                    }

                    Text(dayCoverage?.recipeTitle ?? day.mealTitle)
                        .font(VecklyDesign.Typography.displayHeading(size: 24))
                        .foregroundStyle(VecklyDesign.Colors.inkDeep)

                    if let dayCoverage {
                        Text(L10n.format("prep.leftoversFrom", WeekCalendar.shortDateLabel(yyyyMmDd: dayCoverage.cookDate)))
                            .font(.body)
                            .foregroundStyle(VecklyDesign.Colors.inkMid)
                    } else if !day.detail.isEmpty {
                        Text(day.detail)
                            .font(.body)
                            .foregroundStyle(VecklyDesign.Colors.inkMid)
                    }

                    if dayCoverage == nil, let reason = day.reason {
                        Text(reason.label)
                            .font(.caption)
                            .foregroundStyle(VecklyDesign.Colors.inkFaint)
                    }

                    if dayCoverage == nil, day.confidence == .low {
                        Label("week.confidence.low", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .foregroundStyle(VecklyDesign.Colors.hearthOrange)
                    }

                    if dayCoverage == nil, let streakWeeks = day.streakWeeks {
                        Label(L10n.format("week.satiation.hint", streakWeeks), systemImage: "arrow.2.squarepath")
                            .font(.caption)
                            .foregroundStyle(VecklyDesign.Colors.hearthOrange)
                    }

                    if dayCoverage == nil {
                        FlowLayout(spacing: 8) {
                            Button {
                                if let recipe = day.recipe {
                                    selectedDayRecipe = SelectedDayRecipe(day: day, recipe: recipe)
                                }
                            } label: {
                                Label("meal.recipe", systemImage: "book")
                            }
                            .buttonStyle(.bordered)
                            .tint(VecklyDesign.Colors.inkMid)
                            .accessibilityLabel(L10n.format("accessibility.viewRecipeFor", day.mealTitle))

                            Button {
                                mealPickerDay = day
                            } label: {
                                Label("meal.swap", systemImage: "arrow.2.squarepath")
                            }
                            .buttonStyle(.bordered)
                            .tint(VecklyDesign.Colors.inkMid)
                            .accessibilityLabel(L10n.format("accessibility.swapMealFor", day.weekdayLabel))

                            if let recipe = day.recipe {
                                Button {
                                    prepBatchSeed = PrepBatchSeed(recipeID: recipe.id, cookDate: day.date)
                                } label: {
                                    Label(L10n.string("prep.eatAgain"), systemImage: "arrow.3.trianglepath")
                                }
                                .buttonStyle(.bordered)
                                .tint(VecklyDesign.Colors.inkMid)
                            }

                            Button {
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
                            } label: {
                                Image(systemName: day.isLocked ? "lock.fill" : "lock.open")
                                    .frame(width: 20, height: 20)
                            }
                            .buttonStyle(.bordered)
                            .tint(day.isLocked ? VecklyDesign.Colors.hearthOrange : VecklyDesign.Colors.inkMid)
                            .accessibilityLabel(day.isLocked ? L10n.format("accessibility.unlock", day.weekdayLabel) : L10n.format("accessibility.lock", day.weekdayLabel))
                        }
                    } else if let dayCoverage {
                        Button(role: .destructive) {
                            guard let household = appModel.householdStore.activeHousehold else { return }
                            Task {
                                try? await appModel.prepBatchStore.removeAssignment(
                                    householdID: household.id,
                                    batchID: dayCoverage.batchID,
                                    date: day.date,
                                    mealType: dayCoverage.mealType
                                )
                            }
                        } label: {
                            Image(systemName: "trash")
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.bordered)
                        .tint(VecklyDesign.Colors.inkMid)
                        .accessibilityLabel(L10n.string("prep.removeCoverage"))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("tonightMealPanel")
            }
        }
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

    private var listDays: [WeekDayRowViewModel] {
        appModel.weekStore.dayRows
    }

    private var weekList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(weekListSectionLabel)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(VecklyDesign.Colors.inkFaint)
                .padding(.bottom, 4)

            ForEach(listDays) { day in
                CompactDayRow(
                    day: day,
                    coverage: coverage(for: day),
                    isHighlighted: isViewingCurrentWeek && day.id == tonightHeroDay?.id,
                    isViewOnly: isViewingLastWeek,
                    onTap: {
                        if isViewingLastWeek {
                            if let recipe = day.recipe { selectedDayRecipe = SelectedDayRecipe(day: day, recipe: recipe) }
                            return
                        }
                        if day.recipe != nil { selectedDayForDetail = day }
                        else if !day.isPast { mealPickerDay = day }
                    }
                )
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
}

struct CompactDayRow: View {
    let day: WeekDayRowViewModel
    var coverage: PrepBatchCoverage? = nil
    var isHighlighted: Bool = false
    var isViewOnly: Bool = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            rowContent
        }
        .buttonStyle(.plain)
        .opacity(day.isPast ? 0.7 : 1)
        .background {
            if isHighlighted {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(VecklyDesign.Colors.surfaceStrong)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(VecklyDesign.Colors.edgeLight, lineWidth: 1)
                    )
            }
        }
    }

    private var rowContent: some View {
        HStack(alignment: .center, spacing: 12) {
            dateColumn

            if day.isSkipped {
                skippedContent
            } else if day.isEmpty {
                emptyContent
            } else {
                plannedContent
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, isHighlighted ? 10 : 0)
        .contentShape(Rectangle())
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
            if !day.isPast && !isViewOnly {
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
            if !day.isPast && !isViewOnly {
                Text("meal.plan")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(VecklyDesign.Colors.hearthOrange)
            }
        }
        .opacity(0.7)
    }
}

/// Left-to-right wrapping layout. Views are placed at their intrinsic size with
/// `spacing` between them horizontally; when a view won't fit on the current
/// row it starts a new one, also separated by `spacing` vertically.
/// Requires iOS 16+ (Layout protocol); the app targets iOS 17, so this is safe.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let containerWidth = proposal.replacingUnspecifiedDimensions().width
        var rowX: CGFloat = 0
        var totalY: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let neededX = rowX == 0 ? size.width : rowX + spacing + size.width

            if rowX > 0 && neededX > containerWidth {
                totalY += rowHeight + spacing
                rowX = 0
                rowHeight = 0
            }

            rowX = rowX == 0 ? size.width : rowX + spacing + size.width
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: containerWidth, height: totalY + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let needsWrap = x > bounds.minX && x + spacing + size.width > bounds.maxX

            if needsWrap {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            } else if x > bounds.minX {
                x += spacing
            }

            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width
            rowHeight = max(rowHeight, size.height)
        }
    }
}

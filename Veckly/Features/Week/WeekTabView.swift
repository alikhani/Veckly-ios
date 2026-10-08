import SwiftUI

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

struct WeekTabView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: WeekScreenModel
    var onGoToShoppingTab: (() -> Void)? = nil
    var onGoToHouseholdTab: (() -> Void)? = nil
    @State private var isWeekPickerPresented = false
    @AppStorage("hasSeenLockExplanation") private var hasSeenLockExplanation = false
    @State private var showLockExplanation = false
    @State private var showRegenerateConfirmation = false
    @State private var isWeekendExpanded = false
    @State private var showQualitySuggestionConfirmation = false

    /// `model` is only read on first creation (`State(initialValue:)`), so
    /// a parent re-evaluating its body never replaces the live model.
    init(
        model: WeekScreenModel,
        onGoToShoppingTab: (() -> Void)? = nil,
        onGoToHouseholdTab: (() -> Void)? = nil
    ) {
        _model = State(initialValue: model)
        self.onGoToShoppingTab = onGoToShoppingTab
        self.onGoToHouseholdTab = onGoToHouseholdTab
    }

    private var viewedWeekOffset: ViewedWeekOffset { model.viewedWeekOffset }
    private var viewedWeekStartDate: String { model.viewedWeekStartDate }
    private var isViewingCurrentWeek: Bool { model.isViewingCurrentWeek }
    private var isViewingLastWeek: Bool { model.isViewingLastWeek }
    private var showSessionEndBeat: Bool { model.showSessionEndBeat }
    private var failedFillWeekStartDate: String? { model.failedFillWeekStartDate }
    private var fillCompletionNotice: WeekFillCompletionNotice? { model.fillCompletionNotice }
    private var regenerateUndoContext: RegenerateUndoContext? { model.regenerateUndo }
    private var retroViewModel: RetroCardViewModel { model.retro }
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
                        if failedFillWeekStartDate == viewedWeekStartDate {
                            Button("common.tryAgain") {
                                presentWeekBrief(regenerate: false)
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(VecklyDesign.Colors.hearthOrangeText)
                        }
                        Button {
                            model.dismissWeekMutationError()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(VecklyDesign.Colors.inkMid)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
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
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel(L10n.string("common.dismissError"))
                    }
                    .padding(12)
                    .background(VecklyDesign.Colors.surfaceStrong)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                WeekHeaderView(
                    householdName: appModel.householdStore.activeHousehold?.name ?? L10n.string("week.yourHousehold"),
                    viewedWeekOffset: $model.viewedWeekOffset,
                    isWeekPickerPresented: $isWeekPickerPresented,
                    onSelectWeek: { _ in Task { await model.reloadViewedWeek() } }
                )

                if CoreLoadingGate.shouldShowLoadingPanel(
                    isLoadingHouseholds: appModel.householdStore.isLoading,
                    isLoadingContent: appModel.weekStore.isLoading,
                    hasActiveHousehold: appModel.householdStore.activeHousehold != nil,
                    householdErrorMessage: appModel.householdStore.errorMessage,
                    hasLoadedContentOnce: appModel.weekStore.hasLoadedOnce,
                    contentErrorMessage: appModel.weekStore.errorMessage
                ) {
                    LoadingPanel(title: L10n.string("week.loading"))
                } else if isFillingViewedWeek, !appModel.weekStore.hasWeekContent {
                    LoadingPanel(title: L10n.string("week.generating"))
                } else if let errorMessage = appModel.weekStore.errorMessage ?? appModel.householdStore.errorMessage {
                    ErrorPanel(message: errorMessage) {
                        Task { await model.reloadViewedWeek(trigger: .pullToRefresh) }
                    }
                } else if !appModel.weekStore.hasWeekContent {
                    if isViewingCurrentWeek {
                        emptyWeekView
                        primaryAssistantMessage
                        secondaryWeekContent
                    } else {
                        tonightHeroCard
                        if isViewingLastWeek {
                            weekList
                            collapsedWeekendSection
                        }
                    }
                } else {
                    tonightHeroCard
                    if !isViewingLastWeek {
                        weekPlanningStatusCard
                    }
                    primaryAssistantMessage
                    weekList
                    collapsedWeekendSection
                    secondaryWeekContent
                }
            }
            .padding(18)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: hasOpenRelevantDays)
        }
        .safeAreaPadding(.bottom, VecklyDesign.Spacing.large)
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
            // Beslut: "Planera resten" lives as the CTA inside
            // `weekPlanningStatusCard`'s content card. "Gör om veckan"
            // (Fas C) moved here, into a menu — it's a rare, destructive
            // action that doesn't belong as a second always-visible CTA next
            // to the status card's primary button. A lone `ToolbarItem`
            // still covers the common case (refresh only) to avoid the
            // ambiguous empty-looking Liquid Glass pill a single-control
            // `ToolbarItemGroup` renders as on iOS 26.
            if appModel.weekStore.generatingWeekStartDate == viewedWeekStartDate {
                ToolbarItem(placement: .topBarTrailing) {
                    ProgressView()
                }
            } else if !isViewingLastWeek, appModel.weekStore.hasWeekContent, !hasOpenRelevantDays {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            guard model.session() != nil else { return }
                            showRegenerateConfirmation = true
                        } label: {
                            Label("week.regenerate", systemImage: "arrow.triangle.2.circlepath")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel(L10n.string("week.moreOptions"))
                    .accessibilityIdentifier("weekMoreOptionsMenu")

                    Button {
                        // An explicit tap always forces a real reload —
                        // this is the Week tab's pull-to-refresh equivalent
                        // (it has no `.refreshable`, since the whole
                        // ScrollView already scrolls the hero/status cards
                        // along with the list).
                        Task { await model.reloadViewedWeek(trigger: .pullToRefresh) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel(L10n.string("common.refresh"))
                }
            } else if !isViewingLastWeek {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await model.reloadViewedWeek(trigger: .pullToRefresh) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel(L10n.string("common.refresh"))
                }
            }
        }
        .sheet(item: $model.sheet) { sheet in
            sheetContent(sheet)
        }
        .task(id: appModel.householdStore.activeHousehold?.id) {
            // Retro + weekend next-week peek, re-run whenever the active
            // household is (re)established — see
            // `WeekScreenModel.activeHouseholdDidChange` for why this can't
            // be left to `onAppear`.
            await model.activeHouseholdDidChange()
        }
        .onAppear {
            // Browsing is a transient peek, not a persisted location — always
            // land back on the current week when the tab reappears, unless a
            // just-tapped "plan next week" notification (see
            // `AppNotificationDelegate`) asked for next week specifically.
            if !model.consumePendingWeekPlanDeepLink() {
                model.viewedWeekOffset = .current
            }
            isWeekendExpanded = false
            model.refreshWeekendNudgeDismissalState()
            Task { await model.reloadViewedWeek() }
            Task { await model.refreshNextWeekEmptyState() }
            Task { await model.consumePendingMealDeepLink() }
        }
        .onChange(of: appModel.pendingDeepLink) { _, destination in
            guard case .meal = destination else { return }
            Task { await model.consumePendingMealDeepLink() }
        }
        .onChange(of: appModel.pendingWeekPlanDeepLink) { _, isPending in
            // Covers the case where the notification tap is delivered to
            // `AppNotificationDelegate` *after* this view already appeared
            // (e.g. the app was merely backgrounded, not relaunched, so
            // `.onAppear` doesn't fire again) — the async delegate callback
            // has no fixed ordering relative to SwiftUI's view lifecycle.
            guard isPending, model.consumePendingWeekPlanDeepLink() else { return }
            Task { await model.reloadViewedWeek() }
        }
        .onChange(of: model.viewedWeekOffset) { _, _ in
            // Drops the undo banner (and fill notices) for the week the user
            // just left — see `WeekScreenModel.viewedWeekDidChange`.
            model.viewedWeekDidChange()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            model.sceneDidBecomeActive()
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
                presentWeekBrief(regenerate: true)
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
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: regenerateUndoContext?.id)
    }

    /// Routes `model.sheet` to its view. Each sheet's own close/dismiss
    /// callbacks go through `model.dismissSheet(sheet.id)`, so they can only
    /// ever close the sheet they belong to.
    @ViewBuilder
    private func sheetContent(_ sheet: WeekSheet) -> some View {
        switch sheet {
        case let .recipe(pair):
            let interaction = weekListPresentation.interaction(for: pair.day)
            let allowsDayMutation = interaction == .editDay
            NavigationStack {
                RecipeDetailView(
                    recipe: pair.recipe,
                    householdID: appModel.householdStore.activeHousehold?.id ?? "",
                    isSkipped: allowsDayMutation ? pair.day.isSkipped : nil,
                    onSkip: allowsDayMutation ? {
                        guard canEditDay(pair.day) else { return }
                        if model.toggleSkip(pair.day) {
                            model.dismissSheet(sheet.id)
                        }
                    } : nil,
                    isReadOnly: !allowsDayMutation
                )
            }
        case let .mealPicker(day):
            MealPickerSheet(
                day: day,
                isSkipped: day.isSkipped,
                coverage: coverage(for: day),
                householdID: appModel.householdStore.activeHousehold?.id ?? "",
                weekStartDate: viewedWeekStartDate,
                onSelect: { recipe in
                    guard canMutateDay(day) else { return }
                    model.assignMeal(day, recipe: WeekSummaryRecipe(fullRecipe: recipe))
                },
                onClear: {
                    guard canMutateDay(day) else { return }
                    if model.unassignMeal(day) {
                        model.dismissSheet(sheet.id)
                    }
                },
                onSkip: {
                    guard canMutateDay(day) else { return }
                    model.toggleSkip(day, checksSessionEnd: true)
                },
                onMarkAsLeftover: { recipeID in
                    guard canMutateDay(day) else { return }
                    model.dismissSheet(sheet.id)
                    model.presentAfterDismiss {
                        .prepBatch(PrepBatchSeed(
                            recipeID: recipeID,
                            cookDate: day.date,
                            weekStartDate: model.viewedWeekStartDate
                        ))
                    }
                },
                onMarkAsLeftoverNoRecipe: {
                    guard canMutateDay(day) else { return }
                    guard let household = appModel.householdStore.activeHousehold else { return }
                    let profile = appModel.householdStore.cachedProfile(for: household.id)
                    model.dismissSheet(sheet.id)
                    model.presentAfterDismiss {
                        .leftoversWithoutRecipe(LeftoversWithoutRecipeSeed(
                            day: day,
                            defaultPortions: LeftoversWithoutRecipeFormModel.defaultPortions(profile: profile)
                        ))
                    }
                },
                onRemoveCoverage: {
                    guard canMutateDay(day) else { return }
                    guard let dayCoverage = coverage(for: day),
                          model.removeCoverage(day, coverage: dayCoverage) else { return }
                    model.dismissSheet(sheet.id)
                },
                onDismiss: { model.dismissSheet(sheet.id) }
            )
        case let .rescue(day):
            if let household = appModel.householdStore.activeHousehold {
                WeekRescueSheet(
                    day: day,
                    household: household,
                    weekStartDate: viewedWeekStartDate,
                    expectedUpdatedAt: appModel.weekStore.summary?.updatedAt,
                    onApplied: {
                        await model.weekPlanChangedElsewhere(household: household)
                    }
                )
            }
        case .previousWeekProposal:
            if let household = appModel.householdStore.activeHousehold {
                PreviousWeekProposalSheet(
                    household: household,
                    weekStartDate: viewedWeekStartDate,
                    expectedUpdatedAt: appModel.weekStore.summary?.updatedAt,
                    onApplied: {
                        await model.weekPlanChangedElsewhere(household: household)
                    },
                    onSwap: { date in
                        model.presentAfterDismiss {
                            appModel.weekStore.dayRows.first(where: { $0.date == date }).map(WeekSheet.mealPicker)
                        }
                    }
                )
            }
        case let .dayDetail(day):
            DayDetailSheet(
                day: day,
                householdID: appModel.householdStore.activeHousehold?.id ?? "",
                onViewRecipe: {
                    model.dismissSheet(sheet.id)
                    model.presentAfterDismiss {
                        day.recipe.map { .recipe(SelectedDayRecipe(day: day, recipe: $0)) }
                    }
                },
                onSwap: {
                    guard canEditDay(day) else { return }
                    model.dismissSheet(sheet.id)
                    model.presentAfterDismiss { .mealPicker(day) }
                },
                onSkip: {
                    guard canEditDay(day) else { return }
                    model.toggleSkip(day)
                },
                onClear: {
                    guard canEditDay(day) else { return }
                    if model.unassignMeal(day) {
                        model.dismissSheet(sheet.id)
                    }
                },
                onMarkAsLeftover: {
                    guard canEditDay(day) else { return }
                    model.dismissSheet(sheet.id)
                    if let recipe = day.recipe {
                        model.presentAfterDismiss {
                            .prepBatch(PrepBatchSeed(
                                recipeID: recipe.id,
                                cookDate: day.date,
                                weekStartDate: model.viewedWeekStartDate
                            ))
                        }
                    }
                },
                isLocked: day.isLocked,
                onToggleLock: {
                    guard canEditDay(day) else { return }
                    guard model.toggleLock(day) else { return }
                    if !hasSeenLockExplanation {
                        showLockExplanation = true
                    }
                },
                onApplyPortionSuggestion: { servings in
                    await model.applyPortionSuggestion(day, servings: servings)
                },
                onIgnorePortionSuggestion: {
                    await model.ignorePortionSuggestion(day)
                },
                onResetPortionMemory: {
                    await model.resetPortionMemory(day)
                },
                onDismiss: { model.dismissSheet(sheet.id) }
            )
        case let .prepBatch(seed):
            PrepBatchFormSheet(
                initialRecipeID: seed.recipeID,
                initialCookDate: WeekCalendar.date(from: seed.cookDate) ?? Date(),
                weekStartDate: seed.weekStartDate,
                initialAssignedDate: seed.assignedDate
            )
        case let .leftoversWithoutRecipe(seed):
            LeftoversWithoutRecipeSheet(
                day: seed.day,
                initialPortions: seed.defaultPortions,
                weekStartDate: viewedWeekStartDate
            )
        case let .weekBrief(presentation):
            if let household = appModel.householdStore.activeHousehold,
               let userID = appModel.authSessionStore.userID {
                WeekBriefSheet(
                    store: model.makeWeekBriefStore(),
                    householdID: household.id,
                    weekStartDate: presentation.weekStartDate,
                    userID: userID,
                    rows: appModel.weekStore.dayRows,
                    profile: appModel.householdStore.cachedProfile(for: household.id),
                    isRegenerating: presentation.regenerate,
                    pantryItems: PantryPlanningItem.suggestions(from: appModel.shoppingListStore.pantryStock),
                    onGenerate: { pantryItemKeys, portionAdjustments in
                        await model.performGenerate(
                            regenerate: presentation.regenerate,
                            weekStartDate: presentation.weekStartDate,
                            pantryItemKeys: pantryItemKeys,
                            portionAdjustments: portionAdjustments
                        )
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var primaryAssistantMessage: some View {
        if showSessionEndBeat, isViewingCurrentWeek {
            sessionEndBeatCard
        } else if let fillCompletionNotice {
            fillCompletionBanner(fillCompletionNotice)
        } else if isViewingCurrentWeek {
            weekendNudgeBanner
        }
    }

    @ViewBuilder
    private var secondaryWeekContent: some View {
        weekQualityCard
        weekExplanationSummary

        if isViewingCurrentWeek, !retroViewModel.rows.isEmpty {
            RetroCard(
                viewModel: retroViewModel,
                outcomeStore: appModel.mealOutcomeStore,
                householdID: appModel.householdStore.activeHousehold?.id ?? "",
                recipes: appModel.recipeStore.recipes,
                onResolved: {
                    model.retroResolved()
                }
            )
        }

        if appModel.weekStore.hasPendingSync && isViewingCurrentWeek {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(weekPendingSyncMessage)
                    .font(.caption)
                    .foregroundStyle(VecklyDesign.Colors.inkMid)
            }
            .padding(.horizontal, 4)
            .accessibilityElement(children: .combine)
        }
    }

    private func checkForSessionEnd(wasEmptyBefore: Bool) {
        model.checkForSessionEnd(wasEmptyBefore: wasEmptyBefore)
    }

    private func presentWeekBrief(regenerate: Bool) {
        model.presentWeekBrief(regenerate: regenerate)
    }

    private func refreshShoppingListAfterWeekMutation(household: Household, weekStartDate: String) async {
        await model.refreshShoppingListAfterWeekMutation(household: household, weekStartDate: weekStartDate)
    }

    private func regenerateUndoBanner(_ context: RegenerateUndoContext) -> some View {
        HStack(spacing: 12) {
            Text("week.regenerate.undoBanner")
                .font(.subheadline)
                .foregroundStyle(.white)
            Spacer()
            Button(L10n.string("common.undo")) {
                model.undoRegenerate(context)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(VecklyDesign.Colors.hearthOrangeTextDark)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(VecklyDesign.Colors.toastSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }

    /// `WeekHeaderView` (Fas 3 extraction) owns the household/week-title/date
    /// chrome and its own week-picker popover; this stays only because
    /// `nextWeekSummaryCard`/`lastWeekSummaryCard` still need the plain
    /// subtitle string for the currently-viewed offset.
    private var weekSubtitleLabel: String {
        viewedWeekOffset.subtitleLabel()
    }

    private var shouldShowWeekendNudge: Bool { model.shouldShowWeekendNudge }
    private var shouldOfferPlanNextWeekFromWeekDone: Bool { model.shouldOfferPlanNextWeekFromWeekDone }

    @ViewBuilder
    private var weekendNudgeBanner: some View {
        if shouldShowWeekendNudge {
            HStack(spacing: 12) {
                Text("week.weekendNudge.title")
                    .font(.subheadline)
                    .foregroundStyle(VecklyDesign.Colors.inkDeep)
                Spacer()
                Button("week.weekendNudge.cta") {
                    model.planNextWeek()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(VecklyDesign.Colors.hearthOrangeText)
                Button {
                    model.dismissWeekendNudgeForToday()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(VecklyDesign.Colors.inkMid)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(L10n.string("common.dismiss"))
            }
            .padding(12)
            .background(VecklyDesign.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
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
                            .font(VecklyDesign.Typography.cardTitle)
                            .foregroundStyle(VecklyDesign.Colors.inkDeep)
                        Spacer()
                        Button {
                            model.dismissSessionEndBeat()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(VecklyDesign.Colors.inkMid)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
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
                                    .foregroundStyle(VecklyDesign.Colors.hearthOrangeFill)
                            }
                        }
                    }
                    .padding(.top, 2)

                    Button("week.sessionEnd.cta") {
                        model.dismissSessionEndBeat()
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
                                model.dismissSessionEndBeat()
                                appModel.recordProductEvent(.partnerInviteClicked, weekStartDate: viewedWeekStartDate)
                                onGoToHouseholdTab?()
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(VecklyDesign.Colors.hearthOrangeText)
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
                        .font(VecklyDesign.Typography.cardTitle)
                        .foregroundStyle(VecklyDesign.Colors.inkDeep)

                    Text("week.empty.message")
                        .font(.body)
                        .foregroundStyle(VecklyDesign.Colors.inkMid)

                    Button("week.empty.chooseFirst") {
                        model.sheet = firstOpenPlanningDay.map(WeekSheet.mealPicker)
                    }
                    .buttonStyle(VecklyPrimaryButtonStyle())
                    .padding(.top, 4)
                    .disabled(firstOpenPlanningDay == nil)

                    Button(fillAction.title) {
                        presentWeekBrief(regenerate: false)
                    }
                    .disabled(appModel.householdStore.activeHousehold == nil || firstOpenPlanningDay == nil)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(VecklyDesign.Colors.hearthOrangeText)
                    .frame(maxWidth: .infinity)

                    Button("previousWeek.action") {
                        model.sheet = .previousWeekProposal
                    }
                    .disabled(appModel.householdStore.activeHousehold == nil)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(VecklyDesign.Colors.inkMid)
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            weekList
            collapsedWeekendSection
        }
    }

    private func coverage(for day: WeekDayRowViewModel) -> PrepBatchCoverage? { model.coverage(for: day) }
    private var hasOpenRelevantDays: Bool { model.hasOpenRelevantDays }
    private var fillAction: WeekFillAction { model.fillAction }
    private var firstOpenPlanningDay: WeekDayRowViewModel? { model.firstOpenPlanningDay }
    private var isFillingViewedWeek: Bool { model.isFillingViewedWeek }

    private var heroMode: TonightMealCardMode { model.heroMode }
    private var todayRowIsHeroOwned: Bool { model.todayRowIsHeroOwned }
    private var weekSessionSummary: WeekSessionSummary { model.weekSessionSummary }
    private var weekPlanningScope: WeekPlanningScope { model.weekPlanningScope }
    private var prepCoveredDates: Set<String> { model.prepCoveredDates }
    private var plannedDinnerCount: Int { model.plannedDinnerCount }

    private var sessionEndSummaryRows: [(icon: String, text: String)] {
        let summary = weekSessionSummary
        var rows: [(icon: String, text: String)] = []
        if summary.quickDinnerCount > 0 {
            rows.append((
                icon: "clock",
                text: L10n.format(summary.quickDinnerCount == 1 ? "week.sessionEnd.quick.one" : "week.sessionEnd.quick.other", summary.quickDinnerCount)
            ))
        }
        if summary.prepFriendlyDinnerCount > 0 {
            rows.append((
                icon: "takeoutbag.and.cup.and.straw",
                text: L10n.format(summary.prepFriendlyDinnerCount == 1 ? "week.sessionEnd.prep.one" : "week.sessionEnd.prep.other", summary.prepFriendlyDinnerCount)
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

    private var openDayCount: Int { model.openDayCount }

    private var weekSummaryLine: String {
        let dinnerCount = plannedDinnerCount
        let dayCount = openDayCount
        let dinnersPart = L10n.format(dinnerCount == 1 ? "week.summary.plannedDinners.one" : "week.summary.plannedDinners.other", dinnerCount)
        let daysPart = L10n.format(dayCount == 1 ? "week.summary.openDays.one" : "week.summary.openDays.other", dayCount)
        return "\(dinnersPart) · \(daysPart)"
    }

    private var visibleQualitySuggestion: WeekQualitySuggestion? { model.visibleQualitySuggestion }

    @ViewBuilder
    private var weekQualityCard: some View {
        if !isViewingLastWeek, let suggestion = visibleQualitySuggestion {
            VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("week.quality.suggestion.title")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(VecklyDesign.Colors.inkFaint)
                            .textCase(.uppercase)
                        Spacer()
                        Button {
                            model.dismissQualitySuggestionsForViewedWeek()
                        } label: {
                            Image(systemName: "xmark")
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.string("week.quality.suggestion.dismiss"))
                    }

                    Label(qualitySuggestionReason(suggestion), systemImage: qualitySuggestionIcon(suggestion))
                        .font(.subheadline)
                        .foregroundStyle(VecklyDesign.Colors.inkMid)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(qualitySuggestionBefore(suggestion))
                            .font(.subheadline)
                            .foregroundStyle(VecklyDesign.Colors.inkFaint)
                        Label(qualitySuggestionAfter(suggestion), systemImage: "arrow.down")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(VecklyDesign.Colors.inkDeep)
                    }

                    Button(qualitySuggestionActionTitle(suggestion)) {
                        showQualitySuggestionConfirmation = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(VecklyDesign.Colors.hearthOrangePrimaryFill)
                    .accessibilityIdentifier("weekQualitySuggestionAction")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .confirmationDialog(
                L10n.string("week.quality.suggestion.confirmTitle"),
                isPresented: $showQualitySuggestionConfirmation,
                titleVisibility: .visible
            ) {
                Button(qualitySuggestionConfirmTitle(suggestion)) {
                    model.applyQualitySuggestion(suggestion)
                }
                Button(L10n.string("common.cancel"), role: .cancel) {}
            } message: {
                Text("\(qualitySuggestionBefore(suggestion))\n\(qualitySuggestionAfter(suggestion))")
            }
        }
    }

    @ViewBuilder
    private var weekExplanationSummary: some View {
        if appModel.weekStore.summary?.weekStartDate == viewedWeekStartDate,
           let summary = appModel.weekStore.summary,
           !summary.explanations.isEmpty || !(summary.pulse?.wishes.isEmpty ?? true) {
            VStack(alignment: .leading, spacing: 8) {
                Label("week.explanation.title", systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VecklyDesign.Colors.inkFaint)
                    .textCase(.uppercase)

                ForEach(Array(summary.explanations.prefix(2).enumerated()), id: \.offset) { _, explanation in
                    Text(explanation.sentence)
                        .font(.subheadline)
                        .foregroundStyle(VecklyDesign.Colors.inkMid)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(summary.pulse?.wishes ?? []) { wish in
                    Text(wish.sentence)
                        .font(.subheadline)
                        .foregroundStyle(VecklyDesign.Colors.inkMid)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .accessibilityElement(children: .combine)
        }
    }

    private func qualitySuggestionIcon(_ suggestion: WeekQualitySuggestion) -> String {
        switch suggestion.kind {
        case .fillOpenDay: "calendar.badge.plus"
        case .useLeftovers: "arrow.3.trianglepath"
        case .makeQuicker: "clock.arrow.circlepath"
        case .makeEasier: "basket"
        case .addVariation: "arrow.2.squarepath"
        }
    }

    private func qualitySuggestionReason(_ suggestion: WeekQualitySuggestion) -> String {
        switch suggestion.kind {
        case .fillOpenDay:
            L10n.format("week.quality.suggestion.reason.open", suggestion.day.weekdayLabel)
        case .useLeftovers:
            L10n.format("week.quality.suggestion.reason.leftovers", suggestion.day.weekdayLabel)
        case .makeQuicker:
            L10n.format("week.quality.suggestion.reason.quicker", suggestion.day.weekdayLabel)
        case .makeEasier:
            L10n.format("week.quality.suggestion.reason.easier", suggestion.day.weekdayLabel)
        case .addVariation:
            L10n.format("week.quality.suggestion.reason.variation", suggestion.day.weekdayLabel)
        }
    }

    private func qualitySuggestionBefore(_ suggestion: WeekQualitySuggestion) -> String {
        let meal = suggestion.day.recipe?.title ?? L10n.string("week.quality.suggestion.openDay")
        return L10n.format("week.quality.suggestion.before", suggestion.day.weekdayLabel, meal)
    }

    private func qualitySuggestionAfter(_ suggestion: WeekQualitySuggestion) -> String {
        if suggestion.kind == .useLeftovers, let source = suggestion.sourceDay, let recipe = source.recipe {
            return L10n.format("week.quality.suggestion.afterLeftovers", recipe.title, source.weekdayLabel)
        }
        return L10n.format(
            "week.quality.suggestion.after",
            suggestion.replacement?.title ?? L10n.string("week.quality.suggestion.openDay")
        )
    }

    private func qualitySuggestionActionTitle(_ suggestion: WeekQualitySuggestion) -> LocalizedStringKey {
        suggestion.kind == .useLeftovers
            ? "week.quality.suggestion.reviewLeftovers"
            : "week.quality.suggestion.reviewSwap"
    }

    private func qualitySuggestionConfirmTitle(_ suggestion: WeekQualitySuggestion) -> String {
        suggestion.kind == .useLeftovers
            ? L10n.string("week.quality.suggestion.confirmLeftovers")
            : L10n.string("week.quality.suggestion.confirmSwap")
    }

    /// Replaces "Veckokoll" as the primary status surface (Fas 3): a single
    /// primary CTA reflecting whether relevant planning days remain.
    @ViewBuilder
    private var weekPlanningStatusCard: some View {
        if appModel.weekStore.hasWeekContent {
            WeekPlanningStatusCard(
                openDayCount: openDayCount,
                isComplete: !hasOpenRelevantDays,
                fillActionTitle: fillAction.title,
                fillProgressTitle: fillAction.progressTitle,
                isFilling: isFillingViewedWeek,
                onPlanRest: {
                    presentWeekBrief(regenerate: false)
                },
                onOpenShoppingList: {
                    onGoToShoppingTab?()
                }
            )
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
                    model.sheet = .recipe(SelectedDayRecipe(day: day, recipe: recipe))
                }
            },
            onSwap: { day in
                guard canMutateDay(day) else { return }
                model.sheet = .mealPicker(day)
            },
            onRescue: { day in
                guard canMutateDay(day), !day.isLocked else { return }
                model.sheet = .rescue(day)
            },
            onPlanTonight: { day in
                guard canMutateDay(day) else { return }
                model.sheet = .mealPicker(day)
            },
            onEatExtra: { day in
                guard canMutateDay(day) else { return }
                if let recipe = day.recipe {
                    model.sheet = .prepBatch(PrepBatchSeed(
                        recipeID: recipe.id,
                        cookDate: day.date,
                        weekStartDate: viewedWeekStartDate
                    ))
                }
            },
            onRemoveCoverage: { day, dayCoverage in
                guard canMutateDay(day) else { return }
                model.removeCoverage(day, coverage: dayCoverage)
            },
            onPlanNextWeek: shouldOfferPlanNextWeekFromWeekDone ? {
                model.planNextWeek()
            } : nil
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
                        .font(VecklyDesign.Typography.cardTitle)
                        .foregroundStyle(VecklyDesign.Colors.inkDeep)

                    Text("week.nextWeek.empty.message")
                        .font(.body)
                        .foregroundStyle(VecklyDesign.Colors.inkMid)

                    Button("week.empty.chooseFirst") {
                        model.sheet = firstOpenPlanningDay.map(WeekSheet.mealPicker)
                    }
                    .buttonStyle(VecklyPrimaryButtonStyle())
                    .padding(.top, 4)
                    .disabled(firstOpenPlanningDay == nil)

                    Button(fillAction.title) {
                        presentWeekBrief(regenerate: false)
                    }
                    .disabled(appModel.householdStore.activeHousehold == nil || firstOpenPlanningDay == nil)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(VecklyDesign.Colors.hearthOrangeText)
                    .frame(maxWidth: .infinity)

                    Button("previousWeek.action") {
                        model.sheet = .previousWeekProposal
                    }
                    .disabled(appModel.householdStore.activeHousehold == nil)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(VecklyDesign.Colors.inkMid)
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            weekList
            collapsedWeekendSection
        }
    }

    private func fillCompletionBanner(_ notice: WeekFillCompletionNotice) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("week.fill.success", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(VecklyDesign.Colors.inkDeep)

            Text(notice.reason)
                .font(.subheadline)
                .foregroundStyle(VecklyDesign.Colors.inkMid)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(VecklyDesign.Colors.surfaceStrong)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("weekFillCompletion")
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
                    .font(VecklyDesign.Typography.cardTitle)
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
                    .foregroundStyle(VecklyDesign.Colors.hearthOrangeText)
                    .textCase(.uppercase)
                Text(weekSummaryLine)
                    .font(VecklyDesign.Typography.cardTitle)
                    .foregroundStyle(VecklyDesign.Colors.inkDeep)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Saturday/Sunday rows — only relevant when deciding whether to collapse
    /// them (beslut 8); a household that plans the weekend never collapses it.
    private var weekendDays: [WeekDayRowViewModel] {
        weekListPresentation.weekendDays
    }

    /// Beslut 8: only households that never plan Sat/Sun get a collapsed
    /// weekend section. A household with the weekend in `selectedDays` sees
    /// it as regular rows in `listDays`, counted in scope like any other day.
    private var shouldCollapseWeekend: Bool {
        weekListPresentation.shouldCollapseWeekend
    }

    /// The week list always shows every relevant day, in order, with no
    /// holes (beslut 3) — weekend days are the one exception, moved to
    /// `collapsedWeekendSection` when the household doesn't plan them.
    private var listDays: [WeekDayRowViewModel] {
        weekListPresentation.mainDays
    }

    private var weekListPresentation: WeekListPresentation { model.weekListPresentation }
    private func canEditDay(_ day: WeekDayRowViewModel) -> Bool { model.canEditDay(day) }
    private func canMutateDay(_ day: WeekDayRowViewModel) -> Bool { model.canMutateDay(day) }

    /// Shared tap handling for both the main list and the collapsed weekend
    /// section — a day already owned by the hero (today, when the hero is
    /// showing today) has no tap target of its own (beslut 3); the hero
    /// itself carries the actions.
    private func handleDayTap(_ day: WeekDayRowViewModel) {
        if isViewingCurrentWeek, day.isToday, todayRowIsHeroOwned { return }
        switch weekListPresentation.interaction(for: day) {
        case .none:
            break
        case .viewRecipe:
            if let recipe = day.recipe {
                model.sheet = .recipe(SelectedDayRecipe(day: day, recipe: recipe))
            }
        case .editDay:
            model.sheet = .dayDetail(day)
        case .planDay:
            model.sheet = .mealPicker(day)
        }
    }

    private func dayRow(_ day: WeekDayRowViewModel) -> some View {
        CompactDayRow(
            day: day,
            coverage: coverage(for: day),
            isTodayBadge: day.isToday,
            isHeroOwned: isViewingCurrentWeek && day.isToday && todayRowIsHeroOwned,
            interaction: weekListPresentation.interaction(for: day),
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
                            .foregroundStyle(VecklyDesign.Colors.hearthOrangeText)
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(VecklyDesign.Colors.hearthOrangeFill)
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
    var interaction: WeekDayRowInteraction = .editDay
    let onTap: () -> Void

    var body: some View {
        Group {
            if isHeroOwned || interaction == .none {
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
            .foregroundStyle(VecklyDesign.Colors.hearthOrangeText)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(Capsule().stroke(VecklyDesign.Colors.hearthOrangeText, lineWidth: 1))
            .fixedSize()
    }

    private var dateColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(day.weekday.shortDisplayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(day.isToday ? VecklyDesign.Colors.hearthOrangeText : VecklyDesign.Colors.inkMid)
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
                    .foregroundStyle(VecklyDesign.Colors.hearthOrangeFill)
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
            if interaction == .planDay && !isHeroOwned {
                Text("meal.plan")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(VecklyDesign.Colors.hearthOrangeText)
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
            if interaction == .editDay && !isHeroOwned {
                Text("meal.plan")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(VecklyDesign.Colors.hearthOrangeText)
            }
        }
        .opacity(0.7)
    }
}

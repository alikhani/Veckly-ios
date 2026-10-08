import SwiftUI

struct WeekTabView: View {
    @Environment(AppModel.self) var appModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State var model: WeekScreenModel
    var onGoToShoppingTab: (() -> Void)? = nil
    var onGoToHouseholdTab: (() -> Void)? = nil
    @State private var isWeekPickerPresented = false
    // Not `private`: read by the sheet routing in `WeekTabView+Sheets.swift`.
    @AppStorage("hasSeenLockExplanation") var hasSeenLockExplanation = false
    @State var showLockExplanation = false
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let err = appModel.weekStore.mutationError {
                    DismissibleErrorBanner(
                        message: err,
                        retry: model.failedFillWeekStartDate == model.viewedWeekStartDate
                            ? { model.presentWeekBrief(regenerate: false) }
                            : nil,
                        dismiss: { model.dismissWeekMutationError() }
                    )
                }

                if let err = appModel.prepBatchStore.mutationError {
                    DismissibleErrorBanner(
                        message: err,
                        dismiss: { appModel.prepBatchStore.clearMutationError() }
                    )
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
                    contentErrorMessage: appModel.weekStore.errorMessage,
                    hasRestoredContent: showsRestoredWeek
                ) {
                    LoadingPanel(title: L10n.string("week.loading"))
                } else if model.isFillingViewedWeek, !appModel.weekStore.hasWeekContent {
                    LoadingPanel(title: L10n.string("week.generating"))
                } else if let errorMessage = CoreLoadingGate.blockingErrorMessage(
                    contentError: appModel.weekStore.errorMessage,
                    householdError: appModel.householdStore.errorMessage,
                    hasRestoredContent: showsRestoredWeek
                ) {
                    ErrorPanel(message: errorMessage) {
                        Task { await model.reloadViewedWeek(trigger: .pullToRefresh) }
                    }
                } else if !appModel.weekStore.hasWeekContent {
                    if model.isViewingCurrentWeek {
                        emptyWeekView
                        primaryAssistantMessage
                        secondaryWeekContent
                    } else {
                        tonightHeroCard
                        if model.isViewingLastWeek {
                            weekList
                            collapsedWeekendSection
                        }
                    }
                } else {
                    tonightHeroCard
                    if !model.isViewingLastWeek {
                        weekPlanningStatusCard
                    }
                    primaryAssistantMessage
                    weekList
                    collapsedWeekendSection
                    secondaryWeekContent
                }
            }
            .padding(18)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: model.hasOpenRelevantDays)
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
            WeekToolbar(
                mode: toolbarMode,
                onRegenerate: {
                    guard model.session() != nil else { return }
                    showRegenerateConfirmation = true
                },
                onRefresh: {
                    Task { await model.reloadViewedWeek(trigger: .pullToRefresh) }
                }
            )
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
                model.presentWeekBrief(regenerate: true)
            }
            Button(L10n.string("common.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.string("week.regenerateConfirm.message"))
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 8) {
                if appModel.weekStore.hasPendingUpdate(for: model.viewedWeekStartDate) {
                    // An overlay with a fade only: it never moves the content
                    // under the user's finger.
                    UpdateAvailableBanner(onShow: { model.showPendingUpdate() })
                        .transition(.opacity)
                }
                if let regenerateUndoContext = model.regenerateUndo {
                    WeekRegenerateUndoBanner(onUndo: { model.undoRegenerate(regenerateUndoContext) })
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 12)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.regenerateUndo?.id)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: appModel.weekStore.hasPendingUpdate(for: model.viewedWeekStartDate))
    }

    /// The viewed week is on screen from the disk cache and the network hasn't
    /// answered for it yet.
    private var showsRestoredWeek: Bool {
        appModel.weekStore.isShowingRestoredWeek(model.viewedWeekStartDate)
    }

    private var toolbarMode: WeekToolbar.Mode {
        if appModel.weekStore.generatingWeekStartDate == model.viewedWeekStartDate {
            .generating
        } else if !model.isViewingLastWeek, appModel.weekStore.hasWeekContent, !model.hasOpenRelevantDays {
            .regenerateAndRefresh
        } else if !model.isViewingLastWeek {
            .refresh
        } else {
            .none
        }
    }

    // MARK: Sections
    //
    // Each wrapper keeps the exact conditional structure the screen always
    // had; the content itself lives in the section views
    // (`WeekHeroCards`, `WeekBanners`, `WeekQualityCard`, `WeekDayList`),
    // which take plain values and closures.

    @ViewBuilder
    private var primaryAssistantMessage: some View {
        if model.showSessionEndBeat, model.isViewingCurrentWeek {
            sessionEndBeatCard
        } else if let fillCompletionNotice = model.fillCompletionNotice {
            WeekFillCompletionBanner(notice: fillCompletionNotice)
        } else if model.isViewingCurrentWeek {
            weekendNudgeBanner
        }
    }

    @ViewBuilder
    private var secondaryWeekContent: some View {
        weekQualityCard
        weekExplanationSummary

        if model.isViewingCurrentWeek, !model.retro.rows.isEmpty {
            RetroCard(
                viewModel: model.retro,
                outcomeStore: appModel.mealOutcomeStore,
                householdID: appModel.householdStore.activeHousehold?.id ?? "",
                recipes: appModel.recipeStore.recipes,
                onResolved: {
                    model.retroResolved()
                }
            )
        }

        if appModel.weekStore.hasPendingSync && model.isViewingCurrentWeek {
            WeekPendingSyncNote()
        }
    }

    @ViewBuilder
    private var weekendNudgeBanner: some View {
        if model.shouldShowWeekendNudge {
            WeekendNudgeBanner(
                onPlanNextWeek: { model.planNextWeek() },
                onDismiss: { model.dismissWeekendNudgeForToday() }
            )
        }
    }

    @ViewBuilder
    private var sessionEndBeatCard: some View {
        if model.showSessionEndBeat, model.isViewingCurrentWeek {
            WeekSessionEndCard(
                summary: model.weekSessionSummary,
                showsInviteNudge: SessionEndInviteNudgeEligibility.shouldShow(
                    activeHousehold: appModel.householdStore.activeHousehold,
                    detailsHouseholdID: appModel.householdStore.detailsHouseholdID,
                    memberCount: appModel.householdStore.members.count
                ),
                onDismiss: { model.dismissSessionEndBeat() },
                onOpenShoppingList: {
                    model.dismissSessionEndBeat()
                    appModel.recordProductEvent(.shoppingOpenedAfterWeekCompleted, weekStartDate: model.viewedWeekStartDate)
                    onGoToShoppingTab?()
                },
                onInvitePartner: {
                    model.dismissSessionEndBeat()
                    appModel.recordProductEvent(.partnerInviteClicked, weekStartDate: model.viewedWeekStartDate)
                    onGoToHouseholdTab?()
                }
            )
        }
    }

    private var emptyWeekView: some View {
        emptyWeekSection(eyebrow: "week.empty.eyebrow", title: "week.empty.title", message: "week.empty.message")
    }

    /// Next week, nothing planned yet: forward-looking copy + a CTA to
    /// generate it now, instead of "Tonight" framing that doesn't apply.
    /// Mirrors emptyWeekView's structure (eyebrow/title/message/CTAs + day
    /// list) so browsing ahead previews the week's structure, not just a CTA.
    private var nextWeekHeroCard: some View {
        emptyWeekSection(eyebrow: "week.nextWeek.empty.eyebrow", title: "week.nextWeek.empty.title", message: "week.nextWeek.empty.message")
    }

    private func emptyWeekSection(eyebrow: LocalizedStringKey, title: LocalizedStringKey, message: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            emptyStateCard(eyebrow: eyebrow, title: title, message: message)
            weekList
            collapsedWeekendSection
        }
    }

    private func emptyStateCard(eyebrow: LocalizedStringKey, title: LocalizedStringKey, message: LocalizedStringKey) -> some View {
        let firstOpenPlanningDay = model.firstOpenPlanningDay
        let hasHousehold = appModel.householdStore.activeHousehold != nil
        return WeekEmptyStateCard(
            eyebrow: eyebrow,
            title: title,
            message: message,
            fillActionTitle: model.fillAction.title,
            canChooseFirstDinner: firstOpenPlanningDay != nil,
            canFill: hasHousehold && firstOpenPlanningDay != nil,
            canStartFromLastWeek: hasHousehold,
            onChooseFirstDinner: { model.sheet = model.firstOpenPlanningDay.map(WeekSheet.mealPicker) },
            onFill: { model.presentWeekBrief(regenerate: false) },
            onStartFromLastWeek: { model.sheet = .previousWeekProposal }
        )
    }

    @ViewBuilder
    private var weekQualityCard: some View {
        if !model.isViewingLastWeek, let suggestion = model.visibleQualitySuggestion {
            WeekQualityCard(
                suggestion: suggestion,
                isConfirming: $showQualitySuggestionConfirmation,
                onDismiss: { model.dismissQualitySuggestionsForViewedWeek() },
                onConfirm: { model.applyQualitySuggestion(suggestion) }
            )
        }
    }

    @ViewBuilder
    private var weekExplanationSummary: some View {
        if appModel.weekStore.summary?.weekStartDate == model.viewedWeekStartDate,
           let summary = appModel.weekStore.summary,
           !summary.explanations.isEmpty || !(summary.pulse?.wishes.isEmpty ?? true) {
            WeekExplanationSummary(summary: summary)
        }
    }

    /// Replaces "Veckokoll" as the primary status surface (Fas 3): a single
    /// primary CTA reflecting whether relevant planning days remain.
    @ViewBuilder
    private var weekPlanningStatusCard: some View {
        if appModel.weekStore.hasWeekContent {
            WeekPlanningStatusCard(
                openDayCount: model.openDayCount,
                isComplete: !model.hasOpenRelevantDays,
                fillActionTitle: model.fillAction.title,
                fillProgressTitle: model.fillAction.progressTitle,
                isFilling: model.isFillingViewedWeek,
                onPlanRest: {
                    model.presentWeekBrief(regenerate: false)
                },
                onOpenShoppingList: {
                    onGoToShoppingTab?()
                }
            )
        }
    }

    @ViewBuilder
    private var tonightHeroCard: some View {
        switch model.viewedWeekOffset {
        case .current:
            currentWeekHeroCard
        case .next:
            if appModel.weekStore.hasWeekContent {
                // Next week already has a plan: date range + dinner count.
                // No Generate CTA — the toolbar stays available if needed.
                WeekSummaryCard(
                    eyebrow: model.viewedWeekOffset.subtitleLabel(),
                    eyebrowColor: VecklyDesign.Colors.inkFaint,
                    summaryLine: weekSummaryLine
                )
            } else {
                nextWeekHeroCard
            }
        case .last:
            // Last week is view-only — no actions.
            WeekSummaryCard(
                eyebrow: L10n.string(model.viewedWeekOffset.relativeLabelKey),
                eyebrowColor: VecklyDesign.Colors.hearthOrangeText,
                summaryLine: weekSummaryLine
            )
        }
    }

    private var weekSummaryLine: String {
        let dinnerCount = model.plannedDinnerCount
        let dayCount = model.openDayCount
        let dinnersPart = L10n.format(dinnerCount == 1 ? "week.summary.plannedDinners.one" : "week.summary.plannedDinners.other", dinnerCount)
        let daysPart = L10n.format(dayCount == 1 ? "week.summary.openDays.one" : "week.summary.openDays.other", dayCount)
        return "\(dinnersPart) · \(daysPart)"
    }

    /// Beslut 16's four hero states, rendered by `TonightMealCard`. Lock
    /// lives in `DayDetailSheet` and the list's status icon now, not here
    /// (beslut 3).
    private var currentWeekHeroCard: some View {
        TonightMealCard(
            mode: model.heroMode,
            coverage: { model.coverage(for: $0) },
            onViewRecipe: { model.viewRecipe($0) },
            onSwap: { model.pickMeal(for: $0) },
            onRescue: { model.rescue($0) },
            onPlanTonight: { model.pickMeal(for: $0) },
            onEatExtra: { model.cookExtra($0) },
            onRemoveCoverage: { day, dayCoverage in
                guard model.canMutateDay(day) else { return }
                model.removeCoverage(day, coverage: dayCoverage)
            },
            onPlanNextWeek: model.shouldOfferPlanNextWeekFromWeekDone ? {
                model.planNextWeek()
            } : nil
        )
    }

    private var weekList: some View {
        WeekDayList(days: model.weekListPresentation.mainDays, row: dayRow)
    }

    /// Beslut 8: only households that never plan Sat/Sun get a collapsed
    /// weekend section. A household with the weekend in `selectedDays` sees
    /// it as regular rows in the main list, counted in scope like any other day.
    @ViewBuilder
    private var collapsedWeekendSection: some View {
        if model.weekListPresentation.shouldCollapseWeekend {
            WeekCollapsedWeekendSection(
                days: model.weekListPresentation.weekendDays,
                isExpanded: $isWeekendExpanded,
                row: dayRow
            )
        }
    }

    private func dayRow(_ day: WeekDayRowViewModel) -> CompactDayRow {
        let isHeroOwned = model.isViewingCurrentWeek && day.isToday && model.todayRowIsHeroOwned
        return CompactDayRow(
            day: day,
            coverage: model.coverage(for: day),
            isTodayBadge: day.isToday,
            isHeroOwned: isHeroOwned,
            interaction: model.weekListPresentation.interaction(for: day),
            onTap: { model.openDay(day) }
        )
    }
}

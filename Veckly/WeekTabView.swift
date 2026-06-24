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
    @State private var selectedDayRecipe: SelectedDayRecipe?
    @State private var mealPickerDay: WeekDayRowViewModel?
    @State private var selectedDayForDetail: WeekDayRowViewModel?
    @State private var prepBatchSeed: PrepBatchSeed?
    @State private var viewedWeekOffset: ViewedWeekOffset = .current
    @State private var isWeekPickerPresented = false
    @State private var weekendNudgeDismissedToday = false
    @State private var nextWeekIsEmpty: Bool?

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

                if appModel.weekStore.hasPendingSync {
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
                } else if appModel.weekStore.isGenerating {
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
                if appModel.weekStore.isGenerating {
                    ProgressView()
                } else if !isViewingLastWeek {
                    Button {
                        guard let household = appModel.householdStore.activeHousehold else { return }
                        guard let userID = appModel.authSessionStore.userID else {
                            Task { await appModel.handleUnauthorized() }
                            return
                        }
                        let regenerate = !appModel.weekStore.hasEmptyDays
                        Task {
                            await appModel.weekStore.generateWeek(
                                household: household,
                                userID: userID,
                                regenerate: regenerate,
                                viewedWeekStartDate: viewedWeekStartDate
                            )
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
                        Task { await appModel.weekStore.assignMeal(day: day, recipe: recipe.asWeekSummaryRecipe, household: household, userID: userID, viewedWeekStartDate: viewedWeekStartDate) }
                    } else {
                        Task { await appModel.handleUnauthorized() }
                    }
                },
                onClear: {
                    guard let household = appModel.householdStore.activeHousehold else { return }
                    if let userID = appModel.authSessionStore.userID {
                        mealPickerDay = nil
                        Task { await appModel.weekStore.unassignMeal(day: day, household: household, userID: userID, viewedWeekStartDate: viewedWeekStartDate) }
                    } else {
                        Task { await appModel.handleUnauthorized() }
                    }
                },
                onSkip: {
                    guard let household = appModel.householdStore.activeHousehold else { return }
                    if let userID = appModel.authSessionStore.userID {
                        Task { await appModel.weekStore.toggleSkip(day: day, household: household, userID: userID, viewedWeekStartDate: viewedWeekStartDate) }
                    } else {
                        Task { await appModel.handleUnauthorized() }
                    }
                },
                onMarkAsLeftover: { recipeID in
                    mealPickerDay = nil
                    Task {
                        try? await Task.sleep(for: .milliseconds(50))
                        prepBatchSeed = PrepBatchSeed(recipeID: recipeID, cookDate: day.date)
                    }
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
                    Task {
                        try? await Task.sleep(for: .milliseconds(50))
                        if let recipe = day.recipe {
                            selectedDayRecipe = SelectedDayRecipe(day: day, recipe: recipe)
                        }
                    }
                },
                onSwap: {
                    selectedDayForDetail = nil
                    Task {
                        try? await Task.sleep(for: .milliseconds(50))
                        mealPickerDay = day
                    }
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
                        Task { await appModel.weekStore.unassignMeal(day: day, household: household, userID: userID, viewedWeekStartDate: viewedWeekStartDate) }
                    } else {
                        Task { await appModel.handleUnauthorized() }
                    }
                },
                onMarkAsLeftover: {
                    selectedDayForDetail = nil
                    if let recipe = day.recipe {
                        Task {
                            try? await Task.sleep(for: .milliseconds(50))
                            prepBatchSeed = PrepBatchSeed(recipeID: recipe.id, cookDate: day.date)
                        }
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
            _ = await (week, prep)
            await refreshNextWeekEmptyState()
        }
        .onAppear {
            // Browsing is a transient peek, not a persisted location — always
            // land back on the current week when the tab reappears.
            viewedWeekOffset = .current
            refreshWeekendNudgeDismissalState()
            Task { await refreshNextWeekEmptyState() }
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
                }
            }
        }
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
                .accessibilityLabel(L10n.string("common.dismissError"))
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
                        guard let household = appModel.householdStore.activeHousehold else { return }
                        guard let userID = appModel.authSessionStore.userID else {
                            Task { await appModel.handleUnauthorized() }
                            return
                        }
                        Task {
                            await appModel.weekStore.generateWeek(
                                household: household,
                                userID: userID,
                                regenerate: false
                            )
                        }
                    }
                    .buttonStyle(VecklyPrimaryButtonStyle())
                    .padding(.top, 4)
                    .disabled(appModel.householdStore.activeHousehold == nil)

                    Button("week.empty.secondary") {
                        mealPickerDay = appModel.weekStore.dayRows.first(where: { $0.isToday })
                            ?? appModel.weekStore.dayRows.first
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

    /// Whether leftovers from a prep batch cover this day's dinner — checked
    /// in the view layer so `WeekStore`/`PrepBatchStore` stay decoupled.
    private func coverage(for day: WeekDayRowViewModel) -> PrepBatchCoverage? {
        prepBatchCoverage(for: day.date, batches: appModel.prepBatchStore.batches, recipes: appModel.recipeStore.recipes)
    }

    private func isDayConsideredPlanned(_ day: WeekDayRowViewModel) -> Bool {
        day.recipe != nil || coverage(for: day) != nil
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
        return rows.first(where: { isDayConsideredPlanned($0) })
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
        appModel.weekStore.dayRows.filter { $0.recipe != nil }.count
    }

    private var openDayCount: Int {
        appModel.weekStore.dayRows.filter { $0.recipe == nil && !$0.isSkipped }.count
    }

    private var weekSummaryLine: String {
        let dinnerCount = plannedDinnerCount
        let dayCount = openDayCount
        let dinnersPart = L10n.format(dinnerCount == 1 ? "week.summary.plannedDinners.one" : "week.summary.plannedDinners.other", dinnerCount)
        let daysPart = L10n.format(dayCount == 1 ? "week.summary.openDays.one" : "week.summary.openDays.other", dayCount)
        return "\(dinnersPart) · \(daysPart)"
    }

    @ViewBuilder
    private var tonightHeroCard: some View {
        switch viewedWeekOffset {
        case .current:
            currentWeekHeroCard
        case .next:
            nextWeekHeroCard
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

                    HStack(spacing: 10) {
                        if dayCoverage == nil {
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
                                    Image(systemName: "arrow.3.trianglepath")
                                        .frame(width: 20, height: 20)
                                }
                                .buttonStyle(.bordered)
                                .tint(VecklyDesign.Colors.inkMid)
                                .accessibilityLabel(L10n.string("prep.eatAgain"))
                            }
                        }

                        if let dayCoverage {
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

                        Button {
                            guard let household = appModel.householdStore.activeHousehold else { return }
                            guard let userID = appModel.authSessionStore.userID else {
                                Task { await appModel.handleUnauthorized() }
                                return
                            }
                            appModel.weekStore.clearMutationError()
                            Task { await appModel.weekStore.toggleLock(day: day, household: household, userID: userID) }
                        } label: {
                            Image(systemName: day.isLocked ? "lock.fill" : "lock.open")
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.bordered)
                        .tint(day.isLocked ? VecklyDesign.Colors.hearthOrange : VecklyDesign.Colors.inkMid)
                        .accessibilityLabel(day.isLocked ? L10n.format("accessibility.unlock", day.weekdayLabel) : L10n.format("accessibility.lock", day.weekdayLabel))
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
                        guard let household = appModel.householdStore.activeHousehold else { return }
                        guard let userID = appModel.authSessionStore.userID else {
                            Task { await appModel.handleUnauthorized() }
                            return
                        }
                        Task {
                            await appModel.weekStore.generateWeek(
                                household: household,
                                userID: userID,
                                regenerate: false,
                                viewedWeekStartDate: viewedWeekStartDate
                            )
                        }
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
        guard isViewingCurrentWeek, let heroId = tonightHeroDay?.id else {
            return appModel.weekStore.dayRows
        }
        return appModel.weekStore.dayRows.filter { $0.id != heroId }
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
                    isViewOnly: isViewingLastWeek,
                    onTap: {
                        if isViewingLastWeek {
                            if let recipe = day.recipe { selectedDayRecipe = SelectedDayRecipe(day: day, recipe: recipe) }
                            return
                        }
                        if day.recipe != nil { selectedDayForDetail = day }
                        else { mealPickerDay = day }
                    },
                    onToggleSkip: {
                        guard let household = appModel.householdStore.activeHousehold else { return }
                        if let userID = appModel.authSessionStore.userID {
                            appModel.weekStore.clearMutationError()
                            Task { await appModel.weekStore.toggleSkip(day: day, household: household, userID: userID, viewedWeekStartDate: viewedWeekStartDate) }
                        } else {
                            Task { await appModel.handleUnauthorized() }
                        }
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
        if isViewingCurrentWeek {
            return tonightHeroDay == nil ? "week.section" : "week.rest"
        }
        return "week.section"
    }
}

struct CompactDayRow: View {
    let day: WeekDayRowViewModel
    var coverage: PrepBatchCoverage? = nil
    var isViewOnly: Bool = false
    let onTap: () -> Void
    let onToggleSkip: () -> Void

    var body: some View {
        Button(action: onTap) {
            rowContent
        }
        .buttonStyle(.plain)
        .opacity(day.isPast ? 0.45 : 1)
        .modifier(SwipeSkipModifier(day: day, isViewOnly: isViewOnly, onToggleSkip: onToggleSkip))
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
            Text(day.mealTitle)
                .font(.body.weight(.medium))
                .foregroundStyle(VecklyDesign.Colors.inkDeep)
                .lineLimit(1)
            Spacer()
            if coverage != nil {
                Image(systemName: "arrow.3.trianglepath")
                    .font(.system(size: 12))
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

    private var skippedContent: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("meal.skipped")
                .font(.body)
                .foregroundStyle(VecklyDesign.Colors.inkFaint)
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

/// Attaches a swipe-to-skip action only when the day is not in the past and
/// the row isn't in a view-only week (Last week — no planning actions at all).
/// The condition is resolved outside the swipeActions ViewBuilder so SwiftUI
/// never receives a conditionally-empty modifier body, which can leave a ghost
/// swipe handle on some versions of UIKit.
private struct SwipeSkipModifier: ViewModifier {
    let day: WeekDayRowViewModel
    var isViewOnly: Bool = false
    let onToggleSkip: () -> Void

    func body(content: Content) -> some View {
        if day.isPast || isViewOnly {
            content
        } else {
            content
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(action: onToggleSkip) {
                        Label(
                            day.isSkipped ? L10n.string("meal.plan") : L10n.string("meal.skip"),
                            systemImage: day.isSkipped ? "calendar.badge.plus" : "calendar.badge.minus"
                        )
                    }
                    .tint(VecklyDesign.Colors.inkMid)
                    .accessibilityLabel(day.isSkipped ? L10n.format("accessibility.planDay", day.weekdayLabel) : L10n.format("accessibility.skipDay", day.weekdayLabel))
                }
        }
    }
}

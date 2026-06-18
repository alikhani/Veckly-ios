import SwiftUI

/// Pairs a recipe with the day it belongs to, so RecipeDetailView can offer
/// day-level actions (skip/plan) in context.
private struct SelectedDayRecipe: Identifiable {
    let day: WeekDayRowViewModel
    let recipe: WeekSummaryRecipe
    var id: String { recipe.id + day.id }
}

struct WeekTabView: View {
    @Environment(AppModel.self) private var appModel
    @State private var selectedDayRecipe: SelectedDayRecipe?
    @State private var mealPickerDay: WeekDayRowViewModel?
    @State private var selectedDayForDetail: WeekDayRowViewModel?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if appModel.householdStore.isLoading || appModel.weekStore.isLoading {
                    LoadingPanel(title: "Loading this week")
                } else if appModel.weekStore.isGenerating {
                    LoadingPanel(title: "Generating your week…")
                } else if let errorMessage = appModel.weekStore.errorMessage ?? appModel.householdStore.errorMessage {
                    ErrorPanel(message: errorMessage) {
                        Task { await appModel.loadCoreReader() }
                    }
                } else if !appModel.weekStore.hasWeekContent {
                    emptyWeekView
                } else {
                    tonightHeroCard
                    weekList
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
                } else {
                    Button {
                        guard let household = appModel.householdStore.activeHousehold else { return }
                        let regenerate = !appModel.weekStore.hasEmptyDays
                        Task {
                            await appModel.weekStore.generateWeek(
                                household: household,
                                userID: appModel.authSessionStore.userID ?? "",
                                regenerate: regenerate
                            )
                        }
                    } label: {
                        Text(appModel.weekStore.hasEmptyDays || !appModel.weekStore.hasWeekContent ? "Generate" : "Regenerate")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(VecklyDesign.Colors.hearthOrange)
                    .disabled(appModel.householdStore.activeHousehold == nil)

                    Button {
                        Task { await appModel.loadCoreReader() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh")
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
                        let userID = appModel.authSessionStore.userID ?? ""
                        selectedDayRecipe = nil
                        Task { await appModel.weekStore.toggleSkip(day: pair.day, household: household, userID: userID) }
                    }
                )
            }
        }
        .sheet(item: $mealPickerDay) { day in
            MealPickerSheet(
                day: day,
                isSkipped: day.isSkipped,
                householdID: appModel.householdStore.activeHousehold?.id ?? "",
                onSelect: { recipe in
                    mealPickerDay = nil
                    guard let household = appModel.householdStore.activeHousehold else { return }
                    let userID = appModel.authSessionStore.userID ?? ""
                    let summaryRecipe = WeekSummaryRecipe(
                        id: recipe.id,
                        title: recipe.title,
                        description: recipe.description,
                        servings: recipe.servings,
                        prepTimeMinutes: recipe.prepTimeMinutes,
                        cookTimeMinutes: recipe.cookTimeMinutes,
                        tags: recipe.tags
                    )
                    Task { await appModel.weekStore.assignMeal(day: day, recipe: summaryRecipe, household: household, userID: userID) }
                },
                onClear: {
                    mealPickerDay = nil
                    guard let household = appModel.householdStore.activeHousehold else { return }
                    let userID = appModel.authSessionStore.userID ?? ""
                    Task { await appModel.weekStore.unassignMeal(day: day, household: household, userID: userID) }
                },
                onSkip: {
                    guard let household = appModel.householdStore.activeHousehold else { return }
                    let userID = appModel.authSessionStore.userID ?? ""
                    Task { await appModel.weekStore.toggleSkip(day: day, household: household, userID: userID) }
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
                    let userID = appModel.authSessionStore.userID ?? ""
                    Task { await appModel.weekStore.toggleSkip(day: day, household: household, userID: userID) }
                },
                onClear: {
                    selectedDayForDetail = nil
                    guard let household = appModel.householdStore.activeHousehold else { return }
                    let userID = appModel.authSessionStore.userID ?? ""
                    Task { await appModel.weekStore.unassignMeal(day: day, household: household, userID: userID) }
                },
                onDismiss: { selectedDayForDetail = nil }
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(appModel.householdStore.activeHousehold?.name ?? "Your household")
                .font(.subheadline)
                .foregroundStyle(VecklyDesign.Colors.hearthOrange)
                .textCase(.uppercase)
            Text("This week")
                .font(VecklyDesign.Typography.displayHeading(size: 34))
                .foregroundStyle(VecklyDesign.Colors.inkDeep)
        }
    }

    private var emptyWeekView: some View {
        VStack(alignment: .leading, spacing: 16) {
            VecklyCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Empty week")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(VecklyDesign.Colors.inkFaint)
                        .textCase(.uppercase)

                    Text("What's for dinner this week?")
                        .font(VecklyDesign.Typography.displayHeading(size: 22))
                        .foregroundStyle(VecklyDesign.Colors.inkDeep)

                    Text("We'll suggest 5 dinners that fit your week — adjust from there.")
                        .font(.body)
                        .foregroundStyle(VecklyDesign.Colors.inkMid)

                    Button("Plan my week for me") {
                        guard let household = appModel.householdStore.activeHousehold else { return }
                        Task {
                            await appModel.weekStore.generateWeek(
                                household: household,
                                userID: appModel.authSessionStore.userID ?? "",
                                regenerate: false
                            )
                        }
                    }
                    .buttonStyle(VecklyPrimaryButtonStyle())
                    .padding(.top, 4)
                    .disabled(appModel.householdStore.activeHousehold == nil)

                    Button("Or choose each day") {
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

            Text("The week")
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

    private var tonightHeroDay: WeekDayRowViewModel? {
        let rows = appModel.weekStore.dayRows
        if let today = rows.first(where: { $0.isToday && $0.recipe != nil }) {
            return today
        }
        let todayIndex = rows.firstIndex(where: { $0.isToday }) ?? -1
        if todayIndex >= 0, let next = rows[(todayIndex + 1)...].first(where: { $0.recipe != nil }) {
            return next
        }
        return rows.first(where: { $0.recipe != nil })
    }

    private var tonightHeroLabel: String {
        guard let hero = tonightHeroDay else { return "" }
        if hero.isToday { return "Tonight" }
        let rows = appModel.weekStore.dayRows
        let todayIndex = rows.firstIndex(where: { $0.isToday }) ?? -1
        let heroIndex = rows.firstIndex(where: { $0.id == hero.id }) ?? -1
        return heroIndex > todayIndex
            ? "Next up · \(hero.weekdayLabel)"
            : "This week · \(hero.weekdayLabel)"
    }

    @ViewBuilder
    private var tonightHeroCard: some View {
        if let day = tonightHeroDay {
            VecklyCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(tonightHeroLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(VecklyDesign.Colors.hearthOrange)
                            .textCase(.uppercase)
                        Spacer()
                        if day.isToday {
                            Text("Today")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(VecklyDesign.Colors.hearthOrange)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .overlay(Capsule().stroke(VecklyDesign.Colors.hearthOrange, lineWidth: 1))
                        }
                    }

                    Text(day.mealTitle)
                        .font(VecklyDesign.Typography.displayHeading(size: 24))
                        .foregroundStyle(VecklyDesign.Colors.inkDeep)

                    if !day.detail.isEmpty {
                        Text(day.detail)
                            .font(.body)
                            .foregroundStyle(VecklyDesign.Colors.inkMid)
                    }

                    HStack(spacing: 10) {
                        Button {
                            if let recipe = day.recipe {
                                selectedDayRecipe = SelectedDayRecipe(day: day, recipe: recipe)
                            }
                        } label: {
                            Label("Recipe", systemImage: "book")
                        }
                        .buttonStyle(.bordered)
                        .tint(VecklyDesign.Colors.inkMid)

                        Button {
                            mealPickerDay = day
                        } label: {
                            Label("Swap", systemImage: "arrow.2.squarepath")
                        }
                        .buttonStyle(.bordered)
                        .tint(VecklyDesign.Colors.inkMid)

                        Button {
                            guard let household = appModel.householdStore.activeHousehold else { return }
                            let userID = appModel.authSessionStore.userID ?? ""
                            Task { await appModel.weekStore.toggleLock(day: day, household: household, userID: userID) }
                        } label: {
                            Image(systemName: day.isLocked ? "lock.fill" : "lock.open")
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.bordered)
                        .tint(day.isLocked ? VecklyDesign.Colors.hearthOrange : VecklyDesign.Colors.inkMid)
                        .accessibilityLabel(day.isLocked ? "Unlock \(day.weekdayLabel)" : "Lock \(day.weekdayLabel)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("tonightMealPanel")
            }
        }
    }

    private var listDays: [WeekDayRowViewModel] {
        guard let heroId = tonightHeroDay?.id else {
            return appModel.weekStore.dayRows
        }
        return appModel.weekStore.dayRows.filter { $0.id != heroId }
    }

    private var weekList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(tonightHeroDay == nil ? "The week" : "The rest of the week")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(VecklyDesign.Colors.inkFaint)
                .padding(.bottom, 4)

            ForEach(listDays) { day in
                CompactDayRow(
                    day: day,
                    onTap: {
                        if day.recipe != nil { selectedDayForDetail = day }
                        else { mealPickerDay = day }
                    },
                    onToggleSkip: {
                        guard let household = appModel.householdStore.activeHousehold else { return }
                        let userID = appModel.authSessionStore.userID ?? ""
                        Task { await appModel.weekStore.toggleSkip(day: day, household: household, userID: userID) }
                    }
                )
                if day.id != listDays.last?.id {
                    Divider().padding(.leading, 56)
                }
            }
        }
        .accessibilityIdentifier("weekPlanList")
    }
}

struct CompactDayRow: View {
    let day: WeekDayRowViewModel
    let onTap: () -> Void
    let onToggleSkip: () -> Void

    var body: some View {
        Button(action: onTap) {
            rowContent
        }
        .buttonStyle(.plain)
        .opacity(day.isPast ? 0.45 : 1)
        .modifier(SwipeSkipModifier(day: day, onToggleSkip: onToggleSkip))
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
            Text(String(day.weekdayLabel.prefix(3)))
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
            if day.isLocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(VecklyDesign.Colors.hearthOrange)
                    .accessibilityLabel("Locked")
            }
        }
    }

    private var emptyContent: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("Add dinner")
                .font(.body.italic())
                .foregroundStyle(VecklyDesign.Colors.inkFaint)
            Spacer()
            if !day.isPast {
                Text("Plan")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(VecklyDesign.Colors.hearthOrange)
            }
        }
    }

    private var skippedContent: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("Skipped")
                .font(.body)
                .foregroundStyle(VecklyDesign.Colors.inkFaint)
            Spacer()
            if !day.isPast {
                Text("Plan")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(VecklyDesign.Colors.hearthOrange)
            }
        }
        .opacity(0.7)
    }
}

/// Attaches a swipe-to-skip action only when the day is not in the past.
/// The condition is resolved outside the swipeActions ViewBuilder so SwiftUI
/// never receives a conditionally-empty modifier body, which can leave a ghost
/// swipe handle on some versions of UIKit.
private struct SwipeSkipModifier: ViewModifier {
    let day: WeekDayRowViewModel
    let onToggleSkip: () -> Void

    func body(content: Content) -> some View {
        if day.isPast {
            content
        } else {
            content
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(action: onToggleSkip) {
                        Label(
                            day.isSkipped ? "Plan day" : "Skip",
                            systemImage: day.isSkipped ? "calendar.badge.plus" : "calendar.badge.minus"
                        )
                    }
                    .tint(VecklyDesign.Colors.inkMid)
                    .accessibilityLabel(day.isSkipped ? "Plan \(day.weekdayLabel)" : "Skip \(day.weekdayLabel)")
                }
        }
    }
}

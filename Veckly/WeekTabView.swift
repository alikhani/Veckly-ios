import SwiftUI

struct WeekTabView: View {
    @Environment(AppModel.self) private var appModel
    @State private var selectedRecipe: WeekSummaryRecipe?
    @State private var expandedDayId: String?
    @State private var mealPickerDay: WeekDayRowViewModel?

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
                } else if appModel.weekStore.dayRows.allSatisfy({ $0.recipe == nil }) {
                    emptyWeekView
                } else {
                    tonightHeroCard
                    restOfWeekList
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
                        let hasAnyMeal = appModel.weekStore.dayRows.contains { !$0.isEmpty }
                        Task {
                            await appModel.weekStore.generateWeek(
                                household: household,
                                userID: appModel.authSessionStore.userID ?? "",
                                regenerate: hasAnyMeal
                            )
                        }
                    } label: {
                        Text(appModel.weekStore.dayRows.contains { !$0.isEmpty } ? "Regenerate" : "Generate")
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
        .sheet(item: $selectedRecipe) { recipe in
            RecipeDetailView(
                recipe: recipe,
                householdID: appModel.householdStore.activeHousehold?.id ?? ""
            )
        }
        .sheet(item: $mealPickerDay) { day in
            MealPickerSheet(
                day: day,
                householdID: appModel.householdStore.activeHousehold?.id ?? "",
                apiClient: appModel.apiClient,
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
                onDismiss: { mealPickerDay = nil }
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
            let isLocked = appModel.weekStore.lockedDays.contains(day.weekday)
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
                            selectedRecipe = day.recipe
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
                            Image(systemName: isLocked ? "lock.fill" : "lock.open")
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.bordered)
                        .tint(isLocked ? VecklyDesign.Colors.hearthOrange : VecklyDesign.Colors.inkMid)
                        .accessibilityLabel(isLocked ? "Unlock \(day.weekdayLabel)" : "Lock \(day.weekdayLabel)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("tonightMealPanel")
            }
        }
    }

    private var remainingDays: [WeekDayRowViewModel] {
        let heroId = tonightHeroDay?.id
        return appModel.weekStore.dayRows.filter { $0.id != heroId }
    }

    private var restOfWeekList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("The rest of the week")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(VecklyDesign.Colors.inkFaint)
                .padding(.bottom, 4)

            ForEach(remainingDays) { day in
                CompactDayRow(
                    day: day,
                    isExpanded: expandedDayId == day.id,
                    isLocked: appModel.weekStore.lockedDays.contains(day.weekday),
                    isSkipped: appModel.weekStore.skippedDays.contains(day.weekday),
                    onToggle: {
                        withAnimation(.spring(response: 0.3)) {
                            expandedDayId = expandedDayId == day.id ? nil : day.id
                        }
                    },
                    onToggleLock: {
                        guard let household = appModel.householdStore.activeHousehold else { return }
                        let userID = appModel.authSessionStore.userID ?? ""
                        Task { await appModel.weekStore.toggleLock(day: day, household: household, userID: userID) }
                    },
                    onToggleSkip: {
                        guard let household = appModel.householdStore.activeHousehold else { return }
                        let userID = appModel.authSessionStore.userID ?? ""
                        Task { await appModel.weekStore.toggleSkip(day: day, household: household, userID: userID) }
                    },
                    onViewRecipe: day.recipe != nil ? { selectedRecipe = day.recipe } : nil,
                    onPickMeal: { mealPickerDay = day }
                )
                if day.id != remainingDays.last?.id {
                    Divider().padding(.leading, 56)
                }
            }
        }
        .accessibilityIdentifier("weekPlanList")
    }
}

struct CompactDayRow: View {
    let day: WeekDayRowViewModel
    let isExpanded: Bool
    let isLocked: Bool
    let isSkipped: Bool
    let onToggle: () -> Void
    let onToggleLock: () -> Void
    let onToggleSkip: () -> Void
    let onViewRecipe: (() -> Void)?
    let onPickMeal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if day.recipe == nil && !isSkipped {
                emptyRow
            } else {
                Button(action: onToggle) { collapsedRow }
                    .buttonStyle(.plain)
                if isExpanded {
                    expandedDetail
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .animation(.spring(response: 0.3), value: isExpanded)
        .opacity(isSkipped ? 0.6 : 1)
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

    private var collapsedRow: some View {
        HStack(alignment: .center, spacing: 12) {
            dateColumn
            Text(isSkipped ? "Skipped day" : day.mealTitle)
                .font(.body.weight(isSkipped ? .regular : .medium))
                .foregroundStyle(isSkipped ? VecklyDesign.Colors.inkFaint : VecklyDesign.Colors.inkDeep)
            Spacer()
            if isLocked && !isSkipped {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(VecklyDesign.Colors.hearthOrange)
            }
        }
        .padding(.vertical, 12)
    }

    private var emptyRow: some View {
        Button(action: onPickMeal) {
            HStack(alignment: .center, spacing: 12) {
                dateColumn
                Text("Add dinner")
                    .font(.body)
                    .foregroundStyle(VecklyDesign.Colors.inkFaint)
                Spacer()
                Text("Plan")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(VecklyDesign.Colors.hearthOrange)
            }
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var expandedDetail: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isSkipped {
                Button("Undo skip", action: onToggleSkip)
                    .font(.footnote)
                    .foregroundStyle(VecklyDesign.Colors.inkMid)
                    .buttonStyle(.plain)
            } else if let recipe = day.recipe {
                if !recipe.description.isEmpty {
                    Text(recipe.description)
                        .font(.footnote)
                        .foregroundStyle(VecklyDesign.Colors.inkMid)
                }
                HStack(spacing: 8) {
                    if let onViewRecipe {
                        Button("View recipe", action: onViewRecipe)
                            .buttonStyle(.bordered)
                            .tint(VecklyDesign.Colors.hearthOrange)
                            .font(.footnote)
                    }
                    if !isLocked {
                        Button("Change meal", action: onPickMeal)
                            .buttonStyle(.bordered)
                            .font(.footnote)
                    }
                    Button(action: onToggleLock) {
                        Image(systemName: isLocked ? "lock.fill" : "lock.open")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    .tint(isLocked ? VecklyDesign.Colors.hearthOrange : VecklyDesign.Colors.inkMid)
                    .accessibilityLabel(isLocked ? "Unlock \(day.weekdayLabel)" : "Lock \(day.weekdayLabel)")
                }
                Button("Skip this day", action: onToggleSkip)
                    .font(.footnote)
                    .foregroundStyle(VecklyDesign.Colors.inkMid)
                    .buttonStyle(.plain)
            }
        }
        .padding(.leading, 56)
        .padding(.bottom, 10)
    }
}


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
                    Task { await appModel.weekStore.assignMeal(day: day, recipeID: recipe.id, household: household, userID: userID) }
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

    @ViewBuilder
    private var tonightHeroCard: some View {
        if let day = tonightHeroDay {
            let isLocked = appModel.weekStore.lockedDays.contains(day.weekday)
            VecklyCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(day.isToday ? "Tonight" : "Next up · \(day.weekdayLabel)")
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

    private var weekList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Plan")
                .font(.headline)
                .foregroundStyle(VecklyDesign.Colors.inkDeep)

            ForEach(appModel.weekStore.dayRows) { day in
                WeekDayRow(
                    day: day,
                    isExpanded: expandedDayId == day.id,
                    isLocked: appModel.weekStore.lockedDays.contains(day.weekday),
                    isSkipped: appModel.weekStore.skippedDays.contains(day.weekday),
                    selectedVote: day.recipe.flatMap { appModel.weekStore.mealFeedback[$0.id] },
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
                    onFeedback: { vote in
                        guard let household = appModel.householdStore.activeHousehold, let mealID = day.recipe?.id else { return }
                        Task { await appModel.weekStore.submitFeedback(mealID: mealID, vote: vote, household: household) }
                    },
                    onViewRecipe: day.recipe != nil ? { selectedRecipe = day.recipe } : nil,
                    onPickMeal: { mealPickerDay = day }
                )
            }
        }
        .accessibilityIdentifier("weekPlanList")
    }
}

struct WeekDayRow: View {
    let day: WeekDayRowViewModel
    let isExpanded: Bool
    let isLocked: Bool
    let isSkipped: Bool
    let selectedVote: MealVote?
    let onToggle: () -> Void
    let onToggleLock: () -> Void
    let onToggleSkip: () -> Void
    let onFeedback: (MealVote) -> Void
    let onViewRecipe: (() -> Void)?
    let onPickMeal: () -> Void

    var body: some View {
        VecklyCard {
            VStack(alignment: .leading, spacing: 0) {
                headerRow
                if isExpanded {
                    expandedBody
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .opacity(isSkipped ? 0.5 : 1)
        .animation(.spring(response: 0.3), value: isExpanded)
        .animation(.easeInOut(duration: 0.2), value: isSkipped)
    }

    private var headerRow: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(day.weekdayLabel)
                        .font(.headline)
                    Text(day.dateLabel)
                        .font(.caption)
                        .foregroundStyle(VecklyDesign.Colors.inkFaint)
                }
                .frame(width: 92, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text(isSkipped ? "Skipped" : day.mealTitle)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(
                            isSkipped
                                ? VecklyDesign.Colors.inkFaint
                                : (day.isEmpty ? VecklyDesign.Colors.inkFaint : VecklyDesign.Colors.inkDeep)
                        )
                    if !isExpanded {
                        Text(day.detail)
                            .font(.footnote)
                            .foregroundStyle(VecklyDesign.Colors.inkMid)
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    if day.isToday {
                        Text("Today")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(VecklyDesign.Colors.hearthOrange)
                    }

                    if !isSkipped {
                        Button(action: onToggleLock) {
                            Image(systemName: isLocked ? "lock.fill" : "lock.open")
                                .font(.system(size: 14))
                                .foregroundStyle(isLocked ? VecklyDesign.Colors.hearthOrange : VecklyDesign.Colors.inkFaint)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isLocked ? "Unlock \(day.weekdayLabel)" : "Lock \(day.weekdayLabel)")
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
                .padding(.top, 8)

            if let recipe = day.recipe, !isSkipped {
                Text(recipe.description)
                    .font(.body)
                    .foregroundStyle(VecklyDesign.Colors.inkMid)

                tagRow(recipe: recipe)
                feedbackRow

                HStack(spacing: 10) {
                    if let onViewRecipe {
                        Button("View recipe", action: onViewRecipe)
                            .buttonStyle(.bordered)
                            .tint(VecklyDesign.Colors.hearthOrange)
                    }
                    if !isLocked {
                        Button("Change meal", action: onPickMeal)
                            .buttonStyle(.bordered)
                    }
                }
            } else if !isSkipped {
                Text(day.detail)
                    .font(.footnote)
                    .foregroundStyle(VecklyDesign.Colors.inkMid)
                Button("Choose meal", action: onPickMeal)
                    .buttonStyle(VecklyPrimaryButtonStyle())
                    .padding(.top, 4)
            }

            Button(isSkipped ? "Undo skip" : "Skip this day", action: onToggleSkip)
                .font(.footnote)
                .foregroundStyle(VecklyDesign.Colors.inkMid)
                .buttonStyle(.plain)
        }
        .padding(.top, 4)
    }

    private var feedbackRow: some View {
        HStack(spacing: 10) {
            FeedbackVoteButton(
                vote: .up,
                isSelected: selectedVote == .up,
                action: { onFeedback(.up) }
            )
            FeedbackVoteButton(
                vote: .down,
                isSelected: selectedVote == .down,
                action: { onFeedback(.down) }
            )
        }
    }

    @ViewBuilder
    private func tagRow(recipe: WeekSummaryRecipe) -> some View {
        let hasFeedbackTag = recipe.tags.contains("based-on-feedback")
        let otherTags = recipe.tags.filter { $0 != "based-on-feedback" }

        if !otherTags.isEmpty || hasFeedbackTag {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(otherTags, id: \.self) { tag in
                        TagPill(label: tag)
                    }
                    if hasFeedbackTag {
                        FeedbackTagPill()
                    }
                }
            }
        }
    }
}

struct FeedbackVoteButton: View {
    let vote: MealVote
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: iconName)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 36, height: 32)
                .foregroundStyle(isSelected ? .white : VecklyDesign.Colors.inkMid)
                .background(isSelected ? selectedColor : VecklyDesign.Colors.canvas)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(borderColor, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var iconName: String {
        switch vote {
        case .up:
            return isSelected ? "hand.thumbsup.fill" : "hand.thumbsup"
        case .down:
            return isSelected ? "hand.thumbsdown.fill" : "hand.thumbsdown"
        }
    }

    private var accessibilityLabel: String {
        switch vote {
        case .up:
            return "Like this meal"
        case .down:
            return "Not for us"
        }
    }

    private var selectedColor: Color {
        vote == .up ? VecklyDesign.Colors.hearthOrange : VecklyDesign.Colors.inkMid
    }

    private var borderColor: Color {
        isSelected ? selectedColor : VecklyDesign.Colors.edgeLight
    }
}

struct TagPill: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.caption.weight(.medium))
            .foregroundStyle(VecklyDesign.Colors.inkMid)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(VecklyDesign.Colors.canvas)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(VecklyDesign.Colors.inkFaint.opacity(0.4), lineWidth: 1))
    }
}

struct FeedbackTagPill: View {
    @State private var showPopover = false

    var body: some View {
        Button {
            showPopover = true
        } label: {
            HStack(spacing: 4) {
                Text("Based on your feedback")
                    .font(.caption.weight(.medium))
                Image(systemName: "info.circle")
                    .font(.caption)
            }
            .foregroundStyle(VecklyDesign.Colors.hearthOrange)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(VecklyDesign.Colors.hearthOrange.opacity(0.08))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(VecklyDesign.Colors.hearthOrange.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover) {
            Text("Vi har valt det här baserat på liknande rätter du gillat.")
                .font(.callout)
                .padding(16)
                .presentationCompactAdaptation(.popover)
        }
    }
}

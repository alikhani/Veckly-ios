import SwiftUI

struct DayDetailSheet: View {
    let day: WeekDayRowViewModel
    let householdID: String
    let onViewRecipe: () -> Void
    let onSwap: () -> Void
    let onSkip: () -> Void
    let onClear: () -> Void
    let onMarkAsLeftover: () -> Void
    /// Lock now lives here and in the week list's status icon, not as a
    /// hero button (beslut 3, Fas 3) — `nil` hides the control entirely,
    /// which `MealPickerSheet`'s not-yet-saved preview relies on.
    var isLocked: Bool = false
    var onToggleLock: (() -> Void)? = nil
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            DayDetailContent(
                day: day,
                householdID: householdID,
                onViewRecipe: onViewRecipe,
                onSwap: onSwap,
                onSkip: {
                    onSkip()
                    onDismiss()
                },
                onClear: onClear,
                onMarkAsLeftover: onMarkAsLeftover,
                isLocked: isLocked,
                onToggleLock: onToggleLock
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done", action: onDismiss)
                }
            }
        }
    }
}

/// The body of `DayDetailSheet` — title/meta/vote/actions for an already-planned
/// day — extracted so `MealPickerSheet` can render the identical view once a
/// recipe is confirmed in the same sheet, without duplicating it or nesting a
/// second `NavigationStack`/toolbar inside the picker's own.
struct DayDetailContent: View {
    let day: WeekDayRowViewModel
    let householdID: String
    let onViewRecipe: () -> Void
    let onSwap: () -> Void
    let onSkip: () -> Void
    let onClear: () -> Void
    let onMarkAsLeftover: () -> Void
    var isLocked: Bool = false
    var onToggleLock: (() -> Void)? = nil

    @Environment(AppModel.self) private var appModel
    @State private var showClearConfirmation = false
    @State private var showSkipConfirmation = false

    private var recipe: WeekSummaryRecipe? { day.recipe }

    private var currentVote: MealVote? {
        guard let recipe else { return nil }
        return appModel.feedbackStore.vote(for: recipe.id)
    }

    var body: some View {
        Group {
            if let recipe {
                content(recipe: recipe)
            } else {
                // Shouldn't happen — this view only renders when a recipe is assigned
                ContentUnavailableView(L10n.string("meal.noAssigned"), systemImage: "fork.knife")
            }
        }
    }

    @ViewBuilder
    private func content(recipe: WeekSummaryRecipe) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Day label
                Text("\(day.weekdayLabel.uppercased()) · \(day.dateLabel)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VecklyDesign.Colors.inkFaint)

                // Recipe title
                Text(recipe.title)
                    .font(VecklyDesign.Typography.screenTitle)
                    .foregroundStyle(VecklyDesign.Colors.inkDeep)

                // Time + servings
                metaRow(recipe: recipe)

                // Description
                if !recipe.description.isEmpty {
                    Text(recipe.description)
                        .font(.body)
                        .foregroundStyle(VecklyDesign.Colors.inkMid)
                }

                // Vote buttons
                voteButtons(recipeID: recipe.id)

                Button {
                    onSwap()
                } label: {
                    Label("meal.swapMeal", systemImage: "arrow.2.squarepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(VecklyPrimaryButtonStyle())
                .accessibilityLabel(L10n.format("accessibility.swapMealFor", day.weekdayLabel))

                HStack(spacing: 12) {
                    Button {
                        onViewRecipe()
                    } label: {
                        Label("meal.viewRecipe", systemImage: "book")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(VecklyDesign.Colors.inkMid)
                    .accessibilityLabel(L10n.format("accessibility.viewRecipeFor", recipe.title))

                    Menu {
                        Button(action: onMarkAsLeftover) {
                            Label("prep.eatAgain", systemImage: "arrow.3.trianglepath")
                        }
                        Menu("meal.householdSignal.title", systemImage: "person.2") {
                            Button {
                                toggleHouseholdSignal(.worksForFamily, recipeID: recipe.id)
                            } label: {
                                Label("meal.householdSignal.works", systemImage: "checkmark.seal")
                            }
                            Button {
                                toggleHouseholdSignal(.notForUs, recipeID: recipe.id)
                            } label: {
                                Label("meal.householdSignal.notForUs", systemImage: "xmark.seal")
                            }
                        }
                        if let onToggleLock {
                            Button(action: onToggleLock) {
                                Label(
                                    isLocked ? L10n.string("meal.unlockDay") : L10n.string("meal.lockDay"),
                                    systemImage: isLocked ? "lock.open" : "lock"
                                )
                            }
                        }
                        Button {
                            if day.isSkipped { onSkip() } else { showSkipConfirmation = true }
                        } label: {
                            Label(
                                day.isSkipped ? L10n.string("meal.planDayInstead") : L10n.string("meal.skipDay"),
                                systemImage: day.isSkipped ? "calendar.badge.plus" : "calendar.badge.minus"
                            )
                        }
                        Button(role: .destructive) { showClearConfirmation = true } label: {
                            Label("meal.clear", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(VecklyDesign.Colors.inkMid)
                    .accessibilityLabel(L10n.string("common.more"))
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(VecklyDesign.Colors.canvas)
        .removeDishConfirmation(isPresented: $showClearConfirmation, onConfirm: onClear)
        .skipDayConfirmation(isPresented: $showSkipConfirmation, onConfirm: onSkip)
    }

    @ViewBuilder
    private func metaRow(recipe: WeekSummaryRecipe) -> some View {
        let totalTime = (recipe.prepTimeMinutes ?? 0) + (recipe.cookTimeMinutes ?? 0)
        HStack(spacing: 12) {
            if totalTime > 0 {
                Label("\(totalTime) min", systemImage: "clock")
                    .font(.footnote)
                    .foregroundStyle(VecklyDesign.Colors.inkMid)
            }
            Label(L10n.format("format.servings", recipe.servings), systemImage: "person.2")
                .font(.footnote)
                .foregroundStyle(VecklyDesign.Colors.inkMid)
        }
    }

    @ViewBuilder
    private func voteButtons(recipeID: String) -> some View {
        HStack(spacing: 12) {
            Button {
                Task { await toggleVote(.up, recipeID: recipeID) }
            } label: {
                Label("recipes.like", systemImage: "hand.thumbsup")
                    .labelStyle(.iconOnly)
                    .font(.title3)
            }
            .buttonStyle(.bordered)
            .tint(currentVote == .up ? VecklyDesign.Colors.hearthOrangeFill : VecklyDesign.Colors.inkMid)
            .accessibilityLabel(L10n.string(currentVote == .up ? "recipes.removeLike" : "recipes.likeThis"))

            Button {
                Task { await toggleVote(.down, recipeID: recipeID) }
            } label: {
                Label("recipes.dislike", systemImage: "hand.thumbsdown")
                    .labelStyle(.iconOnly)
                    .font(.title3)
            }
            .buttonStyle(.bordered)
            .tint(currentVote == .down ? VecklyDesign.Colors.hearthOrangeFill : VecklyDesign.Colors.inkMid)
            .accessibilityLabel(L10n.string(currentVote == .down ? "recipes.removeDislike" : "recipes.dislikeThis"))
        }
    }

    private func toggleVote(_ vote: MealVote, recipeID: String) async {
        let newVote: MealVote? = currentVote == vote ? nil : vote
        await appModel.feedbackStore.setVote(
            householdID: householdID,
            recipeID: recipeID,
            vote: newVote
        )
    }

    private func toggleHouseholdSignal(_ signal: HouseholdMealSignal, recipeID: String) {
        let current = appModel.householdMealSignalStore.signal(for: recipeID)
        Task {
            await appModel.householdMealSignalStore.setSignal(
                householdID: householdID,
                recipeID: recipeID,
                signal: current == signal ? nil : signal
            )
        }
    }
}

import SwiftUI

struct DayDetailSheet: View {
    let day: WeekDayRowViewModel
    let householdID: String
    let onViewRecipe: () -> Void
    let onSwap: () -> Void
    let onSkip: () -> Void
    let onClear: () -> Void
    let onMarkAsLeftover: () -> Void
    let onDismiss: () -> Void

    @State private var showClearConfirmation = false

    var body: some View {
        NavigationStack {
            DayDetailContent(
                day: day,
                householdID: householdID,
                onViewRecipe: onViewRecipe,
                onSwap: onSwap,
                onSkip: { onSkip(); onDismiss() },
                onClear: onClear,
                onMarkAsLeftover: onMarkAsLeftover
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel", action: onDismiss)
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button("meal.clear", role: .destructive) {
                        showClearConfirmation = true
                    }
                    .foregroundStyle(.red)
                }
            }
            .confirmationDialog(L10n.string("meal.removeConfirmation"), isPresented: $showClearConfirmation, titleVisibility: .visible) {
                Button("meal.clear", role: .destructive) { onClear() }
                Button("common.cancel", role: .cancel) {}
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

    @Environment(AppModel.self) private var appModel

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
                    .font(VecklyDesign.Typography.displayHeading(size: 22))
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

                // Action buttons
                HStack(spacing: 12) {
                    Button {
                        onViewRecipe()
                    } label: {
                        Label("meal.viewRecipe", systemImage: "book")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(VecklyDesign.Colors.inkMid)

                    Button {
                        onSwap()
                    } label: {
                        Label("meal.swapMeal", systemImage: "arrow.2.squarepath")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(VecklyDesign.Colors.inkMid)
                }

                // Eat this again (mark as leftovers for another day)
                Button {
                    onMarkAsLeftover()
                } label: {
                    HStack {
                        Image(systemName: "arrow.3.trianglepath")
                        Text("prep.eatAgain")
                        Spacer()
                    }
                    .foregroundStyle(VecklyDesign.Colors.inkMid)
                }
                .buttonStyle(.plain)

                // Skip
                Button {
                    onSkip()
                } label: {
                    HStack {
                        Image(systemName: day.isSkipped ? "calendar.badge.plus" : "calendar.badge.minus")
                        Text(day.isSkipped ? L10n.string("meal.planDayInstead") : L10n.string("meal.skipDay"))
                        Spacer()
                    }
                    .foregroundStyle(VecklyDesign.Colors.inkMid)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(day.isSkipped ? L10n.format("accessibility.planDay", day.weekdayLabel) : L10n.format("accessibility.skipDay", day.weekdayLabel))
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(VecklyDesign.Colors.canvas)
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
            .tint(currentVote == .up ? VecklyDesign.Colors.hearthOrange : VecklyDesign.Colors.inkMid)
            .accessibilityLabel(L10n.string(currentVote == .up ? "recipes.removeLike" : "recipes.likeThis"))

            Button {
                Task { await toggleVote(.down, recipeID: recipeID) }
            } label: {
                Label("recipes.dislike", systemImage: "hand.thumbsdown")
                    .labelStyle(.iconOnly)
                    .font(.title3)
            }
            .buttonStyle(.bordered)
            .tint(currentVote == .down ? VecklyDesign.Colors.hearthOrange : VecklyDesign.Colors.inkMid)
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
}

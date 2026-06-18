import SwiftUI

struct DayDetailSheet: View {
    let day: WeekDayRowViewModel
    let householdID: String
    let onViewRecipe: () -> Void
    let onSwap: () -> Void
    let onSkip: () -> Void
    let onClear: () -> Void
    let onDismiss: () -> Void

    @Environment(AppModel.self) private var appModel
    @State private var currentVote: MealVote?

    private var recipe: WeekSummaryRecipe? { day.recipe }

    var body: some View {
        NavigationStack {
            Group {
                if let recipe {
                    content(recipe: recipe)
                } else {
                    // Shouldn't happen — this sheet only opens when a recipe is assigned
                    ContentUnavailableView("No meal assigned", systemImage: "fork.knife")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDismiss)
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Clear meal", role: .destructive) {
                        onClear()
                    }
                    .foregroundStyle(.red)
                }
            }
        }
        .onAppear {
            if let recipe {
                currentVote = appModel.feedbackStore.vote(for: recipe.id)
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
                        Label("View recipe", systemImage: "book")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(VecklyDesign.Colors.inkMid)

                    Button {
                        onSwap()
                    } label: {
                        Label("Swap meal", systemImage: "arrow.2.squarepath")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(VecklyDesign.Colors.inkMid)
                }

                // Skip
                Button {
                    onSkip()
                    onDismiss()
                } label: {
                    HStack {
                        Image(systemName: day.isSkipped ? "calendar.badge.plus" : "calendar.badge.minus")
                        Text(day.isSkipped ? "Plan this day instead" : "Skip this day")
                        Spacer()
                    }
                    .foregroundStyle(VecklyDesign.Colors.inkMid)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(day.isSkipped ? "Plan \(day.weekdayLabel)" : "Skip \(day.weekdayLabel)")
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
            Label("\(recipe.servings) servings", systemImage: "person.2")
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
                Label("Like", systemImage: "hand.thumbsup")
                    .labelStyle(.iconOnly)
                    .font(.title3)
            }
            .buttonStyle(.bordered)
            .tint(currentVote == .up ? VecklyDesign.Colors.hearthOrange : VecklyDesign.Colors.inkMid)
            .accessibilityLabel(currentVote == .up ? "Remove like" : "Like this recipe")

            Button {
                Task { await toggleVote(.down, recipeID: recipeID) }
            } label: {
                Label("Dislike", systemImage: "hand.thumbsdown")
                    .labelStyle(.iconOnly)
                    .font(.title3)
            }
            .buttonStyle(.bordered)
            .tint(currentVote == .down ? VecklyDesign.Colors.hearthOrange : VecklyDesign.Colors.inkMid)
            .accessibilityLabel(currentVote == .down ? "Remove dislike" : "Dislike this recipe")
        }
    }

    private func toggleVote(_ vote: MealVote, recipeID: String) async {
        let newVote: MealVote? = currentVote == vote ? nil : vote
        currentVote = newVote
        await appModel.feedbackStore.setVote(
            householdID: householdID,
            recipeID: recipeID,
            vote: newVote
        )
    }
}

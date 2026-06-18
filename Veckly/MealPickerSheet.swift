import SwiftUI

struct MealPickerSheet: View {
    let day: WeekDayRowViewModel
    let isSkipped: Bool
    let householdID: String
    let onSelect: (FullRecipe) -> Void
    let onClear: () -> Void
    let onSkip: () -> Void
    let onDismiss: () -> Void

    @Environment(AppModel.self) private var appModel
    @State private var searchText = ""

    private var recipes: [FullRecipe] { appModel.recipeStore.recipes }

    var filtered: [FullRecipe] {
        guard !searchText.isEmpty else { return recipes }
        return recipes.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    private var likedRecipes: [FullRecipe] {
        filtered.filter { appModel.feedbackStore.vote(for: $0.id) == .up }
    }

    private var otherRecipes: [FullRecipe] {
        filtered.filter { appModel.feedbackStore.vote(for: $0.id) != .up }
    }

    var body: some View {
        NavigationStack {
            Group {
                if appModel.recipeStore.isLoading {
                    VStack {
                        ProgressView()
                            .tint(VecklyDesign.Colors.hearthOrange)
                        Text("recipes.loadingEllipsis")
                            .foregroundStyle(VecklyDesign.Colors.inkMid)
                            .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage = appModel.recipeStore.errorMessage {
                    VStack(spacing: 12) {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(VecklyDesign.Colors.inkMid)
                            .multilineTextAlignment(.center)
                        Button("common.tryAgain") {
                            Task { await loadRecipes() }
                        }
                        .foregroundStyle(VecklyDesign.Colors.hearthOrange)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else if filtered.isEmpty && !searchText.isEmpty {
                    ContentUnavailableView(
                        L10n.string("recipes.noResults"),
                        systemImage: "fork.knife",
                        description: Text(L10n.string("recipes.tryDifferentSearchTerm"))
                    )
                } else {
                    recipeListWithFooter
                }
            }
            .navigationTitle(day.weekdayLabel)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: L10n.string("recipes.search"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel", action: onDismiss)
                }
                if !day.isEmpty && !isSkipped {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("meal.clear", role: .destructive, action: onClear)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .task { await loadRecipes() }
    }

    private var recipeListWithFooter: some View {
        List {
            if filtered.isEmpty {
                Section {
                    ContentUnavailableView(
                        L10n.string("recipes.empty.title"),
                        systemImage: "fork.knife",
                        description: Text(L10n.string("recipes.empty.pickerMessage"))
                    )
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                if !likedRecipes.isEmpty {
                    Section(L10n.string("recipes.liked")) {
                        ForEach(likedRecipes) { recipe in
                            Button { onSelect(recipe) } label: { RecipePickerRow(recipe: recipe) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                if !otherRecipes.isEmpty {
                    Section(likedRecipes.isEmpty ? "" : L10n.string("recipes.all")) {
                        ForEach(otherRecipes) { recipe in
                            Button { onSelect(recipe) } label: { RecipePickerRow(recipe: recipe) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }

            Section {
                Button(action: {
                    onSkip()
                    onDismiss()
                }) {
                    HStack {
                        Image(systemName: isSkipped ? "calendar.badge.plus" : "calendar.badge.minus")
                            .foregroundStyle(VecklyDesign.Colors.inkMid)
                        Text(isSkipped ? L10n.string("meal.planDayInstead") : L10n.string("meal.skipDay"))
                            .foregroundStyle(VecklyDesign.Colors.inkMid)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isSkipped ? L10n.format("accessibility.planDayInstead", day.weekdayLabel) : L10n.format("accessibility.skipDay", day.weekdayLabel))
            }
        }
        .listStyle(.insetGrouped)
    }

    private func loadRecipes() async {
        await appModel.loadRecipesAndSeedFeedback(householdID: householdID)
    }
}

private struct RecipePickerRow: View {
    let recipe: FullRecipe

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(recipe.title)
                .font(.body.weight(.medium))
                .foregroundStyle(VecklyDesign.Colors.inkDeep)
            HStack(spacing: 6) {
                Text(L10n.format("format.servings", recipe.servings))
                if let total = cookTime {
                    Text("·")
                    Text("\(total) min")
                }
            }
            .font(.caption)
            .foregroundStyle(VecklyDesign.Colors.inkFaint)
        }
        .padding(.vertical, 4)
    }

    private var cookTime: Int? {
        let t = (recipe.prepTimeMinutes ?? 0) + (recipe.cookTimeMinutes ?? 0)
        return t > 0 ? t : nil
    }
}

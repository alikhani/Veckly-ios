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

    var body: some View {
        NavigationStack {
            Group {
                if appModel.recipeStore.isLoading {
                    VStack {
                        ProgressView()
                            .tint(VecklyDesign.Colors.hearthOrange)
                        Text("Loading recipes…")
                            .foregroundStyle(VecklyDesign.Colors.inkMid)
                            .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filtered.isEmpty && !searchText.isEmpty {
                    ContentUnavailableView(
                        "No results",
                        systemImage: "fork.knife",
                        description: Text("Try a different search term.")
                    )
                } else {
                    recipeListWithFooter
                }
            }
            .navigationTitle(day.weekdayLabel)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search recipes")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDismiss)
                }
                if !day.isEmpty && !isSkipped {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Clear meal", role: .destructive, action: onClear)
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
                        "No recipes yet",
                        systemImage: "fork.knife",
                        description: Text("Add recipes to your household to get started.")
                    )
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                Section {
                    ForEach(filtered) { recipe in
                        Button {
                            onSelect(recipe)
                        } label: {
                            RecipePickerRow(recipe: recipe)
                        }
                        .buttonStyle(.plain)
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
                        Text(isSkipped ? "Plan this day instead" : "Skip this day")
                            .foregroundStyle(VecklyDesign.Colors.inkMid)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isSkipped ? "Plan \(day.weekdayLabel) instead" : "Skip \(day.weekdayLabel)")
            }
        }
        .listStyle(.insetGrouped)
    }

    private func loadRecipes() async {
        await appModel.recipeStore.loadRecipes(householdID: householdID)
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
                Text("\(recipe.servings) servings")
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

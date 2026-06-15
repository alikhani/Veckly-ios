import SwiftUI

struct MealPickerSheet: View {
    let day: WeekDayRowViewModel
    let householdID: String
    let apiClient: VecklyAPIClient
    let onSelect: (FullRecipe) -> Void
    let onClear: () -> Void
    let onDismiss: () -> Void

    @State private var recipes: [FullRecipe] = []
    @State private var isLoading = true
    @State private var searchText = ""

    var filtered: [FullRecipe] {
        guard !searchText.isEmpty else { return recipes }
        return recipes.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack {
                        ProgressView()
                            .tint(VecklyDesign.Colors.hearthOrange)
                        Text("Loading recipes…")
                            .foregroundStyle(VecklyDesign.Colors.inkMid)
                            .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filtered.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No recipes yet" : "No results",
                        systemImage: "fork.knife",
                        description: Text(searchText.isEmpty ? "Add recipes to your household to get started." : "Try a different search term.")
                    )
                } else {
                    List(filtered) { recipe in
                        Button {
                            onSelect(recipe)
                        } label: {
                            RecipePickerRow(recipe: recipe)
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(day.weekdayLabel)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search recipes")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDismiss)
                }
                if !day.isEmpty {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Clear meal", role: .destructive, action: onClear)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .task { await loadRecipes() }
    }

    private func loadRecipes() async {
        isLoading = true
        defer { isLoading = false }
        recipes = (try? await apiClient.listHouseholdRecipes(householdID: householdID, includePublic: true)) ?? []
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

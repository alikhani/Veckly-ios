import SwiftUI

struct RecipesTabView: View {
    @Environment(AppModel.self) private var appModel
    @State private var searchText = ""
    @State private var showAddSheet = false
    @State private var editingRecipe: FullRecipe?

    private var filtered: [FullRecipe] {
        guard !searchText.isEmpty else { return appModel.recipeStore.recipes }
        return appModel.recipeStore.recipes.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        Group {
            if appModel.recipeStore.isLoading {
                LoadingPanel(title: "Loading recipes")
                    .padding()
            } else if filtered.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No recipes yet" : "No results",
                    systemImage: "fork.knife",
                    description: Text(searchText.isEmpty ? "Tap + to add your first recipe." : "Try a different search.")
                )
            } else {
                List(filtered) { recipe in
                    RecipeListRow(recipe: recipe)
                        .swipeActions(edge: .trailing) {
                            Button("Edit") { editingRecipe = recipe }
                                .tint(VecklyDesign.Colors.hearthOrange)
                        }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Recipes")
        .searchable(text: $searchText, prompt: "Search recipes")
        .toolbar {
            Button { showAddSheet = true } label: { Image(systemName: "plus") }
        }
        .sheet(isPresented: $showAddSheet) {
            RecipeFormSheet(mode: .create) { draft in
                guard let household = appModel.householdStore.activeHousehold else { return }
                _ = try await appModel.recipeStore.createRecipe(householdID: household.id, draft: draft)
            }
        }
        .sheet(item: $editingRecipe) { recipe in
            RecipeFormSheet(mode: .edit(recipe)) { draft in
                guard let household = appModel.householdStore.activeHousehold else { return }
                try await appModel.recipeStore.updateRecipe(householdID: household.id, recipeID: recipe.id, draft: draft)
            }
        }
        .task {
            guard let household = appModel.householdStore.activeHousehold else { return }
            if appModel.recipeStore.recipes.isEmpty {
                await appModel.recipeStore.loadRecipes(householdID: household.id)
            }
        }
    }
}

private struct RecipeListRow: View {
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
                if !recipe.tags.isEmpty {
                    Text("·")
                    Text(recipe.tags.prefix(2).joined(separator: ", "))
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

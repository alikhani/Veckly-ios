import SwiftUI

struct RecipesTabView: View {
    @Environment(AppModel.self) private var appModel
    @State private var searchText = ""
    @State private var showAddSheet = false
    @State private var editingRecipe: FullRecipe?
    @State private var archiveCandidate: FullRecipe?
    @State private var transientErrorMessage: String?

    private var filtered: [FullRecipe] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return appModel.recipeStore.recipes }
        return appModel.recipeStore.recipes.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.description.localizedCaseInsensitiveContains(query)
                || $0.tags.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        Group {
            if appModel.recipeStore.isLoading {
                LoadingPanel(title: "Loading recipes")
                    .padding()
            } else if let errorMessage = appModel.recipeStore.errorMessage, appModel.recipeStore.recipes.isEmpty {
                ContentUnavailableView {
                    Label("Could not load recipes", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Try again") {
                        guard let household = appModel.householdStore.activeHousehold else { return }
                        Task { await appModel.recipeStore.loadRecipes(householdID: household.id) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(VecklyDesign.Colors.hearthOrange)
                }
            } else if filtered.isEmpty {
                ContentUnavailableView {
                    Label(searchQuery.isEmpty ? "No recipes yet" : "No results", systemImage: "fork.knife")
                } description: {
                    Text(searchQuery.isEmpty ? "Add your first household recipe." : "Try a different search.")
                } actions: {
                    if searchQuery.isEmpty {
                        Button("Add recipe") { showAddSheet = true }
                            .buttonStyle(.borderedProminent)
                            .tint(VecklyDesign.Colors.hearthOrange)
                    }
                }
            } else {
                List(filtered) { recipe in
                    NavigationLink {
                        if let household = appModel.householdStore.activeHousehold {
                            RecipeDetailView(recipe: WeekSummaryRecipe(fullRecipe: recipe), householdID: household.id)
                        } else {
                            EmptyView()
                        }
                    } label: {
                        RecipeListRow(recipe: recipe)
                    }
                        .swipeActions(edge: .trailing) {
                            Button("Edit") { editingRecipe = recipe }
                                .tint(VecklyDesign.Colors.hearthOrange)
                            Button("Archive", role: .destructive) { archiveCandidate = recipe }
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
        .confirmationDialog(
            "Archive this recipe?",
            isPresented: Binding(
                get: { archiveCandidate != nil },
                set: { if !$0 { archiveCandidate = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Archive", role: .destructive) {
                guard let recipe = archiveCandidate,
                      let household = appModel.householdStore.activeHousehold else { return }
                archiveCandidate = nil
                Task {
                    do {
                        try await appModel.recipeStore.archiveRecipe(householdID: household.id, recipeID: recipe.id)
                    } catch {
                        transientErrorMessage = appModel.recipeStore.errorMessage ?? "Could not archive recipe."
                    }
                }
            }
            Button("Cancel", role: .cancel) { archiveCandidate = nil }
        }
        .alert("Error", isPresented: Binding(
            get: { transientErrorMessage != nil },
            set: { if !$0 { transientErrorMessage = nil } }
        )) {
            Button("OK") { transientErrorMessage = nil }
        } message: {
            Text(transientErrorMessage ?? "")
        }
        .task(id: appModel.householdStore.activeHousehold?.id) {
            guard let household = appModel.householdStore.activeHousehold else { return }
            await appModel.recipeStore.loadRecipes(householdID: household.id)
        }
    }

    private var searchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
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

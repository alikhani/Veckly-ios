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
                LoadingPanel(title: L10n.string("recipes.loading"))
                    .padding()
            } else if let errorMessage = appModel.recipeStore.errorMessage, appModel.recipeStore.recipes.isEmpty {
                ContentUnavailableView {
                    Label("recipes.loadFailed", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("common.tryAgain") {
                        guard let household = appModel.householdStore.activeHousehold else { return }
                        Task { await appModel.recipeStore.loadRecipes(householdID: household.id) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(VecklyDesign.Colors.hearthOrange)
                }
            } else if filtered.isEmpty {
                ContentUnavailableView {
                    Label(searchQuery.isEmpty ? L10n.string("recipes.empty.title") : L10n.string("recipes.noResults"), systemImage: "fork.knife")
                } description: {
                    Text(searchQuery.isEmpty ? L10n.string("recipes.empty.message") : L10n.string("recipes.tryDifferentSearch"))
                } actions: {
                    if searchQuery.isEmpty {
                        Button("recipe.add") { showAddSheet = true }
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
                            Button("common.edit") { editingRecipe = recipe }
                                .tint(VecklyDesign.Colors.hearthOrange)
                            Button("recipes.archive", role: .destructive) { archiveCandidate = recipe }
                        }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(L10n.string("tabs.recipes"))
        .searchable(text: $searchText, prompt: L10n.string("recipes.search"))
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
            L10n.string("recipes.archiveConfirmation"),
            isPresented: Binding(
                get: { archiveCandidate != nil },
                set: { if !$0 { archiveCandidate = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("recipes.archive", role: .destructive) {
                guard let recipe = archiveCandidate,
                      let household = appModel.householdStore.activeHousehold else { return }
                archiveCandidate = nil
                Task {
                    do {
                        try await appModel.recipeStore.archiveRecipe(householdID: household.id, recipeID: recipe.id)
                    } catch {
                        transientErrorMessage = appModel.recipeStore.errorMessage ?? L10n.string("error.recipes.archive")
                    }
                }
            }
            Button("common.cancel", role: .cancel) { archiveCandidate = nil }
        }
        .alert(L10n.string("common.error"), isPresented: Binding(
            get: { transientErrorMessage != nil },
            set: { if !$0 { transientErrorMessage = nil } }
        )) {
            Button("common.ok") { transientErrorMessage = nil }
        } message: {
            Text(transientErrorMessage ?? "")
        }
        .task(id: appModel.householdStore.activeHousehold?.id) {
            guard let household = appModel.householdStore.activeHousehold else { return }
            await appModel.loadRecipesAndSeedFeedback(householdID: household.id)
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
                Text(L10n.format("format.servings", recipe.servings))
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

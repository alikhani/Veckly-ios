import SwiftUI

struct RecipesTabView: View {
    @Environment(AppModel.self) private var appModel
    @State private var searchText = ""
    @State private var showAddSheet = false
    @State private var editingRecipe: FullRecipe?
    @State private var archiveCandidate: FullRecipe?
    @State private var transientErrorMessage: String?
    @State private var isArchiving = false

    private var filtered: [FullRecipe] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return appModel.recipeStore.recipes }
        return appModel.recipeStore.recipes.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.description.localizedCaseInsensitiveContains(query)
                || $0.tags.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    /// Recipes the household created, imported, or generated with AI — kept
    /// separate from the stock library below so a flat list of dozens of
    /// built-in recipes doesn't bury what the household actually added.
    private var householdRecipes: [FullRecipe] {
        filtered.filter { !$0.isBuiltIn }
    }

    private var builtInRecipes: [FullRecipe] {
        filtered.filter(\.isBuiltIn)
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
                    .tint(VecklyDesign.Colors.hearthOrangePrimaryFill)
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
                            .tint(VecklyDesign.Colors.hearthOrangePrimaryFill)
                    }
                }
            } else {
                List {
                    if let errorMessage = appModel.recipeStore.errorMessage, !appModel.recipeStore.recipes.isEmpty {
                        Section {
                            HStack(spacing: 10) {
                                Text(errorMessage)
                                    .font(.subheadline)
                                    .foregroundStyle(VecklyDesign.Colors.inkDeep)
                                Spacer()
                                Button {
                                    appModel.recipeStore.clearErrorMessage()
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(VecklyDesign.Colors.inkMid)
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .accessibilityLabel(L10n.string("common.dismissError"))
                            }
                            .padding(12)
                            .background(VecklyDesign.Colors.surfaceStrong)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 0, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    if !householdRecipes.isEmpty {
                        Section(L10n.string("recipes.yourRecipes")) {
                            ForEach(householdRecipes) { recipe in
                                recipeRow(recipe)
                            }
                        }
                    }
                    if !builtInRecipes.isEmpty {
                        Section(L10n.string("recipes.builtInRecipes")) {
                            ForEach(builtInRecipes) { recipe in
                                recipeRow(recipe)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable {
                    guard let household = appModel.householdStore.activeHousehold else { return }
                    appModel.recipeStore.invalidateCache()
                    await appModel.recipeStore.loadRecipes(householdID: household.id)
                }
            }
        }
        // Reuses the household link's own label (Fas E) — the destination's
        // title must match what the user just tapped, or the household →
        // recipes context gets lost mid-navigation.
        .navigationTitle(L10n.string("household.familyRecipesLink"))
        .modifier(SearchableWhenLibraryHasRecipesModifier(hasRecipes: !appModel.recipeStore.recipes.isEmpty, searchText: $searchText))
        .toolbar {
            if !appModel.recipeStore.recipes.isEmpty {
                Button { showAddSheet = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel(L10n.string("recipe.add"))
            }
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
                    guard !isArchiving else { return }
                    isArchiving = true
                    defer { isArchiving = false }
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

    private func recipeRow(_ recipe: FullRecipe) -> some View {
        NavigationLink {
            if let household = appModel.householdStore.activeHousehold {
                RecipeDetailView(recipe: WeekSummaryRecipe(fullRecipe: recipe), householdID: household.id)
            } else {
                EmptyView()
            }
        } label: {
            RecipeListRow(
                recipe: recipe,
                isLiked: appModel.feedbackStore.vote(for: recipe.id) == .up,
                isBookmarked: appModel.householdSavedRecipesStore.isAdded(recipe.id)
            )
        }
        .disabled(appModel.householdStore.activeHousehold == nil)
        .swipeActions(edge: .trailing) {
            // Built-in recipes aren't owned by this household — the backend
            // scopes updates/archiving to `recipes.householdId`, which
            // built-ins don't have, so these actions would silently no-op.
            if !recipe.isBuiltIn {
                Button("common.edit") { editingRecipe = recipe }
                    .tint(VecklyDesign.Colors.hearthOrangePrimaryFill)
                Button("recipes.archive", role: .destructive) {
                    guard !isArchiving else { return }
                    archiveCandidate = recipe
                }
            }
        }
    }
}

/// `.searchable` only once the household's real library has at least one
/// recipe — an empty library has nothing to search, so the field would be a
/// dead control next to the "Add recipe" CTA. Once the library has recipes,
/// the field stays even if an individual search happens to match nothing
/// (the user may want to try a different term).
private struct SearchableWhenLibraryHasRecipesModifier: ViewModifier {
    let hasRecipes: Bool
    @Binding var searchText: String

    func body(content: Content) -> some View {
        if hasRecipes {
            content.searchable(text: $searchText, prompt: L10n.string("recipes.search"))
        } else {
            content
        }
    }
}

private struct RecipeListRow: View {
    let recipe: FullRecipe
    var isLiked: Bool = false
    var isBookmarked: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(recipe.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(VecklyDesign.Colors.inkDeep)
                if isLiked {
                    Image(systemName: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(VecklyDesign.Colors.hearthOrangeFill)
                        .accessibilityLabel(L10n.string("recipes.liked"))
                }
                if isBookmarked {
                    Image(systemName: "bookmark.fill")
                        .font(.caption)
                        .foregroundStyle(VecklyDesign.Colors.inkMid)
                        .accessibilityLabel(L10n.string("recipes.bookmarked"))
                }
            }
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

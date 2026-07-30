import SwiftUI

struct CookbookView: View {
    let householdID: String

    @Environment(AppModel.self) private var appModel
    @State private var searchText = ""
    @State private var removalCandidate: FamilyCookbook.Recipe?
    @State private var errorMessage: String?
    @State private var isRemoving = false

    private var cookbook: FamilyCookbook? {
        appModel.familyCookbookStore.cookbook(for: householdID)
    }

    private var favorites: [FamilyCookbook.Recipe] {
        filtered(cookbook?.uniqueFavorites ?? [])
    }

    private var dueAgain: [FamilyCookbook.Recipe] {
        filtered(cookbook?.uniqueDueAgain ?? [])
    }

    private var normalizedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Group {
            if cookbook == nil {
                LoadingPanel(title: L10n.string("household.cookbook.loading"))
            } else if favorites.isEmpty, dueAgain.isEmpty {
                ContentUnavailableView {
                    Label(
                        normalizedSearch.isEmpty
                            ? L10n.string("household.cookbook.empty")
                            : L10n.string("recipes.noResults"),
                        systemImage: "books.vertical"
                    )
                } description: {
                    if !normalizedSearch.isEmpty {
                        Text("recipes.tryDifferentSearch")
                    }
                }
            } else {
                List {
                    if !favorites.isEmpty {
                        Section("household.cookbook.favorites") {
                            ForEach(favorites) { recipe in
                                recipeRow(
                                    recipe,
                                    detail: recipe.timesCooked == 0
                                        ? L10n.string("household.cookbook.notCookedYet")
                                        : L10n.format("household.cookbook.timesCooked", recipe.timesCooked)
                                )
                            }
                        }
                    }
                    if !dueAgain.isEmpty {
                        Section("household.cookbook.dueAgainSection") {
                            ForEach(dueAgain) { recipe in
                                recipeRow(recipe, detail: L10n.string("household.cookbook.dueAgain"))
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(L10n.string("household.cookbook.navigationTitle"))
        .searchable(text: $searchText, prompt: L10n.string("recipes.search"))
        .task {
            await appModel.familyCookbookStore.loadIfNeeded(householdID: householdID)
        }
        .confirmationDialog(
            L10n.string("household.cookbook.removeConfirmation"),
            isPresented: Binding(
                get: { removalCandidate != nil },
                set: { if !$0 { removalCandidate = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("household.cookbook.remove", role: .destructive) {
                guard let recipe = removalCandidate else { return }
                removalCandidate = nil
                Task { await remove(recipe) }
            }
            Button("common.cancel", role: .cancel) {
                removalCandidate = nil
            }
        }
        .standardErrorAlert(message: $errorMessage)
    }

    private func filtered(_ recipes: [FamilyCookbook.Recipe]) -> [FamilyCookbook.Recipe] {
        guard !normalizedSearch.isEmpty else { return recipes }
        return recipes.filter { $0.title.localizedCaseInsensitiveContains(normalizedSearch) }
    }

    private func recipeRow(_ recipe: FamilyCookbook.Recipe, detail: String) -> some View {
        NavigationLink {
            CookbookRecipeDetailView(recipeID: recipe.recipeID, householdID: householdID)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(recipe.title)
                    .foregroundStyle(VecklyDesign.Colors.inkDeep)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(VecklyDesign.Colors.inkFaint)
            }
            .padding(.vertical, 3)
        }
        .accessibilityLabel("\(recipe.title), \(detail)")
        .accessibilityHint(L10n.string("household.cookbook.openRecipeHint"))
        .swipeActions(edge: .trailing) {
            Button("household.cookbook.remove", role: .destructive) {
                removalCandidate = recipe
            }
        }
        .contextMenu {
            Button("household.cookbook.remove", role: .destructive) {
                removalCandidate = recipe
            }
        }
    }

    private func remove(_ recipe: FamilyCookbook.Recipe) async {
        guard !isRemoving else { return }
        isRemoving = true
        defer { isRemoving = false }

        let succeeded = await appModel.feedbackStore.setVote(
            householdID: householdID,
            recipeID: recipe.recipeID,
            vote: nil
        )
        if succeeded {
            appModel.familyCookbookStore.removeRecipe(recipe.recipeID, householdID: householdID)
        } else {
            errorMessage = L10n.string("household.cookbook.removeFailed")
        }
    }
}

struct CookbookRecipeDetailView: View {
    let recipeID: String
    let householdID: String

    @Environment(AppModel.self) private var appModel
    @State private var recipe: FullRecipe?
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let recipe {
                RecipeDetailView(recipe: WeekSummaryRecipe(fullRecipe: recipe), householdID: householdID)
            } else if loadFailed {
                ContentUnavailableView {
                    Label("recipes.detailLoadFailed", systemImage: "exclamationmark.triangle")
                } actions: {
                    Button("common.tryAgain") {
                        loadFailed = false
                        Task { await loadRecipe() }
                    }
                }
            } else {
                LoadingPanel(title: L10n.string("recipes.loading"))
            }
        }
        .task(id: recipeID) {
            await loadRecipe()
        }
    }

    private func loadRecipe() async {
        do {
            recipe = try await appModel.recipeStore.getOrFetchFull(
                householdID: householdID,
                recipeID: recipeID
            )
        } catch {
            loadFailed = true
        }
    }
}

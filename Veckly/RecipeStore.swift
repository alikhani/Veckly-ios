import Foundation
import Observation

@MainActor
@Observable
final class RecipeStore {
    private let apiClient: any RecipeStoreAPIClient

    private(set) var recipes: [FullRecipe] = []
    private(set) var isLoading = false
    var errorMessage: String?
    private(set) var lastFetchedAt: Date?
    private(set) var recipesHouseholdID: String?
    private var fullRecipeCache: [String: FullRecipe] = [:]

    init(apiClient: any RecipeStoreAPIClient) {
        self.apiClient = apiClient
    }

    func loadRecipes(householdID: String) async {
        if recipesHouseholdID != householdID {
            clearRecipeState()
            recipesHouseholdID = householdID
        }

        let cacheIsFresh = lastFetchedAt.map { Date().timeIntervalSince($0) <= 300 } == true && !recipes.isEmpty
        guard !cacheIsFresh else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let fetched = try await apiClient.listHouseholdRecipes(householdID: householdID, includePublic: true)
            recipes = fetched
            fullRecipeCache = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
            recipesHouseholdID = householdID
            lastFetchedAt = Date()
        } catch {
            errorMessage = L10n.string("error.recipes.load")
        }
    }

    func getOrFetchFull(householdID: String, recipeID: String) async throws -> FullRecipe {
        if let cached = fullRecipeCache[recipeID] { return cached }
        let full = try await apiClient.recipe(householdID: householdID, recipeID: recipeID)
        fullRecipeCache[recipeID] = full
        return full
    }

    func createRecipe(householdID: String, draft: RecipeDraft) async throws -> FullRecipe {
        let created = try await apiClient.createRecipe(householdID: householdID, draft: draft)
        if recipesHouseholdID != householdID {
            clearRecipeState()
            recipesHouseholdID = householdID
        }
        recipes.insert(created, at: 0)
        fullRecipeCache[created.id] = created
        return created
    }

    func updateRecipe(householdID: String, recipeID: String, draft: RecipeDraft) async throws {
        let updated = try await apiClient.updateRecipe(householdID: householdID, recipeID: recipeID, draft: draft)
        if let idx = recipes.firstIndex(where: { $0.id == recipeID }) {
            recipes[idx] = updated
        }
        fullRecipeCache[recipeID] = updated
    }

    func archiveRecipe(householdID: String, recipeID: String) async throws {
        let previousRecipes = recipes
        recipes.removeAll { $0.id == recipeID }
        fullRecipeCache[recipeID] = nil

        do {
            _ = try await apiClient.archiveRecipe(householdID: householdID, recipeID: recipeID)
        } catch {
            recipes = previousRecipes
            if let previous = previousRecipes.first(where: { $0.id == recipeID }) {
                fullRecipeCache[recipeID] = previous
            }
            errorMessage = L10n.string("error.recipes.archive")
            throw error
        }
    }

    func fillIn(draft: RecipeDraft) async throws -> RecipeDraft {
        try await apiClient.fillInRecipe(
            title: draft.title,
            existingIngredients: draft.ingredients.filter { !$0.item.isEmpty },
            existingSteps: draft.steps.filter { !$0.isEmpty }
        )
    }

    func importFromURL(_ urlString: String) async throws -> RecipeDraft {
        try await apiClient.importRecipeFromURL(urlString)
    }

    func importFromText(_ text: String, sourceURL: String?) async throws -> RecipeDraft {
        try await apiClient.importRecipeFromText(text, sourceURL: sourceURL)
    }

    func reset() {
        clearRecipeState()
    }

    private func clearRecipeState() {
        recipes = []
        errorMessage = nil
        isLoading = false
        lastFetchedAt = nil
        recipesHouseholdID = nil
        fullRecipeCache = [:]
    }
}

protocol RecipeStoreAPIClient {
    func listHouseholdRecipes(householdID: String, includePublic: Bool) async throws -> [FullRecipe]
    func recipe(householdID: String, recipeID: String) async throws -> FullRecipe
    func createRecipe(householdID: String, draft: RecipeDraft) async throws -> FullRecipe
    func updateRecipe(householdID: String, recipeID: String, draft: RecipeDraft) async throws -> FullRecipe
    func archiveRecipe(householdID: String, recipeID: String) async throws -> FullRecipe
    func fillInRecipe(title: String, existingIngredients: [DraftIngredient], existingSteps: [String]) async throws -> RecipeDraft
    func importRecipeFromURL(_ urlString: String) async throws -> RecipeDraft
    func importRecipeFromText(_ text: String, sourceURL: String?) async throws -> RecipeDraft
}

extension VecklyAPIClient: RecipeStoreAPIClient {}

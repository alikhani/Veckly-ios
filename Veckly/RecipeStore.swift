import Foundation
import Observation

@MainActor
@Observable
final class RecipeStore {
    private let apiClient: VecklyAPIClient

    private(set) var recipes: [FullRecipe] = []
    private(set) var isLoading = false
    var errorMessage: String?
    private(set) var lastFetchedAt: Date?
    private var fullRecipeCache: [String: FullRecipe] = [:]

    init(apiClient: VecklyAPIClient) {
        self.apiClient = apiClient
    }

    func loadRecipes(householdID: String) async {
        guard lastFetchedAt == nil || Date().timeIntervalSince(lastFetchedAt!) > 300 || recipes.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let fetched = (try? await apiClient.listHouseholdRecipes(householdID: householdID)) ?? []
        recipes = fetched
        for recipe in fetched {
            fullRecipeCache[recipe.id] = recipe
        }
        lastFetchedAt = Date()
    }

    func getOrFetchFull(householdID: String, recipeID: String) async throws -> FullRecipe {
        if let cached = fullRecipeCache[recipeID] { return cached }
        let full = try await apiClient.recipe(householdID: householdID, recipeID: recipeID)
        fullRecipeCache[recipeID] = full
        return full
    }

    func createRecipe(householdID: String, draft: RecipeDraft) async throws -> FullRecipe {
        let created = try await apiClient.createRecipe(householdID: householdID, draft: draft)
        recipes.insert(created, at: 0)
        return created
    }

    func updateRecipe(householdID: String, recipeID: String, draft: RecipeDraft) async throws {
        let updated = try await apiClient.updateRecipe(householdID: householdID, recipeID: recipeID, draft: draft)
        if let idx = recipes.firstIndex(where: { $0.id == recipeID }) {
            recipes[idx] = updated
        }
    }

    func fillIn(title: String) async throws -> RecipeDraft {
        try await apiClient.fillInRecipe(title: title)
    }

    func importFromURL(_ urlString: String) async throws -> RecipeDraft {
        try await apiClient.importRecipeFromURL(urlString)
    }

    func reset() {
        recipes = []
        errorMessage = nil
        isLoading = false
        lastFetchedAt = nil
        fullRecipeCache = [:]
    }
}

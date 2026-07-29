import Foundation
import Observation

@MainActor
@Observable
final class RecipeStore {
    nonisolated private static let defaultCacheTTL: TimeInterval = 60 * 60 * 24

    private let apiClient: any RecipeStoreAPIClient
    private let cacheTTL: TimeInterval
    private let cacheStore: any RecipeStoreCachePersisting

    private(set) var recipes: [FullRecipe] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var lastFetchedAt: Date?
    private(set) var recipesHouseholdID: String?
    private var fullRecipeCache: [String: FullRecipe] = [:]

    init(
        apiClient: any RecipeStoreAPIClient,
        cacheTTL: TimeInterval = RecipeStore.defaultCacheTTL,
        cacheStore: any RecipeStoreCachePersisting = RecipeStoreDiskCache()
    ) {
        self.apiClient = apiClient
        self.cacheTTL = cacheTTL
        self.cacheStore = cacheStore
    }

    /// `force` bypasses the freshness cache below — see the identical
    /// parameter on `WeekStore.loadCurrentWeek` for why `AppRefreshCoordinator`
    /// needs it for forcing triggers (pull-to-refresh, household switch).
    func loadRecipes(householdID: String, force: Bool = false) async {
        if recipesHouseholdID != householdID {
            clearRecipeState()
            recipesHouseholdID = householdID
        }

        restorePersistedCacheIfNeeded(householdID: householdID)

        let cacheIsFresh = !force
            && lastFetchedAt.map { Date().timeIntervalSince($0) <= cacheTTL } == true
            && !recipes.isEmpty
        guard !cacheIsFresh else { return }

        isLoading = recipes.isEmpty
        errorMessage = nil
        defer { isLoading = false }

        do {
            var fetched = try await apiClient.listHouseholdRecipes(householdID: householdID, includePublic: true)
            if fetched.needsIngredientCategoryRepair {
                do {
                    let repair = try await apiClient.repairIngredientCategories(householdID: householdID)
                    if repair.recipesUpdated > 0 {
                        fetched = try await apiClient.listHouseholdRecipes(householdID: householdID, includePublic: true)
                    }
                } catch {
                    // Repair is a compatibility cleanup for legacy imports; recipe loading should still succeed.
                }
            }
            recipes = fetched
            fullRecipeCache = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
            recipesHouseholdID = householdID
            lastFetchedAt = Date()
            persistCurrentCache(householdID: householdID)
        } catch {
            errorMessage = L10n.string("error.recipes.load")
        }
    }

    func getOrFetchFull(householdID: String, recipeID: String) async throws -> FullRecipe {
        restorePersistedCacheIfNeeded(householdID: householdID)
        if let cached = fullRecipeCache[recipeID] { return cached }
        let full = try await apiClient.recipe(householdID: householdID, recipeID: recipeID)
        fullRecipeCache[recipeID] = full
        upsertRecipe(full, householdID: householdID)
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
        lastFetchedAt = Date()
        persistCurrentCache(householdID: householdID)
        return created
    }

    @discardableResult
    func updateRecipe(householdID: String, recipeID: String, draft: RecipeDraft) async throws -> FullRecipe {
        let updated = try await apiClient.updateRecipe(householdID: householdID, recipeID: recipeID, draft: draft)
        if let idx = recipes.firstIndex(where: { $0.id == recipeID }) {
            recipes[idx] = updated
        }
        fullRecipeCache[recipeID] = updated
        lastFetchedAt = Date()
        persistCurrentCache(householdID: householdID)
        return updated
    }

    func archiveRecipe(householdID: String, recipeID: String) async throws {
        let previousRecipes = recipes
        recipes.removeAll { $0.id == recipeID }
        fullRecipeCache[recipeID] = nil

        do {
            _ = try await apiClient.archiveRecipe(householdID: householdID, recipeID: recipeID)
            lastFetchedAt = Date()
            persistCurrentCache(householdID: householdID)
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
            existingSteps: draft.steps.map(\.text).filter { !$0.isEmpty }
        )
    }

    func importFromURL(_ urlString: String) async throws -> RecipeDraft {
        try await apiClient.importRecipeFromURL(urlString)
    }

    func importFromText(_ text: String, sourceURL: String?) async throws -> RecipeDraft {
        try await apiClient.importRecipeFromText(text, sourceURL: sourceURL)
    }

    func invalidateCache() {
        lastFetchedAt = nil
    }

    func clearErrorMessage() {
        errorMessage = nil
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

    private func restorePersistedCacheIfNeeded(householdID: String) {
        guard recipes.isEmpty else { return }
        guard let cached = cacheStore.loadRecipes(householdID: householdID) else { return }
        let restoredRecipes = cached.recipes.map(\.fullRecipe)
        recipes = restoredRecipes
        fullRecipeCache = Dictionary(uniqueKeysWithValues: restoredRecipes.map { ($0.id, $0) })
        recipesHouseholdID = householdID
        lastFetchedAt = cached.fetchedAt
    }

    private func persistCurrentCache(householdID: String) {
        guard !recipes.isEmpty else {
            cacheStore.deleteRecipes(householdID: householdID)
            return
        }

        cacheStore.saveRecipes(
            PersistedRecipeCache(
                householdID: householdID,
                fetchedAt: lastFetchedAt ?? Date(),
                recipes: recipes.map(PersistedRecipe.init)
            )
        )
    }

    private func upsertRecipe(_ recipe: FullRecipe, householdID: String) {
        if let idx = recipes.firstIndex(where: { $0.id == recipe.id }) {
            recipes[idx] = recipe
        } else {
            recipes.insert(recipe, at: 0)
        }
        recipesHouseholdID = householdID
        lastFetchedAt = Date()
        persistCurrentCache(householdID: householdID)
    }
}

struct PersistedRecipeCache: Codable {
    let householdID: String
    let fetchedAt: Date
    let recipes: [PersistedRecipe]
}

struct PersistedRecipe: Codable {
    let id: String
    let title: String
    let description: String
    let servings: Int
    let prepTimeMinutes: Int?
    let cookTimeMinutes: Int?
    let tags: [String]
    let ingredients: [PersistedRecipeIngredient]
    let steps: [PersistedRecipeStep]
    let userVote: String?
    let cuisine: String?
    var source: RecipeSource = .builtin
}

struct PersistedRecipeIngredient: Codable {
    let item: String
    let amount: String?
    let unit: String?
    let category: String?
}

struct PersistedRecipeStep: Codable {
    let text: String
}

protocol RecipeStoreCachePersisting {
    func loadRecipes(householdID: String) -> PersistedRecipeCache?
    func saveRecipes(_ cache: PersistedRecipeCache)
    func deleteRecipes(householdID: String)
}

struct RecipeStoreDiskCache: RecipeStoreCachePersisting {
    private let fileManager: FileManager = .default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func loadRecipes(householdID: String) -> PersistedRecipeCache? {
        let url = cacheURL(for: householdID)
        guard let data = try? Data(contentsOf: url),
              let cache = try? decoder.decode(PersistedRecipeCache.self, from: data) else {
            return nil
        }
        return cache.householdID == householdID ? cache : nil
    }

    func saveRecipes(_ cache: PersistedRecipeCache) {
        let url = cacheURL(for: cache.householdID)
        let directory = url.deletingLastPathComponent()
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? encoder.encode(cache) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    func deleteRecipes(householdID: String) {
        try? fileManager.removeItem(at: cacheURL(for: householdID))
    }

    private func cacheURL(for householdID: String) -> URL {
        let baseDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return baseDirectory
            .appendingPathComponent("Veckly", isDirectory: true)
            .appendingPathComponent("recipes-\(householdID).json")
    }
}

protocol RecipeStoreAPIClient {
    func listHouseholdRecipes(householdID: String, includePublic: Bool) async throws -> [FullRecipe]
    func recipe(householdID: String, recipeID: String) async throws -> FullRecipe
    func createRecipe(householdID: String, draft: RecipeDraft) async throws -> FullRecipe
    func updateRecipe(householdID: String, recipeID: String, draft: RecipeDraft) async throws -> FullRecipe
    func archiveRecipe(householdID: String, recipeID: String) async throws -> FullRecipe
    func repairIngredientCategories(householdID: String) async throws -> RecipeCategoryRepairResult
    func fillInRecipe(title: String, existingIngredients: [DraftIngredient], existingSteps: [String]) async throws -> RecipeDraft
    func importRecipeFromURL(_ urlString: String) async throws -> RecipeDraft
    func importRecipeFromText(_ text: String, sourceURL: String?) async throws -> RecipeDraft
}

extension VecklyAPIClient: RecipeStoreAPIClient {}

struct RecipeCategoryRepairResult: Equatable {
    let recipesUpdated: Int
    let ingredientsUpdated: Int
}

private extension Array where Element == FullRecipe {
    var needsIngredientCategoryRepair: Bool {
        contains { recipe in
            recipe.ingredients.contains { ingredient in
                let category = ingredient.category?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return category == nil || category?.isEmpty == true || category == "other"
            }
        }
    }
}

extension PersistedRecipe {
    init(fullRecipe: FullRecipe) {
        self.init(
            id: fullRecipe.id,
            title: fullRecipe.title,
            description: fullRecipe.description,
            servings: fullRecipe.servings,
            prepTimeMinutes: fullRecipe.prepTimeMinutes,
            cookTimeMinutes: fullRecipe.cookTimeMinutes,
            tags: fullRecipe.tags,
            ingredients: fullRecipe.ingredients.map(PersistedRecipeIngredient.init),
            steps: fullRecipe.steps.map(PersistedRecipeStep.init),
            userVote: fullRecipe.userVote,
            cuisine: fullRecipe.cuisine,
            source: fullRecipe.source
        )
    }

    var fullRecipe: FullRecipe {
        FullRecipe(
            id: id,
            title: title,
            description: description,
            servings: servings,
            prepTimeMinutes: prepTimeMinutes,
            cookTimeMinutes: cookTimeMinutes,
            tags: tags,
            ingredients: ingredients.map(\.recipeIngredient),
            steps: steps.map(\.recipeStep),
            userVote: userVote,
            cuisine: cuisine,
            source: source
        )
    }
}

extension PersistedRecipeIngredient {
    init(_ ingredient: RecipeIngredient) {
        self.init(
            item: ingredient.item,
            amount: ingredient.amount,
            unit: ingredient.unit,
            category: ingredient.category
        )
    }

    var recipeIngredient: RecipeIngredient {
        RecipeIngredient(item: item, amount: amount, unit: unit, category: category)
    }
}

extension PersistedRecipeStep {
    init(_ step: RecipeStep) {
        self.init(text: step.text)
    }

    var recipeStep: RecipeStep {
        RecipeStep(text: text)
    }
}

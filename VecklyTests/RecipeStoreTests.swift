import Foundation
import Testing
@testable import Veckly

@MainActor
struct RecipeStoreTests {
    @Test func recipesAreCachedPerHousehold() async {
        let apiClient = FakeRecipeStoreAPIClient()
        let store = RecipeStore(apiClient: apiClient)

        await store.loadRecipes(householdID: TestRecipeHouseholds.first)

        #expect(store.recipes == [TestRecipes.firstRecipe])
        #expect(store.recipesHouseholdID == TestRecipeHouseholds.first)

        await store.loadRecipes(householdID: TestRecipeHouseholds.second)

        #expect(store.recipes == [TestRecipes.secondRecipe])
        #expect(store.recipesHouseholdID == TestRecipeHouseholds.second)
    }

    @Test func failedLoadDoesNotCacheAnEmptyResult() async {
        let apiClient = FakeRecipeStoreAPIClient()
        apiClient.shouldFailList = true
        let store = RecipeStore(apiClient: apiClient)

        await store.loadRecipes(householdID: TestRecipeHouseholds.first)

        #expect(store.recipes.isEmpty)
        #expect(store.errorMessage != nil)
        #expect(store.lastFetchedAt == nil)

        apiClient.shouldFailList = false
        await store.loadRecipes(householdID: TestRecipeHouseholds.first)

        #expect(store.recipes == [TestRecipes.firstRecipe])
        #expect(store.errorMessage == nil)
        #expect(store.lastFetchedAt != nil)
    }

    @Test func createAndUpdateKeepFullRecipeCacheCurrent() async throws {
        let apiClient = FakeRecipeStoreAPIClient()
        let store = RecipeStore(apiClient: apiClient)

        let created = try await store.createRecipe(householdID: TestRecipeHouseholds.first, draft: TestRecipes.newDraft)
        let cachedCreated = try await store.getOrFetchFull(householdID: TestRecipeHouseholds.first, recipeID: created.id)

        #expect(cachedCreated.title == "New pasta")
        #expect(apiClient.recipeFetchCount == 0)

        var updatedDraft = TestRecipes.newDraft
        updatedDraft.title = "Updated pasta"
        try await store.updateRecipe(householdID: TestRecipeHouseholds.first, recipeID: created.id, draft: updatedDraft)

        let cachedUpdated = try await store.getOrFetchFull(householdID: TestRecipeHouseholds.first, recipeID: created.id)

        #expect(cachedUpdated.title == "Updated pasta")
        #expect(store.recipes.first?.title == "Updated pasta")
        #expect(apiClient.recipeFetchCount == 0)
    }

    @Test func archiveRemovesRecipeAndRollbackRestoresOnFailure() async throws {
        let apiClient = FakeRecipeStoreAPIClient()
        let store = RecipeStore(apiClient: apiClient)

        await store.loadRecipes(householdID: TestRecipeHouseholds.first)
        apiClient.shouldFailArchive = true

        do {
            try await store.archiveRecipe(householdID: TestRecipeHouseholds.first, recipeID: TestRecipes.firstRecipe.id)
            Issue.record("Expected archive to fail")
        } catch {}

        #expect(store.recipes == [TestRecipes.firstRecipe])
        #expect(store.errorMessage != nil)

        apiClient.shouldFailArchive = false
        try await store.archiveRecipe(householdID: TestRecipeHouseholds.first, recipeID: TestRecipes.firstRecipe.id)

        #expect(store.recipes.isEmpty)
    }
}

private enum TestRecipeHouseholds {
    static let first = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    static let second = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
}

private enum TestRecipes {
    static let firstRecipe = recipe(id: "11111111-1111-1111-1111-111111111111", title: "Monday stew")
    static let secondRecipe = recipe(id: "22222222-2222-2222-2222-222222222222", title: "Tuesday tacos")
    static let newDraft = RecipeDraft(
        title: "New pasta",
        description: "Fast pasta",
        servings: 4,
        prepTimeMinutes: 10,
        cookTimeMinutes: 15,
        ingredients: [DraftIngredient(item: "Pasta", amount: "400", unit: "g")],
        steps: ["Boil pasta"]
    )

    static func recipe(id: String, title: String) -> FullRecipe {
        FullRecipe(
            id: id,
            title: title,
            description: "A household dinner",
            servings: 4,
            prepTimeMinutes: 10,
            cookTimeMinutes: 20,
            tags: ["quick"],
            ingredients: [RecipeIngredient(item: "Carrot", amount: "2", unit: nil, category: nil)],
            steps: [RecipeStep(text: "Cook it")]
        )
    }

    static func recipe(id: String, draft: RecipeDraft) -> FullRecipe {
        FullRecipe(
            id: id,
            title: draft.title,
            description: draft.description,
            servings: draft.servings,
            prepTimeMinutes: draft.prepTimeMinutes,
            cookTimeMinutes: draft.cookTimeMinutes,
            tags: [],
            ingredients: draft.ingredients.map {
                RecipeIngredient(
                    item: $0.item,
                    amount: $0.amount.isEmpty ? nil : $0.amount,
                    unit: $0.unit.isEmpty ? nil : $0.unit,
                    category: nil
                )
            },
            steps: draft.steps.map { RecipeStep(text: $0) }
        )
    }
}

private enum TestRecipeError: Error {
    case failed
}

private final class FakeRecipeStoreAPIClient: RecipeStoreAPIClient {
    var shouldFailList = false
    var shouldFailArchive = false
    var recipeFetchCount = 0
    private var recipesByHousehold = [
        TestRecipeHouseholds.first: [TestRecipes.firstRecipe],
        TestRecipeHouseholds.second: [TestRecipes.secondRecipe]
    ]

    func listHouseholdRecipes(householdID: String, includePublic: Bool) async throws -> [FullRecipe] {
        if shouldFailList { throw TestRecipeError.failed }
        return recipesByHousehold[householdID] ?? []
    }

    func recipe(householdID: String, recipeID: String) async throws -> FullRecipe {
        recipeFetchCount += 1
        guard let recipe = recipesByHousehold[householdID]?.first(where: { $0.id == recipeID }) else {
            throw TestRecipeError.failed
        }
        return recipe
    }

    func createRecipe(householdID: String, draft: RecipeDraft) async throws -> FullRecipe {
        let recipe = TestRecipes.recipe(id: "33333333-3333-3333-3333-333333333333", draft: draft)
        recipesByHousehold[householdID, default: []].insert(recipe, at: 0)
        return recipe
    }

    func updateRecipe(householdID: String, recipeID: String, draft: RecipeDraft) async throws -> FullRecipe {
        let recipe = TestRecipes.recipe(id: recipeID, draft: draft)
        let index = recipesByHousehold[householdID]?.firstIndex(where: { $0.id == recipeID })
        if let index {
            recipesByHousehold[householdID]?[index] = recipe
        } else {
            recipesByHousehold[householdID, default: []].append(recipe)
        }
        return recipe
    }

    func archiveRecipe(householdID: String, recipeID: String) async throws -> FullRecipe {
        if shouldFailArchive { throw TestRecipeError.failed }
        guard let recipe = recipesByHousehold[householdID]?.first(where: { $0.id == recipeID }) else {
            throw TestRecipeError.failed
        }
        recipesByHousehold[householdID]?.removeAll { $0.id == recipeID }
        return recipe
    }

    func fillInRecipe(title: String) async throws -> RecipeDraft {
        RecipeDraft(title: title, description: "Filled")
    }

    func importRecipeFromURL(_ urlString: String) async throws -> RecipeDraft {
        RecipeDraft(title: "Imported", sourceUrl: urlString)
    }
}

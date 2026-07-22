import Foundation
import Testing
@testable import Veckly

@MainActor
struct HouseholdSavedRecipesStoreTests {
    @Test func addingMarksTheRecipeAsAddedOnSuccess() async {
        let client = StubHouseholdSavedRecipesAPIClient()
        let store = HouseholdSavedRecipesStore(apiClient: client)

        await store.setAdded(householdID: "household-1", recipeID: "recipe-1", added: true)

        #expect(store.isAdded("recipe-1"))
        #expect(client.addCallCount == 1)
    }

    @Test func addingRollsBackOnFailure() async {
        let client = StubHouseholdSavedRecipesAPIClient(addResult: .failure(APIError.server(statusCode: 500)))
        let store = HouseholdSavedRecipesStore(apiClient: client)

        await store.setAdded(householdID: "household-1", recipeID: "recipe-1", added: true)

        #expect(!store.isAdded("recipe-1"))
    }

    @Test func removingMarksTheRecipeAsNotAddedOnSuccess() async {
        let client = StubHouseholdSavedRecipesAPIClient()
        let store = HouseholdSavedRecipesStore(apiClient: client)

        await store.setAdded(householdID: "household-1", recipeID: "recipe-1", added: true)
        await store.setAdded(householdID: "household-1", recipeID: "recipe-1", added: false)

        #expect(!store.isAdded("recipe-1"))
        #expect(client.removeCallCount == 1)
    }

    @Test func removingRollsBackOnFailure() async {
        let client = StubHouseholdSavedRecipesAPIClient(removeResult: .failure(APIError.server(statusCode: 500)))
        let store = HouseholdSavedRecipesStore(apiClient: client)

        await store.setAdded(householdID: "household-1", recipeID: "recipe-1", added: true)
        await store.setAdded(householdID: "household-1", recipeID: "recipe-1", added: false)

        #expect(store.isAdded("recipe-1"))
    }

    @Test func settingTheSameStateAgainDoesNotCallTheAPI() async {
        let client = StubHouseholdSavedRecipesAPIClient()
        let store = HouseholdSavedRecipesStore(apiClient: client)

        await store.setAdded(householdID: "household-1", recipeID: "recipe-1", added: false)

        #expect(client.addCallCount == 0)
        #expect(client.removeCallCount == 0)
    }

    @Test func resetClearsAddedState() async {
        let client = StubHouseholdSavedRecipesAPIClient()
        let store = HouseholdSavedRecipesStore(apiClient: client)

        await store.setAdded(householdID: "household-1", recipeID: "recipe-1", added: true)
        store.reset()

        #expect(!store.isAdded("recipe-1"))
    }

    @Test func loadSavedRecipeIDsSeedsIsAddedFromAnEarlierSession() async {
        let client = StubHouseholdSavedRecipesAPIClient()
        client.savedRecipeIDs = ["recipe-1", "recipe-2"]
        let store = HouseholdSavedRecipesStore(apiClient: client)

        await store.loadSavedRecipeIDs(householdID: "household-1")

        #expect(store.isAdded("recipe-1"))
        #expect(store.isAdded("recipe-2"))
        #expect(!store.isAdded("recipe-3"))
    }
}

private final class StubHouseholdSavedRecipesAPIClient: HouseholdSavedRecipesAPIClient {
    let addResult: Result<Void, Error>
    let removeResult: Result<Void, Error>
    var savedRecipeIDs: [String] = []
    private(set) var addCallCount = 0
    private(set) var removeCallCount = 0

    init(addResult: Result<Void, Error> = .success(()), removeResult: Result<Void, Error> = .success(())) {
        self.addResult = addResult
        self.removeResult = removeResult
    }

    func listHouseholdSavedRecipeIDs(householdID: String) async throws -> [String] {
        savedRecipeIDs
    }

    func addHouseholdSavedRecipe(householdID: String, recipeID: String) async throws {
        addCallCount += 1
        try addResult.get()
    }

    func removeHouseholdSavedRecipe(householdID: String, recipeID: String) async throws {
        removeCallCount += 1
        try removeResult.get()
    }
}

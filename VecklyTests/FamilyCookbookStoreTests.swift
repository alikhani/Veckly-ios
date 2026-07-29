import Foundation
import Testing
@testable import Veckly

@MainActor
struct FamilyCookbookStoreTests {
    private func cookbook(count: Int = 1) -> FamilyCookbook {
        FamilyCookbook(
            totalFamilyLikedCount: count,
            favorites: [FamilyCookbook.Recipe(recipeID: "pasta", title: "Pasta", timesCooked: 3, weeksSinceCooked: 1)],
            dueAgain: []
        )
    }

    @Test func populatesCookbookOnSuccess() async {
        let client = StubFamilyCookbookAPIClient(result: .success(cookbook()))
        let store = FamilyCookbookStore(apiClient: client)

        await store.loadIfNeeded(householdID: "household-1")

        #expect(store.cookbook(for: "household-1") == cookbook())
    }

    @Test func cachesAnEmptyCookbookOnFailureInsteadOfThrowing() async {
        let client = StubFamilyCookbookAPIClient(result: .failure(APIError.server(statusCode: 500)))
        let store = FamilyCookbookStore(apiClient: client)

        await store.loadIfNeeded(householdID: "household-1")

        #expect(store.cookbook(for: "household-1") == FamilyCookbook(totalFamilyLikedCount: 0, favorites: [], dueAgain: []))
    }

    @Test func doesNotRetryAfterAFailureWithinTheSameSession() async {
        let client = StubFamilyCookbookAPIClient(result: .failure(APIError.server(statusCode: 500)))
        let store = FamilyCookbookStore(apiClient: client)

        await store.loadIfNeeded(householdID: "household-1")
        await store.loadIfNeeded(householdID: "household-1")

        #expect(client.callCount == 1)
    }

    @Test func onlyCallsTheAPIOnceForTheSameHouseholdWithinASession() async {
        let client = StubFamilyCookbookAPIClient(result: .success(cookbook()))
        let store = FamilyCookbookStore(apiClient: client)

        await store.loadIfNeeded(householdID: "household-1")
        await store.loadIfNeeded(householdID: "household-1")

        #expect(client.callCount == 1)
    }

    @Test func resetAllowsAFreshLoadForTheSameHousehold() async {
        let client = StubFamilyCookbookAPIClient(result: .success(cookbook()))
        let store = FamilyCookbookStore(apiClient: client)

        await store.loadIfNeeded(householdID: "household-1")
        store.reset()
        await store.loadIfNeeded(householdID: "household-1")

        #expect(client.callCount == 2)
    }

    @Test func uniqueRecipesKeepStableGroupOrderAndRemoveCrossGroupDuplicates() {
        let duplicate = FamilyCookbook.Recipe(recipeID: "pasta", title: "Pasta", timesCooked: 3, weeksSinceCooked: 8)
        let soup = FamilyCookbook.Recipe(recipeID: "soup", title: "Soup", timesCooked: 1, weeksSinceCooked: 7)
        let cookbook = FamilyCookbook(
            totalFamilyLikedCount: 2,
            favorites: [duplicate, duplicate],
            dueAgain: [duplicate, soup, soup]
        )

        #expect(cookbook.uniqueFavorites == [duplicate])
        #expect(cookbook.uniqueDueAgain == [soup])
        #expect(cookbook.uniqueRecipes == [duplicate, soup])
    }

    @Test func neverCookedFavoriteKeepsNullableWeekAge() {
        let neverCooked = FamilyCookbook.Recipe(
            recipeID: "new",
            title: "New favorite",
            timesCooked: 0,
            weeksSinceCooked: nil
        )
        let cookbook = FamilyCookbook(totalFamilyLikedCount: 1, favorites: [neverCooked], dueAgain: [])

        #expect(cookbook.uniqueFavorites == [neverCooked])
        #expect(cookbook.uniqueFavorites.first?.weeksSinceCooked == nil)
    }

    @Test func removingRecipeUpdatesCountAndBothGroupsImmediately() async {
        let removed = FamilyCookbook.Recipe(recipeID: "pasta", title: "Pasta", timesCooked: 3, weeksSinceCooked: 1)
        let remaining = FamilyCookbook.Recipe(recipeID: "soup", title: "Soup", timesCooked: 1, weeksSinceCooked: 8)
        let initial = FamilyCookbook(
            totalFamilyLikedCount: 2,
            favorites: [removed],
            dueAgain: [remaining]
        )
        let store = FamilyCookbookStore(apiClient: StubFamilyCookbookAPIClient(result: .success(initial)))
        await store.loadIfNeeded(householdID: "household-1")

        store.removeRecipe("pasta", householdID: "household-1")

        #expect(
            store.cookbook(for: "household-1")
                == FamilyCookbook(totalFamilyLikedCount: 1, favorites: [], dueAgain: [remaining])
        )
    }
}

private final class StubFamilyCookbookAPIClient: FamilyCookbookAPIClient {
    let result: Result<FamilyCookbook, Error>
    private(set) var callCount = 0

    init(result: Result<FamilyCookbook, Error>) {
        self.result = result
    }

    func familyCookbook(householdID: String, weekStartDate: String) async throws -> FamilyCookbook {
        callCount += 1
        return try result.get()
    }
}

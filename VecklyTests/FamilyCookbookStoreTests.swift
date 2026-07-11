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

    @Test func leavesCookbookNilOnFailureInsteadOfThrowing() async {
        let client = StubFamilyCookbookAPIClient(result: .failure(APIError.server(statusCode: 500)))
        let store = FamilyCookbookStore(apiClient: client)

        await store.loadIfNeeded(householdID: "household-1")

        #expect(store.cookbook(for: "household-1") == nil)
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

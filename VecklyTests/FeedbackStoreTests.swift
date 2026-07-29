import Foundation
import Testing
@testable import Veckly

@MainActor
struct FeedbackStoreTests {
    @Test func clearingVoteReturnsTrueAndKeepsVoteRemovedWhenAPISucceeds() async {
        let client = StubFeedbackStoreAPIClient()
        let store = FeedbackStore(apiClient: client)
        store.seedVote(for: "recipe-1", vote: .up)

        let succeeded = await store.setVote(
            householdID: "household-1",
            recipeID: "recipe-1",
            vote: nil
        )

        #expect(succeeded)
        #expect(store.vote(for: "recipe-1") == nil)
        #expect(client.removedMealIDs == ["recipe-1"])
    }

    @Test func clearingVoteReturnsFalseAndRestoresVoteWhenAPIFails() async {
        let client = StubFeedbackStoreAPIClient()
        client.removeError = APIError.server(statusCode: 500)
        let store = FeedbackStore(apiClient: client)
        store.seedVote(for: "recipe-1", vote: .up)

        let succeeded = await store.setVote(
            householdID: "household-1",
            recipeID: "recipe-1",
            vote: nil
        )

        #expect(!succeeded)
        #expect(store.vote(for: "recipe-1") == .up)
        #expect(client.removedMealIDs == ["recipe-1"])
    }
}

private final class StubFeedbackStoreAPIClient: FeedbackStoreAPIClient {
    var removeError: Error?
    private(set) var removedMealIDs: [String] = []

    func mealFeedback(householdID: String) async throws -> [String: MealVote] {
        [:]
    }

    func removeMealFeedback(householdID: String, mealID: String) async throws {
        removedMealIDs.append(mealID)
        if let removeError {
            throw removeError
        }
    }

    func submitMealFeedback(householdID: String, mealID: String, vote: MealVote) async throws {}
}

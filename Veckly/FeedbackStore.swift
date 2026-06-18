import Foundation
import Observation

@MainActor
@Observable
final class FeedbackStore {
    private let apiClient: VecklyAPIClient
    // recipeID → vote
    private var votes: [String: MealVote] = [:]

    init(apiClient: VecklyAPIClient) {
        self.apiClient = apiClient
    }

    func vote(for recipeID: String) -> MealVote? {
        votes[recipeID]
    }

    func voteString(for recipeID: String) -> String? {
        votes[recipeID]?.rawValue
    }

    func loadFeedback(householdID: String) async {
        guard let result = try? await apiClient.mealFeedback(householdID: householdID) else { return }
        votes = result
    }

    func setVote(householdID: String, recipeID: String, vote: MealVote?) async {
        let previous = votes[recipeID]
        // Optimistic update
        votes[recipeID] = vote
        guard let vote else {
            // No "remove vote" endpoint — skip the API call for nil
            return
        }
        do {
            try await apiClient.submitMealFeedback(householdID: householdID, mealID: recipeID, vote: vote)
        } catch {
            // Roll back on failure
            votes[recipeID] = previous
        }
    }

    func reset() {
        votes = [:]
    }
}

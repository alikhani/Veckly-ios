import Foundation
import Observation

protocol FeedbackStoreAPIClient {
    func mealFeedback(householdID: String) async throws -> [String: MealVote]
    func removeMealFeedback(householdID: String, mealID: String) async throws
    func submitMealFeedback(householdID: String, mealID: String, vote: MealVote) async throws
}

@MainActor
@Observable
final class FeedbackStore {
    private let apiClient: any FeedbackStoreAPIClient
    // recipeID → vote
    private var votes: [String: MealVote] = [:]
    private(set) var errorMessage: String?

    init(apiClient: any FeedbackStoreAPIClient) {
        self.apiClient = apiClient
    }

    func vote(for recipeID: String) -> MealVote? {
        votes[recipeID]
    }

    /// A snapshot of every recipe this household has voted on — used to build
    /// the `feedbackSummary` sent to `/recipes/recommend` (see
    /// `RecipeRecommendationStore`), which needs the full list, not a
    /// single-recipe lookup.
    var allVotes: [String: MealVote] {
        votes
    }

    func voteString(for recipeID: String) -> String? {
        votes[recipeID]?.rawValue
    }

    func loadFeedback(householdID: String) async {
        errorMessage = nil
        do {
            let result = try await apiClient.mealFeedback(householdID: householdID)
            votes = result
        } catch {
            errorMessage = L10n.string("error.feedback.load")
        }
    }

    @discardableResult
    func setVote(householdID: String, recipeID: String, vote: MealVote?) async -> Bool {
        let previous = votes[recipeID]
        // Optimistic update
        votes[recipeID] = vote
        guard let vote else {
            do {
                try await apiClient.removeMealFeedback(householdID: householdID, mealID: recipeID)
                return true
            } catch {
                // Roll back on failure
                votes[recipeID] = previous
                return false
            }
        }
        do {
            try await apiClient.submitMealFeedback(householdID: householdID, mealID: recipeID, vote: vote)
            return true
        } catch {
            // Roll back on failure
            votes[recipeID] = previous
            return false
        }
    }

    /// Seeds the vote for a recipe from its stored userVote field, but only
    /// if no value is already present (preserves a fresher optimistic update).
    func seedVote(for recipeID: String, vote: MealVote?) {
        if votes[recipeID] == nil, let vote {
            votes[recipeID] = vote
        }
    }

    func reset() {
        votes = [:]
        errorMessage = nil
    }
}

extension VecklyAPIClient: FeedbackStoreAPIClient {}

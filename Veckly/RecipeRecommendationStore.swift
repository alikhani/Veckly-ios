import Foundation
import Observation

protocol RecipeRecommendationAPIClient {
    func recommendMeals(
        householdProfile: HouseholdProfile,
        feedbackSummary: [MealRecommendationFeedbackItem],
        candidateMeals: [MealRecommendationCandidate]
    ) async throws -> [MealRecommendation]
}

extension VecklyAPIClient: RecipeRecommendationAPIClient {}

/// Backs the "Suggestions for you" section at the top of `MealPickerSheet`.
/// Session-scoped, in-memory only: one AI call per household per app launch
/// is the point (matches the backend's own 30s-per-user rate limit), not a
/// live-updating feed — see Plan B3 in `PLAN-veckoritual-familjeminne-2026-07.md`.
@MainActor
@Observable
final class RecipeRecommendationStore {
    private let apiClient: any RecipeRecommendationAPIClient
    private var recommendationsByHousehold: [String: [MealRecommendation]] = [:]
    private var loadingHouseholdIDs: Set<String> = []

    init(apiClient: any RecipeRecommendationAPIClient) {
        self.apiClient = apiClient
    }

    func recommendations(for householdID: String) -> [MealRecommendation] {
        recommendationsByHousehold[householdID] ?? []
    }

    /// Silent-fallback by design, per the plan doc ("Fallback: nuvarande
    /// lista"): any failure (rate limited, AI unavailable, invalid response)
    /// just leaves recommendations empty for the rest of the session — the
    /// picker's full recipe list is already right there below, so there's
    /// nothing else to show the user. Not retried automatically; a fresh app
    /// launch is what resets it.
    func loadIfNeeded(
        householdID: String,
        householdProfile: HouseholdProfile,
        feedbackVotes: [String: MealVote],
        recipes: [FullRecipe]
    ) async {
        guard recommendationsByHousehold[householdID] == nil, !loadingHouseholdIDs.contains(householdID) else { return }
        guard !recipes.isEmpty else { return }
        loadingHouseholdIDs.insert(householdID)
        defer { loadingHouseholdIDs.remove(householdID) }

        let titlesByID = Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, $0.title) })
        let feedbackSummary = feedbackVotes.compactMap { mealID, vote -> MealRecommendationFeedbackItem? in
            guard let title = titlesByID[mealID] else { return nil }
            return MealRecommendationFeedbackItem(mealID: mealID, mealTitle: title, vote: vote)
        }
        let candidates = recipes.map { MealRecommendationCandidate(id: $0.id, title: $0.title) }

        do {
            recommendationsByHousehold[householdID] = try await apiClient.recommendMeals(
                householdProfile: householdProfile,
                feedbackSummary: feedbackSummary,
                candidateMeals: candidates
            )
        } catch {
            recommendationsByHousehold[householdID] = []
        }
    }

    func reset() {
        recommendationsByHousehold = [:]
        loadingHouseholdIDs = []
    }
}

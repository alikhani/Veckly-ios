import Foundation
import Observation

protocol RecipeRecommendationAPIClient {
    func recommendMeals(
        householdID: String,
        householdProfile: HouseholdProfile,
        feedbackSummary: [MealRecommendationFeedbackItem],
        candidateMeals: [MealRecommendationCandidate]
    ) async throws -> [MealRecommendation]
}

extension VecklyAPIClient: RecipeRecommendationAPIClient {}

/// Backs the "Suggestions for you" section at the top of `MealPickerSheet`.
/// In-memory only on this client, but the backend now caches the actual AI
/// result per household (keyed by `householdID`, ~1 week TTL — see
/// `Veckly-backend/src/recipe-recommendations.ts`), so this in-memory guard
/// is about not re-requesting within one session, not the only thing
/// standing between the app and a fresh Claude call every launch.
@MainActor
@Observable
final class RecipeRecommendationStore {
    private let apiClient: any RecipeRecommendationAPIClient
    private let cache = PerHouseholdCache<[MealRecommendation]>()

    init(apiClient: any RecipeRecommendationAPIClient) {
        self.apiClient = apiClient
    }

    func recommendations(for householdID: String) -> [MealRecommendation] {
        cache.value(for: householdID) ?? []
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
        // Not ready to attempt yet — checked before the cache's own
        // de-dup guard, and deliberately not cached, so a later call once
        // recipes have loaded can still try.
        guard !recipes.isEmpty else { return }

        await cache.loadIfNeeded(householdID: householdID) {
            let titlesByID = Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, $0.title) })
            let feedbackSummary = feedbackVotes.compactMap { mealID, vote -> MealRecommendationFeedbackItem? in
                guard let title = titlesByID[mealID] else { return nil }
                return MealRecommendationFeedbackItem(mealID: mealID, mealTitle: title, vote: vote)
            }
            let candidates = recipes.map {
                MealRecommendationCandidate(
                    id: $0.id,
                    title: $0.title,
                    tags: $0.tags,
                    ingredients: $0.ingredients.map(\.item)
                )
            }

            do {
                return try await apiClient.recommendMeals(
                    householdID: householdID,
                    householdProfile: householdProfile,
                    feedbackSummary: feedbackSummary,
                    candidateMeals: candidates
                )
            } catch {
                return []
            }
        }
    }

    func reset() {
        cache.reset()
    }
}

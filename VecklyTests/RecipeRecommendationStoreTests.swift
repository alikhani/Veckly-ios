import Foundation
import Testing
@testable import Veckly

@MainActor
struct RecipeRecommendationStoreTests {
    private func profile(householdID: String = "household-1") -> HouseholdProfile {
        HouseholdProfile(householdId: householdID, adults: 2, children: 1, priorities: [.quick], avoidIngredients: [], selectedDays: [])
    }

    private func recipe(_ id: String, title: String) -> FullRecipe {
        FullRecipe(id: id, title: title, description: "", servings: 4, prepTimeMinutes: 10, cookTimeMinutes: 15, tags: [], ingredients: [], steps: [], userVote: nil)
    }

    @Test func populatesRecommendationsOnSuccess() async {
        let client = StubRecipeRecommendationAPIClient(result: .success([MealRecommendation(mealID: "pasta", reason: "A family favorite")]))
        let store = RecipeRecommendationStore(apiClient: client)

        await store.loadIfNeeded(householdID: "household-1", householdProfile: profile(), feedbackVotes: [:], recipes: [recipe("pasta", title: "Pasta")])

        #expect(store.recommendations(for: "household-1") == [MealRecommendation(mealID: "pasta", reason: "A family favorite")])
    }

    @Test func leavesRecommendationsEmptyOnFailureInsteadOfThrowing() async {
        let client = StubRecipeRecommendationAPIClient(result: .failure(APIError.server(statusCode: 429)))
        let store = RecipeRecommendationStore(apiClient: client)

        await store.loadIfNeeded(householdID: "household-1", householdProfile: profile(), feedbackVotes: [:], recipes: [recipe("pasta", title: "Pasta")])

        #expect(store.recommendations(for: "household-1") == [])
    }

    @Test func skipsTheCallEntirelyWhenThereAreNoCandidateRecipes() async {
        let client = StubRecipeRecommendationAPIClient(result: .success([MealRecommendation(mealID: "pasta", reason: "unused")]))
        let store = RecipeRecommendationStore(apiClient: client)

        await store.loadIfNeeded(householdID: "household-1", householdProfile: profile(), feedbackVotes: [:], recipes: [])

        #expect(client.callCount == 0)
        #expect(store.recommendations(for: "household-1") == [])
    }

    @Test func onlyCallsTheAPIOnceForTheSameHouseholdWithinASession() async {
        let client = StubRecipeRecommendationAPIClient(result: .success([MealRecommendation(mealID: "pasta", reason: "A family favorite")]))
        let store = RecipeRecommendationStore(apiClient: client)
        let recipes = [recipe("pasta", title: "Pasta")]

        await store.loadIfNeeded(householdID: "household-1", householdProfile: profile(), feedbackVotes: [:], recipes: recipes)
        await store.loadIfNeeded(householdID: "household-1", householdProfile: profile(), feedbackVotes: [:], recipes: recipes)

        #expect(client.callCount == 1)
    }

    @Test func resetAllowsAFreshLoadForTheSameHousehold() async {
        let client = StubRecipeRecommendationAPIClient(result: .success([MealRecommendation(mealID: "pasta", reason: "A family favorite")]))
        let store = RecipeRecommendationStore(apiClient: client)
        let recipes = [recipe("pasta", title: "Pasta")]

        await store.loadIfNeeded(householdID: "household-1", householdProfile: profile(), feedbackVotes: [:], recipes: recipes)
        store.reset()
        await store.loadIfNeeded(householdID: "household-1", householdProfile: profile(), feedbackVotes: [:], recipes: recipes)

        #expect(client.callCount == 2)
    }

    /// The backend now caches this call per household (~1 week TTL) — that
    /// only works if the request actually carries the household id, not just
    /// the client-side `recommendationsByHousehold` dictionary key.
    @Test func passesTheHouseholdIDThroughToTheAPICall() async {
        let client = StubRecipeRecommendationAPIClient(result: .success([]))
        let store = RecipeRecommendationStore(apiClient: client)

        await store.loadIfNeeded(householdID: "household-42", householdProfile: profile(householdID: "household-42"), feedbackVotes: [:], recipes: [recipe("pasta", title: "Pasta")])

        #expect(client.lastHouseholdID == "household-42")
    }

    @Test func pairsVotesWithTitlesAndDropsVotesForRecipesOutsideTheCandidatePool() async {
        let client = StubRecipeRecommendationAPIClient(result: .success([]))
        let store = RecipeRecommendationStore(apiClient: client)
        let recipes = [recipe("pasta", title: "Pasta")]

        await store.loadIfNeeded(
            householdID: "household-1",
            householdProfile: profile(),
            feedbackVotes: ["pasta": .up, "orphan-id-not-in-recipes": .down],
            recipes: recipes
        )

        let sentFeedback = client.lastFeedbackSummary ?? []
        #expect(sentFeedback.map(\.mealID) == ["pasta"])
        #expect(sentFeedback.first?.mealTitle == "Pasta")
        #expect(sentFeedback.first?.vote == .up)
    }

    @Test func passesTagsAndIngredientNamesForServerSideAvoidFiltering() async {
        let client = StubRecipeRecommendationAPIClient(result: .success([]))
        let store = RecipeRecommendationStore(apiClient: client)
        let recipe = FullRecipe(
            id: "pasta",
            title: "Pasta",
            description: "",
            servings: 4,
            prepTimeMinutes: 10,
            cookTimeMinutes: 15,
            tags: ["weekday"],
            ingredients: [RecipeIngredient(item: "peanut butter", amount: nil, unit: nil, category: nil)],
            steps: [],
            userVote: nil
        )

        await store.loadIfNeeded(
            householdID: "household-1",
            householdProfile: profile(),
            feedbackVotes: [:],
            recipes: [recipe]
        )

        #expect(client.lastCandidateMeals?.first?.tags == ["weekday"])
        #expect(client.lastCandidateMeals?.first?.ingredients == ["peanut butter"])
    }
}

private final class StubRecipeRecommendationAPIClient: RecipeRecommendationAPIClient {
    let result: Result<[MealRecommendation], Error>
    private(set) var callCount = 0
    private(set) var lastFeedbackSummary: [MealRecommendationFeedbackItem]?
    private(set) var lastCandidateMeals: [MealRecommendationCandidate]?

    init(result: Result<[MealRecommendation], Error>) {
        self.result = result
    }

    private(set) var lastHouseholdID: String?

    func recommendMeals(
        householdID: String,
        householdProfile: HouseholdProfile,
        feedbackSummary: [MealRecommendationFeedbackItem],
        candidateMeals: [MealRecommendationCandidate]
    ) async throws -> [MealRecommendation] {
        callCount += 1
        lastHouseholdID = householdID
        lastFeedbackSummary = feedbackSummary
        lastCandidateMeals = candidateMeals
        return try result.get()
    }
}

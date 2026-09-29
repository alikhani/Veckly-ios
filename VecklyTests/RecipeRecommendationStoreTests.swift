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

    @Test func cachesDifferentPickerContextsSeparately() async {
        let client = StubRecipeRecommendationAPIClient(result: .success([]))
        let store = RecipeRecommendationStore(apiClient: client)
        let recipes = [recipe("pasta", title: "Pasta")]
        let general = MealRecommendationRequestContext.general(referenceWeekStartDate: "2026-09-28")
        let quicker = MealRecommendationRequestContext(
            referenceWeekStartDate: "2026-09-28",
            prep: nil,
            swap: .init(intent: .quicker, currentMealID: "stew")
        )

        await store.loadIfNeeded(householdID: "household-1", householdProfile: profile(), feedbackVotes: [:], recipes: recipes, context: general)
        await store.loadIfNeeded(householdID: "household-1", householdProfile: profile(), feedbackVotes: [:], recipes: recipes, context: quicker)

        #expect(client.callCount == 2)
        #expect(client.contexts == [general, quicker])
    }

    @Test func reloadsTheSameContextWhenCandidateMetadataChanges() async {
        let client = StubRecipeRecommendationAPIClient(result: .success([]))
        let store = RecipeRecommendationStore(apiClient: client)
        let context = MealRecommendationRequestContext.general(referenceWeekStartDate: "2026-09-28")
        let original = recipe("pasta", title: "Pasta")
        let updated = FullRecipe(
            id: original.id,
            title: original.title,
            description: original.description,
            servings: original.servings,
            prepTimeMinutes: 5,
            cookTimeMinutes: original.cookTimeMinutes,
            tags: ["quick"],
            ingredients: original.ingredients,
            steps: original.steps,
            userVote: original.userVote
        )

        await store.loadIfNeeded(householdID: "household-1", householdProfile: profile(), feedbackVotes: [:], recipes: [original], context: context)
        await store.loadIfNeeded(householdID: "household-1", householdProfile: profile(), feedbackVotes: [:], recipes: [updated], context: context)

        #expect(client.callCount == 2)
        #expect(client.lastCandidateMeals?.first?.prepTimeMinutes == 5)
        #expect(client.lastCandidateMeals?.first?.tags == ["quick"])
    }

    @Test func sendsRichCandidateMetadataAndBoundsNormalizedLists() async {
        let client = StubRecipeRecommendationAPIClient(result: .success([]))
        let store = RecipeRecommendationStore(apiClient: client)
        let richRecipe = FullRecipe(
            id: "stew",
            title: "Stew",
            description: "",
            servings: 6,
            prepTimeMinutes: 20,
            cookTimeMinutes: 70,
            tags: [" batch-friendly ", "Batch-Friendly", "family"],
            ingredients: [
                RecipeIngredient(item: " lentils ", amount: nil, unit: nil, category: nil),
                RecipeIngredient(item: "Lentils", amount: nil, unit: nil, category: nil),
            ],
            steps: [],
            userVote: nil,
            cuisine: "Nordic",
            proteinSource: "legumes",
            mealWeight: "hearty"
        )

        await store.loadIfNeeded(householdID: "household-1", householdProfile: profile(), feedbackVotes: [:], recipes: [richRecipe])

        let candidate = client.lastCandidateMeals?.first
        #expect(candidate?.prepTimeMinutes == 20)
        #expect(candidate?.cookTimeMinutes == 70)
        #expect(candidate?.cuisine == "Nordic")
        #expect(candidate?.proteinSource == "legumes")
        #expect(candidate?.mealWeight == "hearty")
        #expect(candidate?.tags == ["batch-friendly", "family"])
        #expect(candidate?.ingredients == ["lentils"])
    }

    @Test func filtersAnAIRecipeThatWasNotInTheCandidateSet() async {
        let client = StubRecipeRecommendationAPIClient(
            result: .success([
                MealRecommendation(mealID: "invented", reason: "No"),
                MealRecommendation(mealID: "pasta", reason: "Yes"),
            ])
        )
        let store = RecipeRecommendationStore(apiClient: client)

        await store.loadIfNeeded(householdID: "household-1", householdProfile: profile(), feedbackVotes: [:], recipes: [recipe("pasta", title: "Pasta")])

        #expect(store.recommendations(for: "household-1").map(\.mealID) == ["pasta"])
    }

    @Test func invalidationDuringAnInFlightLoadCannotRestoreTheStaleResponse() async throws {
        let client = StubRecipeRecommendationAPIClient(
            result: .success([MealRecommendation(mealID: "pasta", reason: "old")])
        )
        client.delayNanoseconds = 50_000_000
        let store = RecipeRecommendationStore(apiClient: client)
        let recipes = [recipe("pasta", title: "Pasta")]

        let staleLoad = Task {
            await store.loadIfNeeded(householdID: "household-1", householdProfile: profile(), feedbackVotes: [:], recipes: recipes)
        }
        try await Task.sleep(nanoseconds: 10_000_000)
        store.invalidate(householdID: "household-1")
        client.result = .success([MealRecommendation(mealID: "pasta", reason: "fresh")])
        let freshLoad = Task {
            await store.loadIfNeeded(householdID: "household-1", householdProfile: profile(), feedbackVotes: [:], recipes: recipes)
        }
        await staleLoad.value
        await freshLoad.value

        #expect(store.recommendations(for: "household-1").map(\.reason) == ["fresh"])
        #expect(client.callCount == 2)
    }

    @Test func resetDuringAnInFlightLoadCannotRepopulateTheCache() async throws {
        let client = StubRecipeRecommendationAPIClient(
            result: .success([MealRecommendation(mealID: "pasta", reason: "stale")])
        )
        client.delayNanoseconds = 40_000_000
        let store = RecipeRecommendationStore(apiClient: client)
        let load = Task {
            await store.loadIfNeeded(householdID: "household-1", householdProfile: profile(), feedbackVotes: [:], recipes: [recipe("pasta", title: "Pasta")])
        }
        try await Task.sleep(nanoseconds: 10_000_000)

        store.reset()
        await load.value

        #expect(store.recommendations(for: "household-1").isEmpty)
        #expect(store.state(for: "household-1", context: .general(referenceWeekStartDate: WeekCalendar.currentWeekStartDate())) == .idle)
    }
}

private final class StubRecipeRecommendationAPIClient: RecipeRecommendationAPIClient {
    var result: Result<[MealRecommendation], Error>
    var delayNanoseconds: UInt64 = 0
    private(set) var callCount = 0
    private(set) var lastFeedbackSummary: [MealRecommendationFeedbackItem]?
    private(set) var lastCandidateMeals: [MealRecommendationCandidate]?
    private(set) var contexts: [MealRecommendationRequestContext] = []

    init(result: Result<[MealRecommendation], Error>) {
        self.result = result
    }

    private(set) var lastHouseholdID: String?

    func recommendMeals(
        householdID: String,
        householdProfile: HouseholdProfile,
        feedbackSummary: [MealRecommendationFeedbackItem],
        candidateMeals: [MealRecommendationCandidate],
        context: MealRecommendationRequestContext
    ) async throws -> [MealRecommendation] {
        let capturedResult = result
        callCount += 1
        lastHouseholdID = householdID
        lastFeedbackSummary = feedbackSummary
        lastCandidateMeals = candidateMeals
        contexts.append(context)
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return try capturedResult.get()
    }
}

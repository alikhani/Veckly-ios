import Foundation
import Observation

struct MealRecommendationPrepContext: Equatable, Hashable {
    let isCookDay: Bool
    let leftoversDesired: Bool
}

struct MealRecommendationSwapContext: Equatable, Hashable {
    let intent: MealSwapIntent
    let currentMealID: String?
}

struct MealRecommendationRequestContext: Equatable, Hashable {
    let referenceWeekStartDate: String
    let prep: MealRecommendationPrepContext?
    let swap: MealRecommendationSwapContext?

    static func general(referenceWeekStartDate: String) -> Self {
        .init(referenceWeekStartDate: referenceWeekStartDate, prep: nil, swap: nil)
    }
}

enum MealRecommendationLoadState: Equatable {
    case idle
    case loading
    case available
    case fallback
}

protocol RecipeRecommendationAPIClient {
    func recommendMeals(
        householdID: String,
        householdProfile: HouseholdProfile,
        feedbackSummary: [MealRecommendationFeedbackItem],
        candidateMeals: [MealRecommendationCandidate],
        context: MealRecommendationRequestContext
    ) async throws -> [MealRecommendation]
}

extension VecklyAPIClient: RecipeRecommendationAPIClient {}

/// Context-keyed recommendations for the meal picker. A Sunday prefetch and a
/// Tuesday "quicker" swap are intentionally different entries: reusing the
/// first answer for the second would make the smart surface feel stale even
/// when the backend request itself is context-aware.
@MainActor
@Observable
final class RecipeRecommendationStore {
    private struct CacheKey: Hashable {
        let householdID: String
        let context: MealRecommendationRequestContext
    }

    private let apiClient: any RecipeRecommendationAPIClient
    private var recommendationsByKey: [CacheKey: [MealRecommendation]] = [:]
    private var statesByKey: [CacheKey: MealRecommendationLoadState] = [:]
    private var requestTokensByKey: [CacheKey: UUID] = [:]
    private var candidateFingerprintsByKey: [CacheKey: Int] = [:]
    private var generationsByHousehold: [String: Int] = [:]

    init(apiClient: any RecipeRecommendationAPIClient) {
        self.apiClient = apiClient
    }

    func recommendations(
        for householdID: String,
        context: MealRecommendationRequestContext
    ) -> [MealRecommendation] {
        recommendationsByKey[CacheKey(householdID: householdID, context: context)] ?? []
    }

    func recommendations(for householdID: String) -> [MealRecommendation] {
        recommendations(
            for: householdID,
            context: .general(referenceWeekStartDate: WeekCalendar.currentWeekStartDate())
        )
    }

    func state(
        for householdID: String,
        context: MealRecommendationRequestContext
    ) -> MealRecommendationLoadState {
        statesByKey[CacheKey(householdID: householdID, context: context)] ?? .idle
    }

    func cacheGeneration(for householdID: String) -> Int {
        generationsByHousehold[householdID, default: 0]
    }

    func loadIfNeeded(
        householdID: String,
        householdProfile: HouseholdProfile,
        feedbackVotes: [String: MealVote],
        recipes: [FullRecipe],
        context: MealRecommendationRequestContext = .general(
            referenceWeekStartDate: WeekCalendar.currentWeekStartDate()
        )
    ) async {
        guard !recipes.isEmpty else { return }
        let key = CacheKey(householdID: householdID, context: context)
        let candidateFingerprint = Self.candidateFingerprint(recipes)
        if candidateFingerprintsByKey[key] == candidateFingerprint,
           recommendationsByKey[key] != nil || requestTokensByKey[key] != nil {
            return
        }

        let requestToken = UUID()
        requestTokensByKey[key] = requestToken
        candidateFingerprintsByKey[key] = candidateFingerprint
        statesByKey[key] = .loading
        defer {
            if requestTokensByKey[key] == requestToken {
                requestTokensByKey[key] = nil
            }
        }

        let selectedRecipes = Self.selectCandidates(recipes, feedbackVotes: feedbackVotes)
        let titlesByID = Dictionary(uniqueKeysWithValues: selectedRecipes.map { ($0.id, $0.title) })
        let feedbackSummary = feedbackVotes.compactMap { mealID, vote -> MealRecommendationFeedbackItem? in
            guard let title = titlesByID[mealID] else { return nil }
            return MealRecommendationFeedbackItem(mealID: mealID, mealTitle: title, vote: vote)
        }
        let candidates = selectedRecipes.map(Self.candidate)

        do {
            let recommendations = try await apiClient.recommendMeals(
                householdID: householdID,
                householdProfile: householdProfile,
                feedbackSummary: feedbackSummary,
                candidateMeals: candidates,
                context: context
            )
            guard requestTokensByKey[key] == requestToken else { return }
            // A second deterministic allow-list on device means even a stale
            // or malformed AI response cannot introduce a recipe that was not
            // in the bounded candidate set sent for this request.
            let allowedIDs = Set(candidates.map(\.id))
            recommendationsByKey[key] = recommendations.filter { allowedIDs.contains($0.mealID) }
            statesByKey[key] = .available
        } catch {
            guard requestTokensByKey[key] == requestToken else { return }
            recommendationsByKey[key] = []
            statesByKey[key] = .fallback
        }
    }

    func invalidate(householdID: String) {
        recommendationsByKey = recommendationsByKey.filter { $0.key.householdID != householdID }
        statesByKey = statesByKey.filter { $0.key.householdID != householdID }
        requestTokensByKey = requestTokensByKey.filter { $0.key.householdID != householdID }
        candidateFingerprintsByKey = candidateFingerprintsByKey.filter { $0.key.householdID != householdID }
        generationsByHousehold[householdID, default: 0] += 1
    }

    func reset() {
        recommendationsByKey = [:]
        statesByKey = [:]
        requestTokensByKey = [:]
        candidateFingerprintsByKey = [:]
        generationsByHousehold = generationsByHousehold.mapValues { $0 + 1 }
    }

    static func candidateFingerprint(_ recipes: [FullRecipe]) -> Int {
        var hasher = Hasher()
        for recipe in recipes {
            hasher.combine(recipe.id)
            hasher.combine(recipe.title)
            hasher.combine(recipe.prepTimeMinutes)
            hasher.combine(recipe.cookTimeMinutes)
            hasher.combine(recipe.cuisine)
            hasher.combine(recipe.proteinSource)
            hasher.combine(recipe.mealWeight)
            hasher.combine(recipe.tags)
            hasher.combine(recipe.ingredients.map(\.item))
        }
        return hasher.finalize()
    }

    /// Keeps request size predictable while retaining the strongest explicit
    /// signal first. The backend applies its own final prompt budget too.
    private static func selectCandidates(
        _ recipes: [FullRecipe],
        feedbackVotes: [String: MealVote]
    ) -> [FullRecipe] {
        let ranked = recipes.enumerated().sorted { lhs, rhs in
            let lhsRank = feedbackVotes[lhs.element.id] == nil ? 1 : 0
            let rhsRank = feedbackVotes[rhs.element.id] == nil ? 1 : 0
            return lhsRank == rhsRank ? lhs.offset < rhs.offset : lhsRank < rhsRank
        }
        return ranked.prefix(200).map(\.element)
    }

    private static func candidate(_ recipe: FullRecipe) -> MealRecommendationCandidate {
        MealRecommendationCandidate(
            id: recipe.id,
            title: recipe.title,
            tags: normalized(recipe.tags, limit: 20),
            ingredients: normalized(recipe.ingredients.map(\.item), limit: 40),
            prepTimeMinutes: recipe.prepTimeMinutes,
            cookTimeMinutes: recipe.cookTimeMinutes,
            cuisine: recipe.cuisine,
            proteinSource: recipe.proteinSource,
            mealWeight: recipe.mealWeight
        )
    }

    private static func normalized(_ values: [String], limit: Int) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let identity = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard seen.insert(identity).inserted else { return nil }
            return trimmed
        }.prefix(limit).map { $0 }
    }
}

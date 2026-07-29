import Foundation
import Observation

protocol FamilyCookbookAPIClient {
    func familyCookbook(householdID: String, weekStartDate: String) async throws -> FamilyCookbook
}

extension VecklyAPIClient: FamilyCookbookAPIClient {}

/// Backs the "Er kokbok" panel in the Household tab (Plan D3). Session-scoped,
/// in-memory only — the same silent-fallback-on-failure, load-once-per-
/// household shape as `RecipeRecommendationStore`, since this is a quiet
/// recognition panel, not a live dashboard.
@MainActor
@Observable
final class FamilyCookbookStore {
    private let apiClient: any FamilyCookbookAPIClient
    private let cache = PerHouseholdCache<FamilyCookbook>()

    init(apiClient: any FamilyCookbookAPIClient) {
        self.apiClient = apiClient
    }

    func cookbook(for householdID: String) -> FamilyCookbook? {
        cache.value(for: householdID)
    }

    func removeRecipe(_ recipeID: String, householdID: String) {
        guard let current = cache.value(for: householdID) else { return }
        guard current.uniqueRecipes.contains(where: { $0.recipeID == recipeID }) else { return }
        let favorites = current.favorites.filter { $0.recipeID != recipeID }
        let dueAgain = current.dueAgain.filter { $0.recipeID != recipeID }
        cache.setValue(
            FamilyCookbook(
                totalFamilyLikedCount: max(0, current.totalFamilyLikedCount - 1),
                favorites: favorites,
                dueAgain: dueAgain
            ),
            for: householdID
        )
    }

    func loadIfNeeded(householdID: String) async {
        await cache.loadIfNeeded(householdID: householdID) {
            do {
                return try await apiClient.familyCookbook(
                    householdID: householdID,
                    weekStartDate: WeekCalendar.currentWeekStartDate()
                )
            } catch {
                // Silent fallback — cache an empty cookbook (the panel already
                // hides itself when `totalFamilyLikedCount == 0`) rather than
                // leaving the entry unset, which would make `loadIfNeeded` retry
                // on every subsequent call instead of just once per session.
                return FamilyCookbook(totalFamilyLikedCount: 0, favorites: [], dueAgain: [])
            }
        }
    }

    func reset() {
        cache.reset()
    }
}

extension FamilyCookbook {
    var uniqueFavorites: [Recipe] {
        unique(favorites)
    }

    var uniqueDueAgain: [Recipe] {
        let favoriteIDs = Set(uniqueFavorites.map(\.recipeID))
        return unique(dueAgain).filter { !favoriteIDs.contains($0.recipeID) }
    }

    var uniqueRecipes: [Recipe] {
        uniqueFavorites + uniqueDueAgain
    }

    private func unique(_ recipes: [Recipe]) -> [Recipe] {
        var seen = Set<String>()
        return recipes.filter { seen.insert($0.recipeID).inserted }
    }
}

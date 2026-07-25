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

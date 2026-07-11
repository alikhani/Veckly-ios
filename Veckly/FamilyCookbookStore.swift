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
    private var cookbookByHousehold: [String: FamilyCookbook] = [:]
    private var loadingHouseholdIDs: Set<String> = []

    init(apiClient: any FamilyCookbookAPIClient) {
        self.apiClient = apiClient
    }

    func cookbook(for householdID: String) -> FamilyCookbook? {
        cookbookByHousehold[householdID]
    }

    func loadIfNeeded(householdID: String) async {
        guard cookbookByHousehold[householdID] == nil, !loadingHouseholdIDs.contains(householdID) else { return }
        loadingHouseholdIDs.insert(householdID)
        defer { loadingHouseholdIDs.remove(householdID) }

        do {
            cookbookByHousehold[householdID] = try await apiClient.familyCookbook(
                householdID: householdID,
                weekStartDate: WeekCalendar.currentWeekStartDate()
            )
        } catch {
            // Silent fallback — cache an empty cookbook (the panel already
            // hides itself when `totalFamilyLikedCount == 0`) rather than
            // leaving the entry unset, which would make `loadIfNeeded` retry
            // on every subsequent call instead of just once per session.
            cookbookByHousehold[householdID] = FamilyCookbook(totalFamilyLikedCount: 0, favorites: [], dueAgain: [])
        }
    }

    func reset() {
        cookbookByHousehold = [:]
        loadingHouseholdIDs = []
    }
}

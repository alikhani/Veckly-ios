import Foundation
import Observation

protocol HouseholdSavedRecipesAPIClient {
    func listHouseholdSavedRecipeIDs(householdID: String) async throws -> [String]
    func addHouseholdSavedRecipe(householdID: String, recipeID: String) async throws
    func removeHouseholdSavedRecipe(householdID: String, recipeID: String) async throws
}

// Tracks which recipes this household has added to its shared bookmark list
// (Plan A3b) — the pool week generation reads from (see
// `Veckly-backend/src/week-plan.ts`).
@MainActor
@Observable
final class HouseholdSavedRecipesStore {
    private let apiClient: any HouseholdSavedRecipesAPIClient
    private var addedRecipeIDs: Set<String> = []

    init(apiClient: any HouseholdSavedRecipesAPIClient) {
        self.apiClient = apiClient
    }

    func isAdded(_ recipeID: String) -> Bool {
        addedRecipeIDs.contains(recipeID)
    }

    /// Seeds `addedRecipeIDs` from the server — call once per household load
    /// so `isAdded` reflects bookmarks made in earlier sessions too, not just
    /// this one.
    func loadSavedRecipeIDs(householdID: String) async {
        guard let ids = try? await apiClient.listHouseholdSavedRecipeIDs(householdID: householdID) else { return }
        addedRecipeIDs = Set(ids)
    }

    func setAdded(householdID: String, recipeID: String, added: Bool) async {
        let wasAdded = addedRecipeIDs.contains(recipeID)
        guard wasAdded != added else { return }

        if added {
            addedRecipeIDs.insert(recipeID)
        } else {
            addedRecipeIDs.remove(recipeID)
        }

        do {
            if added {
                try await apiClient.addHouseholdSavedRecipe(householdID: householdID, recipeID: recipeID)
            } else {
                try await apiClient.removeHouseholdSavedRecipe(householdID: householdID, recipeID: recipeID)
            }
        } catch {
            // Roll back on failure
            if wasAdded {
                addedRecipeIDs.insert(recipeID)
            } else {
                addedRecipeIDs.remove(recipeID)
            }
        }
    }

    func reset() {
        addedRecipeIDs = []
    }
}

extension VecklyAPIClient: HouseholdSavedRecipesAPIClient {}

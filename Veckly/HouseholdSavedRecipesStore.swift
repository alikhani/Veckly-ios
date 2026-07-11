import Foundation
import Observation

protocol HouseholdSavedRecipesAPIClient {
    func addHouseholdSavedRecipe(householdID: String, recipeID: String) async throws
    func removeHouseholdSavedRecipe(householdID: String, recipeID: String) async throws
}

// Tracks which community recipes this session has added to the household's
// shared bookmark list (Plan A3b) — the pool week generation reads from (see
// `Veckly-backend/src/week-plan.ts`). Session-only, not seeded from the
// server on load: a recipe added in a previous session will show as
// "not yet added" again here until the user revisits it, which is harmless
// since adding is idempotent server-side.
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

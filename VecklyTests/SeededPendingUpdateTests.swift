import Testing
@testable import Veckly

/// The UI-test seed that shows the "updates available" banner (used for
/// screenshots) must behave like a real pending update.
@MainActor
struct SeededPendingUpdateTests {
    @Test func theSeededWeekUpdateWaitsAndAppliesOnRequest() {
        let store = WeekStore(apiClient: SeededPendingNoopWeekAPI())
        store.seedForUITests()
        let before = store.dayRows.map(\.mealTitle)

        store.seedPendingUpdateForUITests()

        #expect(store.hasPendingUpdate(for: store.weekStartDate))
        #expect(store.dayRows.map(\.mealTitle) == before)

        store.applyPendingUpdate()

        #expect(!store.hasPendingUpdate(for: store.weekStartDate))
        #expect(store.dayRows.map(\.mealTitle) != before)
    }

    @Test func theSeededShoppingUpdateWaitsAndAppliesOnRequest() {
        let store = ShoppingListStore(apiClient: SeededPendingNoopShoppingAPI())
        store.seedForUITests()
        let before = store.groups.flatMap(\.items).count

        store.seedPendingUpdateForUITests()

        #expect(store.hasPendingUpdate)
        #expect(store.groups.flatMap(\.items).count == before)

        store.applyPendingUpdate()

        #expect(!store.hasPendingUpdate)
        #expect(store.groups.flatMap(\.items).count == before + 1)
    }
}

private struct SeededPendingNoopWeekAPI: WeekStoreAPIClient {
    func weekSummary(householdID: String, weekStartDate: String) async throws -> WeekSummary { throw APIError.notFound }
    func appendWeekPlanEvent(householdID: String, weekStartDate: String, userID: String, event: WeekPlanEventInput) async throws {}
    func generateWeekPlan(householdID: String, weekStartDate: String, regenerate: Bool) async throws {}
    func recipe(householdID: String, recipeID: String) async throws -> FullRecipe { throw APIError.notFound }
}

private struct SeededPendingNoopShoppingAPI: ShoppingListStoreAPIClient {
    func shoppingListSummary(householdID: String, weekStartDate: String) async throws -> ShoppingListSummary { throw APIError.notFound }
    func shoppingListState(householdID: String, weekStartDate: String) async throws -> (state: ShoppingListSharedState?, updatedAt: String?) { (nil, nil) }
    func updateShoppingListState(householdID: String, weekStartDate: String, checkedItems: [String], pantryStock: [String: Double], expectedUpdatedAt: String?, customItems: [ShoppingCustomItem]) async throws -> String? { nil }
}

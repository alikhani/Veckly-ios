import Foundation
import Observation

@MainActor
@Observable
final class ShoppingListStore {
    private let apiClient: VecklyAPIClient

    private(set) var summary: ShoppingListSummary?
    private(set) var groups: [ShoppingListGroup] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    init(apiClient: VecklyAPIClient) {
        self.apiClient = apiClient
    }

    func loadCurrentWeek(household: Household, weekStartDate: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let summary = try await apiClient.shoppingListSummary(householdID: household.id, weekStartDate: weekStartDate)
            self.summary = summary
            groups = ShoppingListViewModelMapper.groups(from: summary)
        } catch APIError.notFound {
            summary = nil
            groups = []
        } catch {
            errorMessage = "We could not load your shopping list."
        }
    }

    func reset() {
        summary = nil
        groups = []
        errorMessage = nil
        isLoading = false
    }

    func seedForUITests() {
        groups = [
            ShoppingListGroup(
                category: "Pantry",
                items: [ShoppingListItem(itemKey: "pantry:spaghetti:400:g", label: "spaghetti", amount: "400", unit: "g", checked: false)]
            ),
        ]
    }
}

struct ShoppingListViewModelMapper {
    static func groups(from summary: ShoppingListSummary) -> [ShoppingListGroup] {
        summary.groups.filter { !$0.items.isEmpty }
    }
}

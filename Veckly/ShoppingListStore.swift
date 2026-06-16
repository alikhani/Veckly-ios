import Foundation
import Observation

@MainActor
@Observable
final class ShoppingListStore {
    private let apiClient: VecklyAPIClient

    private(set) var summary: ShoppingListSummary?
    private(set) var groups: [ShoppingListGroup] = []
    private(set) var checkedItems: Set<String> = []
    private(set) var stateUpdatedAt: String?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var lastFetchedAt: Date?

    init(apiClient: VecklyAPIClient) {
        self.apiClient = apiClient
    }

    func loadCurrentWeek(household: Household, weekStartDate: String) async {
        guard lastFetchedAt == nil || Date().timeIntervalSince(lastFetchedAt!) > 60 || summary == nil else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let summary = try await apiClient.shoppingListSummary(householdID: household.id, weekStartDate: weekStartDate)
            self.summary = summary
            lastFetchedAt = Date()
            groups = ShoppingListViewModelMapper.groups(from: summary)
            checkedItems = Set(groups.flatMap { $0.items }.filter { $0.checked }.map { $0.itemKey })
            stateUpdatedAt = nil
        } catch APIError.notFound {
            summary = nil
            groups = []
            checkedItems = []
        } catch {
            errorMessage = "We could not load your shopping list."
        }
    }

    func toggleItem(key: String) async {
        guard let summary else { return }
        let wasChecked = checkedItems.contains(key)
        if wasChecked { checkedItems.remove(key) } else { checkedItems.insert(key) }

        do {
            let newUpdatedAt = try await apiClient.updateShoppingListState(
                householdID: summary.household.id,
                weekStartDate: summary.weekStartDate,
                checkedItems: Array(checkedItems),
                expectedUpdatedAt: stateUpdatedAt
            )
            stateUpdatedAt = newUpdatedAt
        } catch APIError.stale(let latestUpdatedAt) {
            stateUpdatedAt = latestUpdatedAt
            do {
                let newUpdatedAt = try await apiClient.updateShoppingListState(
                    householdID: summary.household.id,
                    weekStartDate: summary.weekStartDate,
                    checkedItems: Array(checkedItems),
                    expectedUpdatedAt: stateUpdatedAt
                )
                stateUpdatedAt = newUpdatedAt
            } catch {
                if wasChecked { checkedItems.insert(key) } else { checkedItems.remove(key) }
            }
        } catch {
            if wasChecked { checkedItems.insert(key) } else { checkedItems.remove(key) }
        }
    }

    func reset() {
        summary = nil
        groups = []
        checkedItems = []
        stateUpdatedAt = nil
        errorMessage = nil
        isLoading = false
        lastFetchedAt = nil
    }

    func seedForUITests() {
        groups = [
            ShoppingListGroup(
                category: "Pantry",
                items: [ShoppingListItem(itemKey: "pantry:spaghetti:400:g", label: "spaghetti", amount: "400", unit: "g", checked: false)]
            ),
        ]
        checkedItems = []
    }
}

struct ShoppingListViewModelMapper {
    static func groups(from summary: ShoppingListSummary) -> [ShoppingListGroup] {
        summary.groups.filter { !$0.items.isEmpty }
    }
}

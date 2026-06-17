import Foundation
import Observation

// MARK: - Shopping category

enum ShoppingCategory: String, CaseIterable {
    case produce
    case meat
    case dairy
    case pantry
    case frozen
    case bakery
    case other

    static func from(_ raw: String) -> ShoppingCategory {
        switch raw.lowercased() {
        case "produce": return .produce
        case "protein": return .meat
        case "dairy": return .dairy
        case "pantry": return .pantry
        case "frozen": return .frozen
        case "bakery": return .bakery
        default: return .other
        }
    }

    var displayLabel: String {
        switch self {
        case .produce: return "Fruit & veg"
        case .meat:    return "Meat & fish"
        case .dairy:   return "Dairy & eggs"
        case .pantry:  return "Pantry"
        case .frozen:  return "Frozen"
        case .bakery:  return "Bakery"
        case .other:   return "Other"
        }
    }

    var sortIndex: Int {
        switch self {
        case .produce: return 0
        case .meat:    return 1
        case .dairy:   return 2
        case .pantry:  return 3
        case .frozen:  return 4
        case .bakery:  return 5
        case .other:   return 6
        }
    }
}

// MARK: - Store

@MainActor
@Observable
final class ShoppingListStore {
    private let apiClient: VecklyAPIClient

    private(set) var summary: ShoppingListSummary?
    private(set) var groups: [ShoppingListGroup] = []
    private(set) var stapledItems: [ShoppingListItem] = []
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
            let mapped = ShoppingListViewModelMapper.map(from: summary)
            groups = mapped.groups
            stapledItems = mapped.stapledItems
            let allItems = groups.flatMap { $0.items } + stapledItems
            checkedItems = Set(allItems.filter { $0.checked }.map { $0.itemKey })
            stateUpdatedAt = nil
        } catch APIError.notFound {
            summary = nil
            groups = []
            stapledItems = []
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
        stapledItems = []
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
        stapledItems = []
        checkedItems = []
    }
}

// MARK: - Mapper

struct ShoppingListViewModelMapper {
    private static let stapleNames: Set<String> = [
        // Swedish
        "salt", "peppar", "svartpeppar", "vitpeppar", "vatten", "olja", "olivolja",
        "rapsolja", "solrosolja", "mjöl", "vetemjöl", "socker", "strösocker",
        "bikarbonat", "bakpulver",
        // English (imported recipes)
        "water", "oil", "olive oil", "flour", "sugar", "salt and pepper",
        "black pepper", "pepper", "baking powder", "baking soda",
    ]

    static func isStaple(_ label: String) -> Bool {
        stapleNames.contains(label.lowercased().trimmingCharacters(in: .whitespaces))
    }

    static func map(from summary: ShoppingListSummary) -> (groups: [ShoppingListGroup], stapledItems: [ShoppingListItem]) {
        var extracted: [ShoppingListItem] = []

        let filteredGroups = summary.groups
            .compactMap { group -> ShoppingListGroup? in
                let (regular, staples) = group.items.reduce(
                    into: ([ShoppingListItem](), [ShoppingListItem]())
                ) { acc, item in
                    if isStaple(item.label) { acc.1.append(item) } else { acc.0.append(item) }
                }
                extracted.append(contentsOf: staples)
                guard !regular.isEmpty else { return nil }
                return ShoppingListGroup(category: group.category, items: regular)
            }
            .filter { !$0.items.isEmpty }
            .sorted { ShoppingCategory.from($0.category).sortIndex < ShoppingCategory.from($1.category).sortIndex }

        return (filteredGroups, extracted)
    }
}

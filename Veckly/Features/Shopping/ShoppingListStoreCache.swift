import Foundation

/// Everything one shopping-list load returns, as the store applies it: the
/// summary, the shared check/pantry/custom-item state with its version, and
/// the category order. Persisted whole so a restored list carries the same
/// `updatedAt` the next write is checked against, and the pantry stock a write
/// sends back is the server's, not an empty one.
struct ShoppingListSnapshot: Codable, Equatable {
    let summary: ShoppingListSummary
    let state: ShoppingListSharedState?
    let stateUpdatedAt: String?
    let categoryOrder: [String]?

    /// Two snapshots of the same server state are equal whatever order the
    /// server listed the checked and custom items in.
    static func == (lhs: ShoppingListSnapshot, rhs: ShoppingListSnapshot) -> Bool {
        lhs.summary == rhs.summary
            && lhs.stateUpdatedAt == rhs.stateUpdatedAt
            && lhs.categoryOrder.map { $0.map(ShoppingCategory.from) } == rhs.categoryOrder.map { $0.map(ShoppingCategory.from) }
            && lhs.normalizedState == rhs.normalizedState
    }

    private var normalizedState: ShoppingListSharedState? {
        state.map {
            ShoppingListSharedState(
                checkedItems: $0.checkedItems.sorted(),
                pantryStock: $0.pantryStock,
                customItems: $0.customItems.sorted { $0.itemKey < $1.itemKey }
            )
        }
    }
}

protocol ShoppingListStoreCachePersisting {
    func loadList(scope: CacheScope, weekStartDate: String) -> ShoppingListSnapshot?
    func saveList(_ snapshot: ShoppingListSnapshot, scope: CacheScope)
    func removeList(scope: CacheScope, weekStartDate: String)
    func deleteAll()
}

/// Disk persistence for each household's recent shopping lists (see
/// `HouseholdWeekDiskCache`). A snapshot that doesn't belong to the week and
/// household it is filed under is a miss.
struct ShoppingListStoreDiskCache: ShoppingListStoreCachePersisting {
    private let cache: HouseholdWeekDiskCache<ShoppingListSnapshot>

    init(baseDirectory: URL? = nil) {
        cache = HouseholdWeekDiskCache(folder: "shopping-lists", baseDirectory: baseDirectory)
    }

    func loadList(scope: CacheScope, weekStartDate: String) -> ShoppingListSnapshot? {
        guard let snapshot = cache.load(scope: scope, weekStartDate: weekStartDate),
              snapshot.summary.weekStartDate == weekStartDate,
              snapshot.summary.household.id == scope.householdID else { return nil }
        return snapshot
    }

    func saveList(_ snapshot: ShoppingListSnapshot, scope: CacheScope) {
        cache.save(snapshot, scope: scope, weekStartDate: snapshot.summary.weekStartDate)
    }

    func removeList(scope: CacheScope, weekStartDate: String) {
        cache.remove(scope: scope, weekStartDate: weekStartDate)
    }

    func deleteAll() {
        cache.deleteAll()
    }
}

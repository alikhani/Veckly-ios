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
        case .produce: return L10n.string("shopping.category.produce")
        case .meat:    return L10n.string("shopping.category.meat")
        case .dairy:   return L10n.string("shopping.category.dairy")
        case .pantry:  return L10n.string("shopping.category.pantry")
        case .frozen:  return L10n.string("shopping.category.frozen")
        case .bakery:  return L10n.string("shopping.category.bakery")
        case .other:   return L10n.string("shopping.category.other")
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

    var backendValue: String {
        switch self {
        case .produce: return "Produce"
        case .meat:    return "Protein"
        case .dairy:   return "Dairy"
        case .pantry:  return "Pantry"
        case .frozen:  return "Frozen"
        case .bakery:  return "Bakery"
        case .other:   return "Other"
        }
    }
}

// MARK: - Store

@MainActor
@Observable
final class ShoppingListStore {
    private let apiClient: any ShoppingListStoreAPIClient
    private let syncDebounceNanoseconds: UInt64
    private let retryDelayNanoseconds: UInt64

    private(set) var summary: ShoppingListSummary?
    private(set) var groups: [ShoppingListGroup] = []
    private(set) var stapledItems: [ShoppingListItem] = []
    private(set) var customItems: [ShoppingCustomItem] = []
    private(set) var checkedItems: Set<String> = []
    private(set) var pantryStock: [String: Double] = [:]
    private(set) var stateUpdatedAt: String?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var mutationError: String?
    private(set) var lastFetchedAt: Date?
    private(set) var hasPendingSync = false
    private var regularGroups: [ShoppingListGroup] = []
    private var pendingMutations: [ShoppingListMutation] = []
    private var flushTask: Task<Void, Never>?
    private var isFlushingChanges = false

    init(
        apiClient: any ShoppingListStoreAPIClient,
        syncDebounceNanoseconds: UInt64 = 400_000_000,
        retryDelayNanoseconds: UInt64 = 2_000_000_000
    ) {
        self.apiClient = apiClient
        self.syncDebounceNanoseconds = syncDebounceNanoseconds
        self.retryDelayNanoseconds = retryDelayNanoseconds
    }

    func clearMutationError() { mutationError = nil }

    func loadCurrentWeek(household: Household, weekStartDate: String) async {
        guard !isLoading else { return }
        let hasFreshRequestedWeek = lastFetchedAt.map { Date().timeIntervalSince($0) <= 300 } == true
            && summary?.weekStartDate == weekStartDate
        guard !hasFreshRequestedWeek else { return }
        isLoading = summary == nil
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let summaryResult = apiClient.shoppingListSummary(householdID: household.id, weekStartDate: weekStartDate)
            async let stateResult = apiClient.shoppingListState(householdID: household.id, weekStartDate: weekStartDate)

            let summary = try await summaryResult
            let state = try await stateResult
            self.summary = summary
            lastFetchedAt = Date()
            let mapped = ShoppingListViewModelMapper.map(from: summary)
            regularGroups = ShoppingListViewModelMapper.regularGroups(from: mapped.groups)
            stapledItems = mapped.stapledItems
            let fallbackCheckedItems = Set((mapped.groups.flatMap(\.items) + mapped.stapledItems).filter(\.checked).map(\.itemKey))
            applySharedState(
                checkedItems: state.state.map { Set($0.checkedItems) } ?? fallbackCheckedItems,
                pantryStock: state.state?.pantryStock ?? [:],
                customItems: state.state?.customItems ?? mapped.customItems
            )
            stateUpdatedAt = state.updatedAt ?? summary.updatedAt
        } catch APIError.notFound {
            summary = nil
            groups = []
            regularGroups = []
            stapledItems = []
            customItems = []
            checkedItems = []
            pantryStock = [:]
        } catch {
            errorMessage = L10n.string("error.shopping.load")
        }
    }

    func toggleItem(key: String) async {
        mutationError = nil
        applyLocalMutation(.toggleChecked(key))
        scheduleFlush()
    }

    func addCustomItem(label: String, category: ShoppingCategory = .other) async throws {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let customItem = ShoppingCustomItem(
            itemKey: "custom:\(UUID().uuidString.lowercased())",
            label: trimmed,
            category: category.backendValue
        )
        mutationError = nil
        applyLocalMutation(.addCustomItem(customItem))
        scheduleFlush()
    }

    func removeCustomItem(itemKey: String) async throws {
        guard customItems.contains(where: { $0.itemKey == itemKey }) else { return }
        mutationError = nil
        applyLocalMutation(.removeCustomItem(itemKey))
        scheduleFlush()
    }

    func reset() {
        flushTask?.cancel()
        flushTask = nil
        pendingMutations = []
        hasPendingSync = false
        isFlushingChanges = false
        summary = nil
        groups = []
        regularGroups = []
        stapledItems = []
        customItems = []
        checkedItems = []
        pantryStock = [:]
        stateUpdatedAt = nil
        errorMessage = nil
        mutationError = nil
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
        customItems = []
        checkedItems = []
    }

    private func applySharedState(
        checkedItems: Set<String>,
        pantryStock: [String: Double],
        customItems: [ShoppingCustomItem]
    ) {
        self.checkedItems = checkedItems
        self.pantryStock = pantryStock
        self.customItems = customItems
        groups = ShoppingListViewModelMapper.inject(
            customItems: customItems,
            into: regularGroups,
            checkedItems: checkedItems
        )
    }

    private func currentState() -> MutableShoppingListState {
        MutableShoppingListState(
            checkedItems: checkedItems,
            pantryStock: pantryStock,
            customItems: customItems
        )
    }

    private func applyLocalMutation(_ mutation: ShoppingListMutation) {
        var desired = currentState()
        mutation.apply(to: &desired)
        applySharedState(
            checkedItems: desired.checkedItems,
            pantryStock: desired.pantryStock,
            customItems: desired.customItems
        )
        pendingMutations.append(mutation)
        hasPendingSync = true
    }

    private func scheduleFlush(immediate: Bool = false) {
        guard summary != nil else { return }
        guard !isFlushingChanges else { return }
        flushTask?.cancel()
        let delay = immediate ? UInt64.zero : syncDebounceNanoseconds
        flushTask = Task { [weak self] in
            guard let self else { return }
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            guard !Task.isCancelled else { return }
            await self.flushPendingMutations()
        }
    }

    private func flushPendingMutations() async {
        guard let summary, !pendingMutations.isEmpty, !isFlushingChanges else { return }

        isFlushingChanges = true
        let outgoingMutations = pendingMutations
        pendingMutations.removeAll()
        let desired = currentState()

        do {
            stateUpdatedAt = try await persistSharedState(
                householdID: summary.household.id,
                weekStartDate: summary.weekStartDate,
                state: desired,
                expectedUpdatedAt: stateUpdatedAt
            )
            mutationError = nil
            hasPendingSync = !pendingMutations.isEmpty
        } catch APIError.stale {
            let latest = try? await fetchLatestSharedState(
                householdID: summary.household.id,
                weekStartDate: summary.weekStartDate
            )
            if let latest {
                stateUpdatedAt = latest.updatedAt
                let mergedQueue = outgoingMutations + pendingMutations
                pendingMutations = mergedQueue
                reapplyPendingMutations(on: latest.state)
                hasPendingSync = !pendingMutations.isEmpty
                isFlushingChanges = false
                scheduleFlush(immediate: true)
                return
            } else {
                pendingMutations = outgoingMutations + pendingMutations
                hasPendingSync = true
                mutationError = L10n.string("error.shopping.pendingSync")
                isFlushingChanges = false
                scheduleFlushAfterRetryDelay()
                return
            }
        } catch {
            pendingMutations = outgoingMutations + pendingMutations
            hasPendingSync = true
            mutationError = L10n.string("error.shopping.pendingSync")
            scheduleFlushAfterRetryDelay()
            isFlushingChanges = false
            return
        }

        isFlushingChanges = false
        if !pendingMutations.isEmpty {
            hasPendingSync = true
            scheduleFlush(immediate: true)
        }
    }

    private func scheduleFlushAfterRetryDelay() {
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: retryDelayNanoseconds)
            guard !Task.isCancelled else { return }
            await self.flushPendingMutations()
        }
    }

    private func reapplyPendingMutations(on baseState: MutableShoppingListState) {
        var desired = baseState
        for mutation in pendingMutations {
            mutation.apply(to: &desired)
        }
        applySharedState(
            checkedItems: desired.checkedItems,
            pantryStock: desired.pantryStock,
            customItems: desired.customItems
        )
    }

    private func persistSharedState(
        householdID: String,
        weekStartDate: String,
        state: MutableShoppingListState,
        expectedUpdatedAt: String?
    ) async throws -> String? {
        try await apiClient.updateShoppingListState(
            householdID: householdID,
            weekStartDate: weekStartDate,
            checkedItems: Array(state.checkedItems),
            pantryStock: state.pantryStock,
            expectedUpdatedAt: expectedUpdatedAt,
            customItems: state.customItems
        )
    }

    private func fetchLatestSharedState(
        householdID: String,
        weekStartDate: String
    ) async throws -> (state: MutableShoppingListState, updatedAt: String?) {
        let latest = try await apiClient.shoppingListState(
            householdID: householdID,
            weekStartDate: weekStartDate
        )
        return (
            state: MutableShoppingListState(
                checkedItems: Set(latest.state?.checkedItems ?? []),
                pantryStock: latest.state?.pantryStock ?? [:],
                customItems: latest.state?.customItems ?? []
            ),
            updatedAt: latest.updatedAt
        )
    }
}

private struct MutableShoppingListState {
    var checkedItems: Set<String>
    var pantryStock: [String: Double]
    var customItems: [ShoppingCustomItem]
}

private enum ShoppingListMutation {
    case toggleChecked(String)
    case addCustomItem(ShoppingCustomItem)
    case removeCustomItem(String)

    func apply(to state: inout MutableShoppingListState) {
        switch self {
        case .toggleChecked(let key):
            if state.checkedItems.contains(key) {
                state.checkedItems.remove(key)
            } else {
                state.checkedItems.insert(key)
            }
        case .addCustomItem(let item):
            state.customItems.removeAll { $0.itemKey == item.itemKey }
            state.customItems.append(item)
        case .removeCustomItem(let itemKey):
            state.customItems.removeAll { $0.itemKey == itemKey }
            state.checkedItems.remove(itemKey)
        }
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

    static func map(from summary: ShoppingListSummary) -> (groups: [ShoppingListGroup], stapledItems: [ShoppingListItem], customItems: [ShoppingCustomItem]) {
        var extracted: [ShoppingListItem] = []
        let customItems = summary.groups.flatMap { group in
            group.items
                .filter(\.isCustom)
                .map { ShoppingCustomItem(itemKey: $0.itemKey, label: $0.label, category: group.category) }
        }

        let filteredGroups = summary.groups
            .compactMap { group -> ShoppingListGroup? in
                let (regular, staples) = group.items.reduce(
                    into: ([ShoppingListItem](), [ShoppingListItem]())
                ) { acc, item in
                    if item.isCustom {
                        acc.0.append(item)
                    } else if isStaple(item.label) {
                        acc.1.append(item)
                    } else {
                        acc.0.append(item)
                    }
                }
                extracted.append(contentsOf: staples)
                guard !regular.isEmpty else { return nil }
                return ShoppingListGroup(category: group.category, items: regular)
            }
            .filter { !$0.items.isEmpty }
            .sorted { ShoppingCategory.from($0.category).sortIndex < ShoppingCategory.from($1.category).sortIndex }

        return (filteredGroups, extracted, customItems)
    }

    static func regularGroups(from groups: [ShoppingListGroup]) -> [ShoppingListGroup] {
        groups
            .map { group in
                ShoppingListGroup(category: group.category, items: group.items.filter { !$0.isCustom })
            }
            .filter { !$0.items.isEmpty }
            .sorted { ShoppingCategory.from($0.category).sortIndex < ShoppingCategory.from($1.category).sortIndex }
    }

    static func inject(
        customItems: [ShoppingCustomItem],
        into groups: [ShoppingListGroup],
        checkedItems: Set<String>
    ) -> [ShoppingListGroup] {
        let nonCustomGroups = groups
            .map { group in
                ShoppingListGroup(category: group.category, items: group.items.filter { !$0.isCustom })
            }
            .filter { !$0.items.isEmpty }

        guard !customItems.isEmpty else {
            return nonCustomGroups.sorted { ShoppingCategory.from($0.category).sortIndex < ShoppingCategory.from($1.category).sortIndex }
        }

        var merged = Dictionary(uniqueKeysWithValues: nonCustomGroups.map { ($0.category, $0.items) })
        for item in customItems {
            let current = merged[item.category] ?? []
            merged[item.category] = current + [
                ShoppingListItem(
                    itemKey: item.itemKey,
                    label: item.label,
                    amount: nil,
                    unit: nil,
                    checked: checkedItems.contains(item.itemKey),
                    isCustom: true
                ),
            ]
        }

        return merged
            .map { category, items in
                ShoppingListGroup(
                    category: category,
                    items: items.sorted { left, right in
                        if left.isCustom != right.isCustom { return left.isCustom && !right.isCustom }
                        return left.label.localizedCaseInsensitiveCompare(right.label) == .orderedAscending
                    }
                )
            }
            .sorted { ShoppingCategory.from($0.category).sortIndex < ShoppingCategory.from($1.category).sortIndex }
    }
}

protocol ShoppingListStoreAPIClient {
    func shoppingListSummary(householdID: String, weekStartDate: String) async throws -> ShoppingListSummary
    func shoppingListState(householdID: String, weekStartDate: String) async throws -> (state: ShoppingListSharedState?, updatedAt: String?)
    func updateShoppingListState(
        householdID: String,
        weekStartDate: String,
        checkedItems: [String],
        pantryStock: [String: Double],
        expectedUpdatedAt: String?,
        customItems: [ShoppingCustomItem]
    ) async throws -> String?
}

extension VecklyAPIClient: ShoppingListStoreAPIClient {}

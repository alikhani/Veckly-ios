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
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "produce": return .produce
        case "meat", "protein": return .meat
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
    private var inFlightMutations: [ShoppingListMutation] = []
    private var mutationContext: ShoppingListSyncContext?
    private var flushTask: Task<Void, Never>?
    private var isFlushingChanges = false
    private var needsFlushWhenSummaryLoads = false
    private var loadGeneration = 0
    private var stateRevision = 0

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

    /// Clears the freshness timestamp so the next call to `loadCurrentWeek`
    /// always fetches from the server. Call this after any week plan mutation
    /// (assign/unassign meal, generate week) so the shopping list stays in sync.
    func invalidateCache() { lastFetchedAt = nil }

    /// `force` bypasses the freshness cache below — see the identical
    /// parameter on `WeekStore.loadCurrentWeek` for why `AppRefreshCoordinator`
    /// needs it for forcing triggers (pull-to-refresh, household switch).
    func loadCurrentWeek(household: Household, weekStartDate: String, force: Bool = false) async {
        let requestedContext = ShoppingListSyncContext(householdID: household.id, weekStartDate: weekStartDate)
        guard await prepareForLoad(context: requestedContext) else { return }
        guard !isLoading else { return }
        let hasFreshRequestedWeek = !force
            && lastFetchedAt.map { Date().timeIntervalSince($0) <= 300 } == true
            && summary?.weekStartDate == weekStartDate
        guard !hasFreshRequestedWeek else { return }
        isLoading = summary == nil
        errorMessage = nil
        loadGeneration += 1
        let generation = loadGeneration
        let revision = stateRevision
        defer { isLoading = false }

        do {
            async let summaryResult = apiClient.shoppingListSummary(householdID: household.id, weekStartDate: weekStartDate)
            async let stateResult = apiClient.shoppingListState(householdID: household.id, weekStartDate: weekStartDate)

            let summary = try await summaryResult
            let state = try await stateResult
            guard generation == loadGeneration else { return }
            self.summary = summary
            lastFetchedAt = Date()
            let mapped = ShoppingListViewModelMapper.map(from: summary)
            regularGroups = ShoppingListViewModelMapper.regularGroups(from: mapped.groups)
            stapledItems = mapped.stapledItems
            let fallbackCheckedItems = Set((mapped.groups.flatMap(\.items) + mapped.stapledItems).filter(\.checked).map(\.itemKey))
            if revision == stateRevision {
                var desired = MutableShoppingListState(
                    checkedItems: state.state.map { Set($0.checkedItems) } ?? fallbackCheckedItems,
                    pantryStock: state.state?.pantryStock ?? [:],
                    customItems: state.state?.customItems ?? mapped.customItems
                )
                for mutation in mutations(for: requestedContext) {
                    mutation.apply(to: &desired)
                }
                applySharedState(desired)
                stateUpdatedAt = state.updatedAt ?? summary.updatedAt
            } else {
                // A local edit or completed write won the race with this GET.
                // Keep that newer shared state while still accepting the
                // refreshed shopping-list structure above.
                applySharedState(currentState())
            }
            if needsFlushWhenSummaryLoads {
                needsFlushWhenSummaryLoads = false
                scheduleFlush(immediate: true)
            }
        } catch APIError.notFound {
            guard generation == loadGeneration else { return }
            summary = nil
            groups = []
            regularGroups = []
            stapledItems = []
            if mutationContext == requestedContext {
                var desired = MutableShoppingListState(checkedItems: [], pantryStock: [:], customItems: [])
                for mutation in mutations(for: requestedContext) {
                    mutation.apply(to: &desired)
                }
                applySharedState(desired)
            } else {
                customItems = []
                checkedItems = []
                pantryStock = [:]
            }
        } catch is CancellationError {
            // `.onAppear` and `.task(id: weekStartDate)` both fire on tab
            // appearance, and `.task` gets cancelled/restarted whenever this
            // view leaves and rejoins the visible hierarchy (tab switches,
            // scene backgrounding). A cancelled in-flight request is not a
            // real failure — surfacing it as one wiped an already-loaded list
            // and forced the user to tap "Try again" to get back what was
            // already there a moment ago.
        } catch let urlError as URLError where urlError.code == .cancelled {
            // Same cancellation case, but thrown as URLError instead of
            // CancellationError depending on which await point was cancelled.
        } catch {
            guard summary == nil else { return }
            errorMessage = L10n.string("error.shopping.load")
        }
    }

    func toggleItem(key: String) async {
        setItemChecked(key: key, isChecked: !checkedItems.contains(key))
    }

    func setItemChecked(key: String, isChecked: Bool) {
        mutationError = nil
        applyLocalMutation(.setChecked(key: key, isChecked: isChecked))
        scheduleFlush()
    }

    func addCustomItem(label: String, category: ShoppingCategory = .other) {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !customItems.contains(where: { isSameCustomItem($0, label: trimmed, category: category.backendValue) }) else { return }

        let customItem = ShoppingCustomItem(
            itemKey: "custom:\(UUID().uuidString.lowercased())",
            label: trimmed,
            category: category.backendValue
        )
        mutationError = nil
        applyLocalMutation(.addCustomItem(customItem))
        scheduleFlush()
    }

    /// Unchecks all currently-checked items and returns their keys so the caller
    /// can offer an undo action that re-checks them.
    @discardableResult
    func bulkClearChecked() -> [String] {
        let cleared = Array(checkedItems)
        guard !cleared.isEmpty else { return [] }
        mutationError = nil
        for key in cleared {
            applyLocalMutation(.setChecked(key: key, isChecked: false))
        }
        scheduleFlush()
        return cleared
    }

    func removeCustomItem(itemKey: String) {
        guard customItems.contains(where: { $0.itemKey == itemKey }) else { return }
        mutationError = nil
        applyLocalMutation(.removeCustomItem(itemKey))
        scheduleFlush()
    }

    func reset(discardPendingMutations: Bool = false) {
        loadGeneration += 1
        flushTask?.cancel()
        flushTask = nil
        if discardPendingMutations {
            pendingMutations = []
            inFlightMutations = []
            mutationContext = nil
            hasPendingSync = false
            isFlushingChanges = false
        } else if !pendingMutations.isEmpty, !isFlushingChanges {
            scheduleFlush(immediate: true)
        }
        if !discardPendingMutations, hasPendingSync {
            // Keep the optimistic snapshot alive until the explicitly-scoped
            // write finishes. The following load waits for that write before
            // publishing another household/week.
            errorMessage = nil
            mutationError = nil
            isLoading = false
            lastFetchedAt = nil
            return
        }
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
        needsFlushWhenSummaryLoads = !pendingMutations.isEmpty
    }

    func seedForUITests() {
        groups = [
            ShoppingListGroup(
                category: "Pantry",
                items: [ShoppingListItem(itemKey: "pantry:spaghetti:g", label: "spaghetti", amount: "400", unit: "g", checked: false)]
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
        self.customItems = deduplicatedCustomItems(customItems)
        groups = ShoppingListViewModelMapper.inject(
            customItems: self.customItems,
            into: regularGroups,
            checkedItems: checkedItems
        )
    }

    private func applySharedState(_ state: MutableShoppingListState) {
        applySharedState(
            checkedItems: state.checkedItems,
            pantryStock: state.pantryStock,
            customItems: state.customItems
        )
    }

    private func deduplicatedCustomItems(_ items: [ShoppingCustomItem]) -> [ShoppingCustomItem] {
        var seen: Set<String> = []
        return items.filter { item in
            let key = shoppingCustomItemIdentity(label: item.label, category: item.category)
            return seen.insert(key).inserted
        }
    }

    private func isSameCustomItem(_ item: ShoppingCustomItem, label: String, category: String) -> Bool {
        shoppingCustomItemIdentity(label: item.label, category: item.category) == shoppingCustomItemIdentity(label: label, category: category)
    }

    private func currentState() -> MutableShoppingListState {
        MutableShoppingListState(
            checkedItems: checkedItems,
            pantryStock: pantryStock,
            customItems: customItems
        )
    }

    private func applyLocalMutation(_ mutation: ShoppingListMutation) {
        guard let context = currentContext else { return }
        guard mutationContext == nil || mutationContext == context else {
            mutationError = L10n.string("error.shopping.pendingSync")
            return
        }
        mutationContext = context
        var desired = currentState()
        mutation.apply(to: &desired)
        applySharedState(desired)
        enqueue(mutation)
        stateRevision += 1
        updatePendingSyncState()
    }

    private func scheduleFlush(immediate: Bool = false) {
        guard mutationContext != nil else {
            needsFlushWhenSummaryLoads = true
            return
        }
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
        guard let context = mutationContext, !pendingMutations.isEmpty, !isFlushingChanges else { return }

        isFlushingChanges = true
        let outgoingMutations = pendingMutations
        pendingMutations.removeAll()
        let desired = currentState()
        inFlightMutations = outgoingMutations
        updatePendingSyncState()

        do {
            stateUpdatedAt = try await persistSharedState(
                householdID: context.householdID,
                weekStartDate: context.weekStartDate,
                state: desired,
                expectedUpdatedAt: stateUpdatedAt
            )
            guard mutationContext == context else {
                finishFlush()
                return
            }
            inFlightMutations = []
            stateRevision += 1
            mutationError = nil
            updatePendingSyncState()
        } catch APIError.stale {
            let latest = try? await fetchLatestSharedState(
                householdID: context.householdID,
                weekStartDate: context.weekStartDate
            )
            guard mutationContext == context else {
                finishFlush()
                return
            }
            if let latest {
                stateUpdatedAt = latest.updatedAt
                pendingMutations = coalesced(outgoingMutations + pendingMutations)
                inFlightMutations = []
                reapplyPendingMutations(on: latest.state)
                stateRevision += 1
                updatePendingSyncState()
                isFlushingChanges = false
                scheduleFlush(immediate: true)
                return
            } else {
                restoreOutgoingMutations(outgoingMutations)
                mutationError = L10n.string("error.shopping.pendingSync")
                isFlushingChanges = false
                scheduleFlushAfterRetryDelay()
                return
            }
        } catch {
            restoreOutgoingMutations(outgoingMutations)
            mutationError = L10n.string("error.shopping.pendingSync")
            scheduleFlushAfterRetryDelay()
            isFlushingChanges = false
            return
        }

        isFlushingChanges = false
        if !pendingMutations.isEmpty {
            updatePendingSyncState()
            scheduleFlush(immediate: true)
        } else {
            mutationContext = nil
            updatePendingSyncState()
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
        applySharedState(desired)
    }

    private var currentContext: ShoppingListSyncContext? {
        guard let summary else { return nil }
        return ShoppingListSyncContext(
            householdID: summary.household.id,
            weekStartDate: summary.weekStartDate
        )
    }

    private func prepareForLoad(context: ShoppingListSyncContext) async -> Bool {
        guard let mutationContext, mutationContext != context else { return true }

        while isFlushingChanges {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        if !pendingMutations.isEmpty {
            await flushPendingMutations()
        }
        guard self.mutationContext == nil else {
            mutationError = L10n.string("error.shopping.pendingSync")
            return false
        }
        return true
    }

    private func mutations(for context: ShoppingListSyncContext) -> [ShoppingListMutation] {
        guard mutationContext == context else { return [] }
        return inFlightMutations + pendingMutations
    }

    private func enqueue(_ mutation: ShoppingListMutation) {
        if case .setChecked(let key, _) = mutation {
            pendingMutations.removeAll { $0.checkedItemKey == key }
        }
        pendingMutations.append(mutation)
    }

    private func coalesced(_ mutations: [ShoppingListMutation]) -> [ShoppingListMutation] {
        var result: [ShoppingListMutation] = []
        for mutation in mutations {
            if case .setChecked(let key, _) = mutation {
                result.removeAll { $0.checkedItemKey == key }
            }
            result.append(mutation)
        }
        return result
    }

    private func restoreOutgoingMutations(_ outgoing: [ShoppingListMutation]) {
        pendingMutations = coalesced(outgoing + pendingMutations)
        inFlightMutations = []
        updatePendingSyncState()
    }

    private func finishFlush() {
        inFlightMutations = []
        isFlushingChanges = false
        updatePendingSyncState()
    }

    private func updatePendingSyncState() {
        hasPendingSync = !pendingMutations.isEmpty || !inFlightMutations.isEmpty
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

private struct ShoppingListSyncContext: Equatable {
    let householdID: String
    let weekStartDate: String
}

private func shoppingCustomItemIdentity(_ item: ShoppingCustomItem) -> String {
    shoppingCustomItemIdentity(label: item.label, category: item.category)
}

private func shoppingCustomItemIdentity(label: String, category: String) -> String {
    let normalizedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let normalizedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return "\(normalizedCategory):\(normalizedLabel)"
}

private enum ShoppingListMutation {
    case setChecked(key: String, isChecked: Bool)
    case addCustomItem(ShoppingCustomItem)
    case removeCustomItem(String)

    func apply(to state: inout MutableShoppingListState) {
        switch self {
        case .setChecked(let key, let isChecked):
            if isChecked { state.checkedItems.insert(key) }
            else { state.checkedItems.remove(key) }
        case .addCustomItem(let item):
            state.customItems.removeAll { existing in
                existing.itemKey == item.itemKey || shoppingCustomItemIdentity(existing) == shoppingCustomItemIdentity(item)
            }
            state.customItems.append(item)
        case .removeCustomItem(let itemKey):
            state.customItems.removeAll { $0.itemKey == itemKey }
            state.checkedItems.remove(itemKey)
        }
    }

    var checkedItemKey: String? {
        guard case .setChecked(let key, _) = self else { return nil }
        return key
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
                        return
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
        canonicalNonCustomGroups(from: groups)
    }

    static func inject(
        customItems: [ShoppingCustomItem],
        into groups: [ShoppingListGroup],
        checkedItems: Set<String>
    ) -> [ShoppingListGroup] {
        let nonCustomGroups = canonicalNonCustomGroups(from: groups)

        guard !customItems.isEmpty else {
            return nonCustomGroups.sorted { ShoppingCategory.from($0.category).sortIndex < ShoppingCategory.from($1.category).sortIndex }
        }

        var merged = Dictionary(uniqueKeysWithValues: nonCustomGroups.map { ($0.category, $0.items) })
        for item in customItems {
            let category = ShoppingCategory.from(item.category).backendValue
            let current = merged[category] ?? []
            merged[category] = current + [
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
                    items: deduplicatedShoppingItems(items).sorted { left, right in
                        if left.isCustom != right.isCustom { return left.isCustom && !right.isCustom }
                        return left.label.localizedCaseInsensitiveCompare(right.label) == .orderedAscending
                    }
                )
            }
            .sorted { ShoppingCategory.from($0.category).sortIndex < ShoppingCategory.from($1.category).sortIndex }
    }

    private static func canonicalNonCustomGroups(from groups: [ShoppingListGroup]) -> [ShoppingListGroup] {
        var itemsByCategory: [String: [ShoppingListItem]] = [:]
        for group in groups {
            let category = ShoppingCategory.from(group.category).backendValue
            itemsByCategory[category, default: []].append(contentsOf: group.items.filter { !$0.isCustom })
        }

        return itemsByCategory
            .compactMap { category, items in
                let deduplicated = deduplicatedShoppingItems(items)
                return deduplicated.isEmpty ? nil : ShoppingListGroup(category: category, items: deduplicated)
            }
            .sorted { ShoppingCategory.from($0.category).sortIndex < ShoppingCategory.from($1.category).sortIndex }
    }

    private static func deduplicatedShoppingItems(_ items: [ShoppingListItem]) -> [ShoppingListItem] {
        var seen: Set<String> = []
        return items.filter { item in
            seen.insert(item.itemKey).inserted
        }
    }
}

// MARK: - Share text

enum ShoppingListShareText {
    static func make(
        title: String,
        contextLine: String?,
        groups: [ShoppingListGroup],
        staples: [ShoppingListItem],
        checkedItems: Set<String>
    ) -> String? {
        guard groups.contains(where: { !$0.items.isEmpty }) || !staples.isEmpty else { return nil }

        var lines: [String] = [title]
        if let contextLine, !contextLine.isEmpty {
            lines.append(contextLine)
        }

        for group in groups where !group.items.isEmpty {
            lines.append("")
            lines.append(ShoppingCategory.from(group.category).displayLabel)
            lines.append(contentsOf: group.items.map { item in
                itemLine(item, checkedItems: checkedItems)
            })
        }

        if !staples.isEmpty {
            lines.append("")
            lines.append(L10n.string("shopping.likelyAtHome"))
            lines.append(contentsOf: staples.map { item in
                itemLine(item, checkedItems: checkedItems)
            })
        }

        return lines.joined(separator: "\n")
    }

    private static func itemLine(
        _ item: ShoppingListItem,
        checkedItems: Set<String>
    ) -> String {
        let state = checkedItems.contains(item.itemKey) ? "x" : " "
        let amountLabel = [item.amount, item.unit].compactMap { $0 }.joined(separator: " ")
        let suffix = amountLabel.isEmpty ? "" : " \(amountLabel)"
        return "- [\(state)] \(item.label)\(suffix)"
    }

    static func reminderItems(
        groups: [ShoppingListGroup],
        checkedItems: Set<String>
    ) -> [String] {
        groups.flatMap(\.items).compactMap { item in
            guard !checkedItems.contains(item.itemKey) else { return nil }
            let amountLabel = [item.amount, item.unit].compactMap { $0 }.joined(separator: " ")
            return amountLabel.isEmpty ? item.label : "\(item.label) \(amountLabel)"
        }
    }
}

enum ShoppingListHandoffState: Equatable {
    case ready(totalItems: Int, checkedItems: Int)
    case completed(totalItems: Int)

    static func make(groups: [ShoppingListGroup], checkedItems: Set<String>) -> ShoppingListHandoffState? {
        let itemKeys = groups.flatMap { $0.items.map(\.itemKey) }
        guard !itemKeys.isEmpty else { return nil }

        let checkedCount = itemKeys.filter { checkedItems.contains($0) }.count
        if checkedCount >= itemKeys.count {
            return .completed(totalItems: itemKeys.count)
        }
        return .ready(totalItems: itemKeys.count, checkedItems: checkedCount)
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

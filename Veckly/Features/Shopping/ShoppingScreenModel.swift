import Foundation
import Observation

struct ShoppingReminderExportNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

extension ShoppingListHandoffState {
    var isCompleted: Bool {
        switch self {
        case .completed: true
        case .ready: false
        }
    }
}

/// Owns the Shopping tab's user intents and the orchestration between
/// stores (shopping list, week, household) that used to live inline in
/// `ShoppingListTabView`. The view renders; this decides.
///
/// Depends on concrete stores plus closures for product events, the
/// core-reader reload and the Reminders export — never on `AppModel`, so it
/// can be built directly in unit tests.
@MainActor
@Observable
final class ShoppingScreenModel {
    // MARK: Dependencies

    private let shoppingListStore: ShoppingListStore
    private let weekStore: WeekStore
    private let householdStore: HouseholdStore
    private let usesSeededCoreReader: Bool
    private let reloadCoreReader: (AppRefreshCoordinator.Trigger) async -> Void
    private let exportReminders: (_ items: [String], _ listTitle: String, _ notes: String?) async throws -> Int
    private let recordEvent: (ProductEventName, String?, ProductEventProperties) -> Void
    /// How long the "Items cleared · Undo" toast stays up. Injectable so
    /// tests don't have to wait out the real 4 seconds.
    private let clearedUndoDuration: Duration

    // MARK: Screen state

    /// The one sheet the Shopping tab is presenting, if any.
    var sheet: ShoppingSheet?
    /// Keys unchecked by the last "Clear checked" — non-empty while the
    /// undo toast is showing.
    private(set) var clearedKeys: [String] = []
    private(set) var isExportingReminders = false
    var reminderExportNotice: ShoppingReminderExportNotice?
    @ObservationIgnored private var undoTask: Task<Void, Never>?
    @ObservationIgnored private var reportedCompletedShoppingListWeeks: Set<String> = []

    /// The work started by the most recent fire-and-forget intent. The view
    /// never awaits it — it exists so tests can wait for an intent's effects
    /// deterministically.
    private(set) var lastTask: Task<Void, Never>?

    init(
        shoppingListStore: ShoppingListStore,
        weekStore: WeekStore,
        householdStore: HouseholdStore,
        usesSeededCoreReader: Bool,
        reloadCoreReader: @escaping (AppRefreshCoordinator.Trigger) async -> Void,
        exportReminders: @escaping (_ items: [String], _ listTitle: String, _ notes: String?) async throws -> Int,
        recordEvent: @escaping (ProductEventName, String?, ProductEventProperties) -> Void,
        clearedUndoDuration: Duration = .seconds(4)
    ) {
        self.shoppingListStore = shoppingListStore
        self.weekStore = weekStore
        self.householdStore = householdStore
        self.usesSeededCoreReader = usesSeededCoreReader
        self.reloadCoreReader = reloadCoreReader
        self.exportReminders = exportReminders
        self.recordEvent = recordEvent
        self.clearedUndoDuration = clearedUndoDuration
    }

    // MARK: Store state

    var groups: [ShoppingListGroup] { shoppingListStore.groups }
    var stapledItems: [ShoppingListItem] { shoppingListStore.stapledItems }
    var checkedItems: Set<String> { shoppingListStore.checkedItems }
    var categoryOrder: [ShoppingCategory] { shoppingListStore.categoryOrder }
    var mutationError: String? { shoppingListStore.mutationError }
    var hasPendingSync: Bool { shoppingListStore.hasPendingSync }
    /// Fresher data has arrived that differs from the list on screen.
    var hasPendingUpdate: Bool { shoppingListStore.hasPendingUpdate }

    /// The "updates available" banner's button.
    func showPendingUpdate() {
        shoppingListStore.applyPendingUpdate()
    }
    var hasActiveHousehold: Bool { householdStore.activeHousehold != nil }
    /// The week the list belongs to — the view reloads when it changes.
    var weekStartDate: String { weekStore.weekStartDate }

    var showsLoadingPanel: Bool {
        CoreLoadingGate.shouldShowLoadingPanel(
            isLoadingHouseholds: householdStore.isLoading,
            isLoadingContent: shoppingListStore.isLoading,
            hasActiveHousehold: householdStore.activeHousehold != nil,
            householdErrorMessage: householdStore.errorMessage,
            hasLoadedContentOnce: shoppingListStore.hasLoadedOnce,
            contentErrorMessage: shoppingListStore.errorMessage,
            hasRestoredContent: shoppingListStore.isShowingRestoredList
        )
    }

    var loadErrorMessage: String? {
        CoreLoadingGate.blockingErrorMessage(
            contentError: shoppingListStore.errorMessage,
            householdError: householdStore.errorMessage,
            hasRestoredContent: shoppingListStore.isShowingRestoredList
        )
    }

    var isListEmpty: Bool {
        shoppingListStore.groups.isEmpty && shoppingListStore.stapledItems.isEmpty
    }

    /// A week plan exists but all meals are skipped/unassigned.
    var hasWeekPlan: Bool { shoppingListStore.summary != nil }

    // MARK: Derived

    var totalItemCount: Int {
        shoppingListStore.groups.flatMap { $0.items }.count
    }

    /// Progress counts only checked items that are on the list right now. The
    /// persisted checked set also holds the keys of items whose meal was since
    /// swapped, rescued or removed, and those must not count ("7 / 5").
    var checkedItemCount: Int {
        let listKeys = Set(shoppingListStore.groups.flatMap { $0.items.map(\.itemKey) })
        return shoppingListStore.checkedItems.intersection(listKeys).count
    }

    /// Something on the list — a regular item or a "likely at home" staple — is checked.
    var hasCheckedItemsOnList: Bool {
        let listKeys = Set(shoppingListStore.groups.flatMap { $0.items.map(\.itemKey) })
            .union(shoppingListStore.stapledItems.map(\.itemKey))
        return !shoppingListStore.checkedItems.isDisjoint(with: listKeys)
    }

    /// "V.26 · 2 MIDDAGAR" — nil if data is unavailable.
    var weekContextLine: String? {
        let weekStartString = weekStore.weekStartDate
        guard WeekCalendar.date(from: weekStartString) != nil else { return nil }

        let weekNumber = WeekCalendar.weekNumber(for: weekStartString)

        let dayRows = weekStore.currentWeekDayRows
        let mealCount = dayRows.filter { $0.recipe != nil }.count

        var parts: [String] = [L10n.format("format.week", weekNumber)]
        if mealCount > 0 {
            parts.append(L10n.format(mealCount == 1 ? "format.meals.one" : "format.meals.other", mealCount))
        }

        return parts.joined(separator: " · ")
    }

    var shareText: String? {
        ShoppingListShareText.make(
            title: L10n.string("shopping.title"),
            contextLine: weekContextLine,
            groups: shoppingListStore.groups,
            staples: shoppingListStore.stapledItems,
            checkedItems: shoppingListStore.checkedItems
        )
    }

    var reminderItems: [String] {
        let reminderItems = ShoppingListShareText.reminderItems(
            groups: shoppingListStore.groups,
            checkedItems: shoppingListStore.checkedItems
        )

        if !reminderItems.isEmpty {
            return reminderItems
        }

        return shareText.map { [$0] } ?? []
    }

    var remindersExportButtonLabel: String {
        let count = reminderItems.count
        let key = count == 1 ? "shopping.reminders.export.one" : "shopping.reminders.export.other"
        return L10n.format(key, count)
    }

    var handoffState: ShoppingListHandoffState? {
        ShoppingListHandoffState.make(
            groups: shoppingListStore.groups,
            checkedItems: shoppingListStore.checkedItems
        )
    }

    // MARK: Sheets

    func presentCustomItemSheet() {
        sheet = .customItem
    }

    func presentCategoryOrderSheet() {
        sheet = .categoryOrder
    }

    // MARK: Item intents

    func toggleItem(_ key: String) {
        lastTask = Task { await shoppingListStore.toggleItem(key: key) }
    }

    func addCustomItem(label: String, category: ShoppingCategory) {
        shoppingListStore.addCustomItem(label: label, category: category)
    }

    func removeCustomItem(_ key: String) {
        shoppingListStore.removeCustomItem(itemKey: key)
    }

    func dismissMutationError() {
        shoppingListStore.clearMutationError()
    }

    /// Silent no-op without an active household (the sheet that calls this
    /// is only shown when one exists).
    func saveCategoryOrder(_ order: [ShoppingCategory]) async {
        guard let household = householdStore.activeHousehold else { return }
        await shoppingListStore.updateCategoryOrder(order, householdID: household.id)
    }

    // MARK: Clear checked / undo

    func clearChecked() {
        let keys = shoppingListStore.bulkClearChecked()
        guard !keys.isEmpty else { return }
        clearedKeys = keys
        undoTask?.cancel()
        let duration = clearedUndoDuration
        undoTask = Task {
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            clearedKeys = []
        }
    }

    func undoClearChecked() {
        undoTask?.cancel()
        let keys = clearedKeys
        clearedKeys = []
        lastTask = Task {
            for key in keys {
                shoppingListStore.setItemChecked(key: key, isChecked: true)
            }
        }
    }

    // MARK: Loading

    /// Re-fetch the shopping list whenever the tab becomes visible so that
    /// mutations made on the Week tab (add/remove/generate) are reflected
    /// here. `ShoppingListStore.loadCurrentWeek` short-circuits if data is
    /// fresh (< 5 min), so this is cheap during normal browsing and only
    /// hits the network after `invalidateCache()` is called following a
    /// week plan change.
    ///
    /// Unlike the Week tab, this tab was never migrated onto
    /// `AppRefreshCoordinator` (Fas 7's migration only covered the Week
    /// tab), so it needs its own `usesSeededCoreReader` guard — without it,
    /// seeded UI-test mode still made a real network call here and silently
    /// overwrote the seeded shopping list with a load-error banner.
    func tabDidAppear() {
        guard !usesSeededCoreReader else { return }
        guard let household = householdStore.activeHousehold else { return }
        let weekStartDate = weekStore.weekStartDate
        lastTask = Task { await shoppingListStore.loadCurrentWeek(household: household, weekStartDate: weekStartDate) }
    }

    /// Run from `.task(id: weekStartDate)`.
    func weekDidChange() async {
        guard !usesSeededCoreReader else { return }
        guard let household = householdStore.activeHousehold else { return }
        let weekStartDate = weekStore.weekStartDate
        await shoppingListStore.loadCurrentWeek(household: household, weekStartDate: weekStartDate)
    }

    /// Pull-to-refresh: always fetches, bypassing the freshness cache.
    func refresh() async {
        guard let household = householdStore.activeHousehold else { return }
        let weekStartDate = weekStore.weekStartDate
        shoppingListStore.invalidateCache()
        await shoppingListStore.loadCurrentWeek(household: household, weekStartDate: weekStartDate, origin: .userInitiated)
    }

    /// The load-error panel's "Try again".
    func retryLoad() {
        lastTask = Task { await reloadCoreReader(.pullToRefresh) }
    }

    // MARK: Reminders export

    func exportToReminders() async {
        guard !isExportingReminders else { return }
        isExportingReminders = true
        defer { isExportingReminders = false }

        do {
            let count = try await exportReminders(
                reminderItems,
                L10n.string("shopping.title"),
                weekContextLine
            )
            reminderExportNotice = ShoppingReminderExportNotice(
                title: L10n.string("shopping.reminders.success.title"),
                message: L10n.format(
                    count == 1 ? "shopping.reminders.success.message.one" : "shopping.reminders.success.message.other",
                    count
                )
            )
            recordEvent(.shoppingShared, weekStore.weekStartDate, [
                "items": .int(count),
                "checkedItems": .int(checkedItemCount)
            ])
        } catch ShoppingListReminderExportError.accessDenied {
            reminderExportNotice = ShoppingReminderExportNotice(
                title: L10n.string("shopping.reminders.denied.title"),
                message: L10n.string("shopping.reminders.denied.message")
            )
        } catch {
            reminderExportNotice = ShoppingReminderExportNotice(
                title: L10n.string("shopping.reminders.error.title"),
                message: L10n.string("shopping.reminders.error.message")
            )
        }
    }

    // MARK: Product events

    /// Called when the handoff state's completion flips; logs
    /// `shoppingMainListCompleted` at most once per week per screen.
    func handoffCompletionDidChange(isCompleted: Bool?) {
        guard isCompleted == true else { return }
        let weekStartDate = weekStore.weekStartDate
        guard reportedCompletedShoppingListWeeks.insert(weekStartDate).inserted else { return }
        recordEvent(.shoppingMainListCompleted, weekStartDate, [
            "items": .int(totalItemCount)
        ])
    }
}

extension ShoppingScreenModel {
    static func live(_ app: AppModel) -> ShoppingScreenModel {
        let reminderExporter = ShoppingListReminderExporter()
        return ShoppingScreenModel(
            shoppingListStore: app.shoppingListStore,
            weekStore: app.weekStore,
            householdStore: app.householdStore,
            usesSeededCoreReader: app.usesSeededCoreReader,
            reloadCoreReader: { trigger in
                await app.loadCoreReader(trigger: trigger)
            },
            exportReminders: { items, listTitle, notes in
                try await reminderExporter.export(items: items, listTitle: listTitle, notes: notes)
            },
            recordEvent: { eventName, weekStartDate, properties in
                app.recordProductEvent(eventName, weekStartDate: weekStartDate, properties: properties)
            }
        )
    }
}

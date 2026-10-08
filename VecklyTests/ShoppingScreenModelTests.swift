import Foundation
import Testing
@testable import Veckly

/// `ShoppingScreenModel` owns the Shopping tab's intents and the
/// orchestration between the shopping list, week and household stores.
/// Driven through real stores over fake API clients, like
/// `WeekScreenModelTests`.
@MainActor
struct ShoppingScreenModelTests {
    // MARK: Derived state

    @Test func itemCountsExcludeLikelyAtHomeStaples() async {
        let harness = await ShoppingScreenHarness.make(checked: ["produce:apples:", "pantry:salt:"])

        #expect(harness.model.totalItemCount == 2)
        #expect(harness.model.stapledItems.map(\.itemKey) == ["pantry:salt:"])
        #expect(harness.model.checkedItemCount == 1)
    }

    /// Keys of items whose meal was since swapped, rescued or removed stay in the
    /// persisted checked set. They must not count towards progress ("7 / 5").
    @Test func progressIgnoresCheckedKeysOfItemsThatLeftTheList() async {
        let harness = await ShoppingScreenHarness.make(
            checked: ["produce:apples:", "produce:swapped-out:", "dairy:removed:", "pantry:gone:"]
        )

        #expect(harness.model.totalItemCount == 2)
        #expect(harness.model.checkedItemCount == 1)
    }

    @Test func clearCheckedIsOnlyOfferedWhenSomethingOnTheListIsChecked() async {
        let onlyStale = await ShoppingScreenHarness.make(checked: ["produce:swapped-out:"])
        #expect(!onlyStale.model.hasCheckedItemsOnList)

        let aListItem = await ShoppingScreenHarness.make(checked: ["produce:apples:"])
        #expect(aListItem.model.hasCheckedItemsOnList)

        let aStaple = await ShoppingScreenHarness.make(checked: ["pantry:salt:"])
        #expect(aStaple.model.hasCheckedItemsOnList)
    }

    @Test func theContextLineNamesTheWeekAndItsPlannedDinners() async {
        let harness = await ShoppingScreenHarness.make()
        let weekStartDate = harness.weekStore.weekStartDate
        let mealCount = harness.weekStore.currentWeekDayRows.filter { $0.recipe != nil }.count

        #expect(mealCount > 1)
        #expect(harness.model.weekContextLine == [
            L10n.format("format.week", WeekCalendar.weekNumber(for: weekStartDate)),
            L10n.format("format.meals.other", mealCount)
        ].joined(separator: " · "))
    }

    @Test func remindersFallBackToTheShareTextOnceEverythingIsChecked() async {
        let harness = await ShoppingScreenHarness.make(checked: ["produce:apples:", "produce:carrots:"])

        #expect(harness.model.reminderItems.count == 1)
        #expect(harness.model.reminderItems.first == harness.model.shareText)
    }

    // MARK: Sheets

    @Test func eachHeaderActionRequestsItsOwnSheet() async {
        let harness = await ShoppingScreenHarness.make()
        #expect(harness.model.sheet == nil)

        harness.model.presentCustomItemSheet()
        #expect(harness.model.sheet == .customItem)

        harness.model.presentCategoryOrderSheet()
        #expect(harness.model.sheet == .categoryOrder)
    }

    // MARK: Clear checked / undo

    @Test func clearCheckedOffersAnUndoThatRechecksTheClearedItems() async {
        let harness = await ShoppingScreenHarness.make(checked: ["produce:apples:"])

        harness.model.clearChecked()
        #expect(harness.model.clearedKeys == ["produce:apples:"])
        #expect(harness.model.checkedItems.isEmpty)

        harness.model.undoClearChecked()
        await harness.model.lastTask?.value

        #expect(harness.model.clearedKeys.isEmpty)
        #expect(harness.model.checkedItems == ["produce:apples:"])
    }

    @Test func theUndoToastDismissesItselfAfterItsTimeout() async throws {
        let harness = await ShoppingScreenHarness.make(checked: ["produce:apples:"], clearedUndoDuration: .milliseconds(10))

        harness.model.clearChecked()
        #expect(!harness.model.clearedKeys.isEmpty)

        try await Task.sleep(for: .milliseconds(200))
        #expect(harness.model.clearedKeys.isEmpty)
        #expect(harness.model.checkedItems.isEmpty)
    }

    @Test func clearCheckedWithNothingCheckedOffersNoUndo() async {
        let harness = await ShoppingScreenHarness.make()

        harness.model.clearChecked()

        #expect(harness.model.clearedKeys.isEmpty)
    }

    // MARK: Loading

    @Test func appearingLoadsTheCurrentWeeksList() async {
        let harness = await ShoppingScreenHarness.make(loadsList: false)

        harness.model.tabDidAppear()
        await harness.model.lastTask?.value

        #expect(harness.shoppingAPI.summaryRequests == [harness.weekStore.weekStartDate])
        #expect(harness.model.totalItemCount == 2)
    }

    @Test func seededUITestModeNeverLoadsFromTheNetwork() async {
        let harness = await ShoppingScreenHarness.make(loadsList: false, usesSeededCoreReader: true)

        harness.model.tabDidAppear()
        await harness.model.lastTask?.value
        await harness.model.weekDidChange()

        #expect(harness.shoppingAPI.summaryRequests.isEmpty)
    }

    @Test func pullToRefreshBypassesTheFreshnessCache() async {
        let harness = await ShoppingScreenHarness.make()
        harness.shoppingAPI.summaryRequests = []

        await harness.model.weekDidChange()
        #expect(harness.shoppingAPI.summaryRequests.isEmpty)

        await harness.model.refresh()
        #expect(harness.shoppingAPI.summaryRequests == [harness.weekStore.weekStartDate])
    }

    @Test func retryingAfterALoadErrorReloadsTheCoreReaderAsAnExplicitRefresh() async {
        let harness = await ShoppingScreenHarness.make()

        harness.model.retryLoad()
        await harness.model.lastTask?.value

        #expect(harness.coreReaderReloads == [.pullToRefresh])
    }

    // MARK: Category order

    @Test func savingTheCategoryOrderWritesItForTheActiveHousehold() async {
        let harness = await ShoppingScreenHarness.make()
        let order: [ShoppingCategory] = [.dairy, .produce, .meat, .pantry, .frozen, .bakery, .other]

        await harness.model.saveCategoryOrder(order)

        #expect(harness.shoppingAPI.preferenceUpdates == [order.map(\.preferenceValue)])
        #expect(harness.model.categoryOrder == order)
    }

    @Test func savingTheCategoryOrderWithoutAHouseholdIsANoOp() async {
        let harness = await ShoppingScreenHarness.make(hasHousehold: false)

        await harness.model.saveCategoryOrder([.dairy, .produce, .meat, .pantry, .frozen, .bakery, .other])

        #expect(harness.shoppingAPI.preferenceUpdates.isEmpty)
    }

    // MARK: Reminders export

    @Test func aSuccessfulExportConfirmsAndLogsShoppingShared() async {
        let harness = await ShoppingScreenHarness.make(checked: ["produce:apples:"])

        await harness.model.exportToReminders()

        #expect(harness.exportedItems == [["carrots 2"]])
        #expect(harness.model.reminderExportNotice?.title == L10n.string("shopping.reminders.success.title"))
        #expect(!harness.model.isExportingReminders)
        let shared = harness.events.filter { $0.name == .shoppingShared }
        #expect(shared.count == 1)
        #expect(shared.first?.weekStartDate == harness.weekStore.weekStartDate)
        #expect(shared.first?.properties == ["items": .int(1), "checkedItems": .int(1)])
    }

    @Test func aDeniedExportExplainsAccessAndLogsNothing() async {
        let harness = await ShoppingScreenHarness.make()
        harness.exportError = ShoppingListReminderExportError.accessDenied

        await harness.model.exportToReminders()

        #expect(harness.model.reminderExportNotice?.title == L10n.string("shopping.reminders.denied.title"))
        #expect(harness.events.isEmpty)
    }

    @Test func aFailedExportShowsTheGenericErrorAndLogsNothing() async {
        let harness = await ShoppingScreenHarness.make()
        harness.exportError = ShoppingListReminderExportError.noReminderCalendar

        await harness.model.exportToReminders()

        #expect(harness.model.reminderExportNotice?.title == L10n.string("shopping.reminders.error.title"))
        #expect(harness.events.isEmpty)
    }

    // MARK: Completion event

    @Test func completingTheMainListIsLoggedOncePerWeek() async {
        let harness = await ShoppingScreenHarness.make()

        harness.model.handoffCompletionDidChange(isCompleted: nil)
        harness.model.handoffCompletionDidChange(isCompleted: false)
        harness.model.handoffCompletionDidChange(isCompleted: true)
        harness.model.handoffCompletionDidChange(isCompleted: true)

        let completed = harness.events.filter { $0.name == .shoppingMainListCompleted }
        #expect(completed.count == 1)
        #expect(completed.first?.properties == ["items": .int(2)])
    }
}

// MARK: - Harness

@MainActor
private final class ShoppingScreenHarness {
    let shoppingAPI = ShoppingScreenFakeShoppingAPI()
    let weekAPI = WeekScreenFakeAPIClient()
    let shoppingListStore: ShoppingListStore
    let weekStore: WeekStore
    let householdStore: HouseholdStore
    var exportError: Error?
    private(set) var exportedItems: [[String]] = []
    private(set) var coreReaderReloads: [AppRefreshCoordinator.Trigger] = []
    private(set) var events: [(name: ProductEventName, weekStartDate: String?, properties: ProductEventProperties)] = []
    private(set) var model: ShoppingScreenModel!

    private init(usesSeededCoreReader: Bool, clearedUndoDuration: Duration) {
        shoppingListStore = ShoppingListStore(apiClient: shoppingAPI, syncDebounceNanoseconds: 60_000_000_000)
        weekStore = WeekStore(apiClient: weekAPI)
        householdStore = HouseholdStore(apiClient: weekAPI, selectionStore: ShoppingScreenFakeSelectionStore())
        model = ShoppingScreenModel(
            shoppingListStore: shoppingListStore,
            weekStore: weekStore,
            householdStore: householdStore,
            usesSeededCoreReader: usesSeededCoreReader,
            reloadCoreReader: { [unowned self] trigger in
                coreReaderReloads.append(trigger)
            },
            exportReminders: { [unowned self] items, _, _ in
                if let exportError { throw exportError }
                exportedItems.append(items)
                return items.count
            },
            recordEvent: { [unowned self] name, weekStartDate, properties in
                events.append((name, weekStartDate, properties))
            },
            clearedUndoDuration: clearedUndoDuration
        )
    }

    /// An active household, the current week loaded and (by default) its
    /// shopping list loaded: Apples + Carrots, plus Salt as a staple.
    static func make(
        hasHousehold: Bool = true,
        loadsList: Bool = true,
        checked: [String] = [],
        usesSeededCoreReader: Bool = false,
        clearedUndoDuration: Duration = .seconds(60)
    ) async -> ShoppingScreenHarness {
        let harness = ShoppingScreenHarness(usesSeededCoreReader: usesSeededCoreReader, clearedUndoDuration: clearedUndoDuration)
        harness.shoppingAPI.checkedItems = checked
        guard hasHousehold else { return harness }
        let household = WeekScreenFixtures.household
        harness.householdStore.setActiveHousehold(household)
        await harness.weekStore.loadCurrentWeek(household: household, force: true)
        if loadsList {
            await harness.shoppingListStore.loadCurrentWeek(household: household, weekStartDate: harness.weekStore.weekStartDate)
        }
        return harness
    }
}

private final class ShoppingScreenFakeShoppingAPI: ShoppingListStoreAPIClient {
    var checkedItems: [String] = []
    var summaryRequests: [String] = []
    private(set) var preferenceUpdates: [[String]] = []

    func shoppingListSummary(householdID: String, weekStartDate: String) async throws -> ShoppingListSummary {
        summaryRequests.append(weekStartDate)
        return ShoppingListSummary(
            household: SummaryHousehold(id: householdID, name: "Test household"),
            weekStartDate: weekStartDate,
            updatedAt: nil,
            groups: [
                ShoppingListGroup(category: "Produce", items: [
                    ShoppingListItem(itemKey: "produce:apples:", label: "apples", amount: "4", unit: nil, checked: false),
                    ShoppingListItem(itemKey: "produce:carrots:", label: "carrots", amount: "2", unit: nil, checked: false),
                ]),
                ShoppingListGroup(category: "Pantry", items: [
                    ShoppingListItem(itemKey: "pantry:salt:", label: "salt", amount: nil, unit: nil, checked: false),
                ]),
            ]
        )
    }

    func shoppingListState(householdID: String, weekStartDate: String) async throws -> (state: ShoppingListSharedState?, updatedAt: String?) {
        (ShoppingListSharedState(checkedItems: checkedItems, pantryStock: [:], customItems: []), nil)
    }

    func updateShoppingListState(
        householdID: String,
        weekStartDate: String,
        checkedItems: [String],
        pantryStock: [String: Double],
        expectedUpdatedAt: String?,
        customItems: [ShoppingCustomItem]
    ) async throws -> String? {
        nil
    }

    func shoppingPreferences(householdID: String) async throws -> ShoppingPreferences {
        ShoppingPreferences(categoryOrder: ShoppingCategory.allCases.map(\.preferenceValue), updatedAt: nil)
    }

    func updateShoppingPreferences(householdID: String, categoryOrder: [String]) async throws -> ShoppingPreferences {
        preferenceUpdates.append(categoryOrder)
        return ShoppingPreferences(categoryOrder: categoryOrder, updatedAt: nil)
    }
}

private final class ShoppingScreenFakeSelectionStore: HouseholdSelectionPersisting {
    func selectedHouseholdID() -> String? { nil }
    func setSelectedHouseholdID(_ householdID: String) {}
    func clearSelectedHouseholdID() {}
}

import Foundation
import Testing
@testable import Veckly

/// `WeekScreenModel` owns the Week tab's intents and the orchestration
/// between stores. These tests drive it through real stores backed by one
/// fake API client, the same pattern as the `WeekStore*Tests`.
@MainActor
struct WeekScreenModelTests {
    // MARK: Session + mutations

    @Test func aMissingUserIDTriggersUnauthorizedHandlingAndMutatesNothing() async {
        let harness = await WeekScreenHarness.make(signedIn: false)
        let day = harness.row(.sunday)

        let started = harness.model.assignMeal(day, recipe: WeekScreenFixtures.recipe)
        await harness.model.lastTask?.value

        #expect(!started)
        #expect(harness.unauthorizedCount == 1)
        #expect(harness.api.weekEvents.isEmpty)
        #expect(harness.api.shoppingSummaryRequests.isEmpty)
    }

    @Test func noActiveHouseholdIsASilentNoOp() async {
        let harness = await WeekScreenHarness.make(hasHousehold: false)

        let started = harness.model.toggleSkip(WeekScreenFixtures.anyRow())
        await harness.model.lastTask?.value

        #expect(!started)
        #expect(harness.unauthorizedCount == 0)
        #expect(harness.api.weekEvents.isEmpty)
    }

    @Test func aSuccessfulMutationReloadsTheShoppingListForTheViewedWeek() async {
        let harness = await WeekScreenHarness.make()
        harness.model.viewedWeekOffset = .next
        let nextWeekStart = ViewedWeekOffset.next.weekStartDate
        await harness.weekStore.loadWeek(household: WeekScreenFixtures.household, weekStartDate: nextWeekStart)
        harness.api.shoppingSummaryRequests = []

        let started = harness.model.assignMeal(harness.row(.tuesday), recipe: WeekScreenFixtures.recipe)
        await harness.model.lastTask?.value

        #expect(started)
        #expect(harness.api.weekEvents.map(\.weekStartDate) == [nextWeekStart])
        #expect(harness.api.shoppingSummaryRequests == [nextWeekStart])
    }

    @Test func aFailedMutationDoesNotReloadTheShoppingList() async {
        let harness = await WeekScreenHarness.make()
        harness.api.failsWeekEvents = true
        harness.api.shoppingSummaryRequests = []

        harness.model.unassignMeal(harness.row(.sunday))
        await harness.model.lastTask?.value

        #expect(harness.weekStore.mutationError != nil)
        #expect(harness.api.shoppingSummaryRequests.isEmpty)
    }

    @Test func lockingClearsAStaleMutationErrorBeforeWriting() async {
        let harness = await WeekScreenHarness.make()
        harness.api.failsWeekEvents = true
        harness.model.unassignMeal(harness.row(.sunday))
        await harness.model.lastTask?.value
        #expect(harness.weekStore.mutationError != nil)

        let started = harness.model.toggleLock(harness.row(.monday))

        #expect(started)
        #expect(harness.weekStore.mutationError == nil)
    }
}

// MARK: - Harness

enum WeekScreenFixtures {
    static let household = Household(id: "11111111-1111-1111-1111-111111111111", name: "Test household", role: .owner)
    static let recipe = WeekSummaryRecipe(
        id: "recipe-new",
        title: "New dinner",
        description: "",
        servings: 4,
        prepTimeMinutes: 10,
        cookTimeMinutes: 10,
        tags: []
    )

    static func plannedRecipe(_ weekday: Weekday) -> WeekSummaryRecipe {
        WeekSummaryRecipe(
            id: "recipe-\(weekday.rawValue)",
            title: "Dinner \(weekday.rawValue)",
            description: "",
            servings: 4,
            prepTimeMinutes: 10,
            cookTimeMinutes: 10,
            tags: []
        )
    }

    /// Every day planned except `openDays` — Sunday by default, which is
    /// never in the past within the current week, so tests don't depend on
    /// which weekday they run on.
    static func summary(weekStartDate: String, openDays: Set<Weekday> = [.sunday], locked: Set<Weekday> = [], skipped: Set<Weekday> = []) -> WeekSummary {
        WeekSummary(
            household: SummaryHousehold(id: household.id, name: household.name),
            weekStartDate: weekStartDate,
            updatedAt: nil,
            days: Weekday.allCases.enumerated().map { index, weekday in
                let isOpen = openDays.contains(weekday)
                return WeekSummaryDay(
                    dayOfWeek: weekday,
                    date: WeekCalendar.addDays(to: weekStartDate, offset: index),
                    state: skipped.contains(weekday) ? .skipped : isOpen ? .empty : .planned,
                    isLocked: locked.contains(weekday),
                    recipe: isOpen ? nil : plannedRecipe(weekday)
                )
            }
        )
    }

    static func anyRow() -> WeekDayRowViewModel {
        WeekViewModelMapper.map(summary: summary(weekStartDate: WeekCalendar.currentWeekStartDate()), today: Date()).days[0]
    }
}

@MainActor
final class WeekScreenHarness {
    let api: WeekScreenFakeAPIClient
    let weekStore: WeekStore
    let householdStore: HouseholdStore
    let shoppingListStore: ShoppingListStore
    let prepBatchStore: PrepBatchStore
    let recipeStore: RecipeStore
    let authSessionStore: AuthSessionStore
    private(set) var events: [(name: ProductEventName, weekStartDate: String?, properties: ProductEventProperties)] = []
    private(set) var unauthorizedCount = 0
    private(set) var model: WeekScreenModel!

    private init(api: WeekScreenFakeAPIClient) {
        self.api = api
        weekStore = WeekStore(apiClient: api)
        householdStore = HouseholdStore(apiClient: api, selectionStore: WeekScreenFakeSelectionStore())
        shoppingListStore = ShoppingListStore(apiClient: api)
        prepBatchStore = PrepBatchStore(apiClient: api, cacheStore: WeekScreenFakePrepBatchCache())
        recipeStore = RecipeStore(apiClient: api, cacheStore: WeekScreenFakeRecipeCache())
        authSessionStore = AuthSessionStore(authClient: WeekScreenFakeAuthClient(), sessionStorage: WeekScreenFakeSessionStorage())
        model = WeekScreenModel(
            weekStore: weekStore,
            householdStore: householdStore,
            shoppingListStore: shoppingListStore,
            prepBatchStore: prepBatchStore,
            recipeStore: recipeStore,
            authSessionStore: authSessionStore,
            recordEvent: { [unowned self] name, weekStartDate, properties in
                events.append((name, weekStartDate, properties))
            },
            onUnauthorized: { [unowned self] in
                unauthorizedCount += 1
            }
        )
    }

    /// An active household with an all-seven-days planning profile, the
    /// current week loaded, and (by default) a signed-in user.
    static func make(
        signedIn: Bool = true,
        hasHousehold: Bool = true,
        api: WeekScreenFakeAPIClient = WeekScreenFakeAPIClient()
    ) async -> WeekScreenHarness {
        let harness = WeekScreenHarness(api: api)
        if signedIn { harness.authSessionStore.seedForUITests() }
        guard hasHousehold else { return harness }
        harness.householdStore.setActiveHousehold(WeekScreenFixtures.household)
        _ = await harness.householdStore.loadHouseholdDetails(householdID: WeekScreenFixtures.household.id)
        await harness.weekStore.loadCurrentWeek(household: WeekScreenFixtures.household, force: true)
        return harness
    }

    func row(_ weekday: Weekday) -> WeekDayRowViewModel {
        weekStore.dayRows.first { $0.weekday == weekday }!
    }

    func eventCount(_ name: ProductEventName) -> Int {
        events.filter { $0.name == name }.count
    }
}

final class WeekScreenFakeAPIClient:
    WeekStoreAPIClient,
    HouseholdStoreAPIClient,
    ShoppingListStoreAPIClient,
    PrepBatchStoreAPIClient,
    RecipeStoreAPIClient
{
    struct WeekEvent {
        let weekStartDate: String
        let event: WeekPlanEventInput
    }

    /// Summaries keyed by week start; any other week gets the default
    /// "all planned except Sunday" shape.
    var summaries: [String: WeekSummary] = [:]
    var failsWeekEvents = false
    var failsGenerate = false
    /// Applied to the generated week once `generateWeekPlan` succeeds.
    var summaryAfterGenerate: ((String) -> WeekSummary)?
    var recipes: [FullRecipe] = []
    var weekEvents: [WeekEvent] = []
    var generateCalls: [(weekStartDate: String, regenerate: Bool)] = []
    var shoppingSummaryRequests: [String] = []
    var weekSummaryRequests: [String] = []
    /// Lets a test act (e.g. navigate away) while generate is in flight.
    var onGenerate: (() async -> Void)?

    // WeekStoreAPIClient

    func weekSummary(householdID: String, weekStartDate: String) async throws -> WeekSummary {
        weekSummaryRequests.append(weekStartDate)
        return summaries[weekStartDate] ?? WeekScreenFixtures.summary(weekStartDate: weekStartDate)
    }

    func appendWeekPlanEvent(householdID: String, weekStartDate: String, userID: String, event: WeekPlanEventInput) async throws {
        if failsWeekEvents { throw APIError.server(statusCode: 500) }
        weekEvents.append(WeekEvent(weekStartDate: weekStartDate, event: event))
    }

    func generateWeekPlan(householdID: String, weekStartDate: String, regenerate: Bool) async throws {
        generateCalls.append((weekStartDate, regenerate))
        await onGenerate?()
        if failsGenerate { throw APIError.server(statusCode: 500) }
        if let summaryAfterGenerate { summaries[weekStartDate] = summaryAfterGenerate(weekStartDate) }
    }

    func recipe(householdID: String, recipeID: String) async throws -> FullRecipe { throw APIError.notFound }

    // HouseholdStoreAPIClient

    func bootstrapHousehold() async throws -> Household { WeekScreenFixtures.household }
    func listHouseholds() async throws -> [Household] { [WeekScreenFixtures.household] }
    func listMembers(householdID: String) async throws -> [HouseholdMember] {
        [HouseholdMember(userId: "11111111-1111-1111-1111-111111111111", role: .owner, givenName: nil, familyName: nil)]
    }
    func getProfile(householdID: String) async throws -> HouseholdProfile? {
        HouseholdProfile(
            householdId: householdID,
            adults: 2,
            children: 1,
            priorities: [],
            avoidIngredients: [],
            selectedDays: Weekday.allCases.map { HouseholdDaySelection(day: $0) }
        )
    }
    func saveProfile(
        householdID: String,
        adults: Int,
        children: Int,
        priorities: [HouseholdPriority],
        avoidIngredients: [String],
        selectedDays: [HouseholdDaySelection]
    ) async throws -> HouseholdProfile {
        HouseholdProfile(householdId: householdID, adults: adults, children: children, priorities: priorities, avoidIngredients: avoidIngredients, selectedDays: selectedDays)
    }
    func createInvite(householdID: String) async throws -> HouseholdInvite { throw APIError.notFound }
    func listInvites(householdID: String) async throws -> [HouseholdInvite] { [] }
    func revokeInvite(householdID: String, inviteID: String) async throws {}
    func lookupInvite(token: String) async throws -> InviteLanding { throw APIError.notFound }
    func acceptInvite(token: String) async throws -> String { WeekScreenFixtures.household.id }
    func renameHousehold(householdID: String, name: String) async throws {}
    func removeMember(householdID: String, userID: String) async throws {}
    func deleteHousehold(householdID: String) async throws {}
    func weekPulse(householdID: String, weekStartDate: String) async throws -> WeekPulse { throw APIError.notFound }
    func saveWeekPulse(householdID: String, weekStartDate: String, draft: WeekPulseDraft) async throws -> WeekPulse { throw APIError.notFound }

    // ShoppingListStoreAPIClient

    func shoppingListSummary(householdID: String, weekStartDate: String) async throws -> ShoppingListSummary {
        shoppingSummaryRequests.append(weekStartDate)
        return ShoppingListSummary(household: SummaryHousehold(id: householdID, name: "Test household"), weekStartDate: weekStartDate, updatedAt: nil, groups: [])
    }
    func shoppingListState(householdID: String, weekStartDate: String) async throws -> (state: ShoppingListSharedState?, updatedAt: String?) {
        (nil, nil)
    }
    func updateShoppingListState(
        householdID: String,
        weekStartDate: String,
        checkedItems: [String],
        pantryStock: [String: Double],
        expectedUpdatedAt: String?,
        customItems: [ShoppingCustomItem]
    ) async throws -> String? { nil }
    func shoppingPreferences(householdID: String) async throws -> ShoppingPreferences { throw APIError.notFound }
    func updateShoppingPreferences(householdID: String, categoryOrder: [String]) async throws -> ShoppingPreferences { throw APIError.notFound }

    // PrepBatchStoreAPIClient

    func listPrepBatches(householdID: String, from: String, to: String) async throws -> [PrepBatch] { [] }
    func createPrepBatch(
        householdID: String,
        recipeId: String?,
        cookDate: String,
        totalPortions: Int,
        assignments: [(date: String, mealType: MealType)]
    ) async throws -> PrepBatch {
        throw APIError.notFound
    }
    func deletePrepBatch(householdID: String, batchID: String) async throws {}
    func removeAssignment(householdID: String, batchID: String, date: String, mealType: MealType) async throws {}

    // RecipeStoreAPIClient

    func listHouseholdRecipes(householdID: String, includePublic: Bool) async throws -> [FullRecipe] { recipes }
    func createRecipe(householdID: String, draft: RecipeDraft) async throws -> FullRecipe { throw APIError.notFound }
    func updateRecipe(householdID: String, recipeID: String, draft: RecipeDraft) async throws -> FullRecipe { throw APIError.notFound }
    func archiveRecipe(householdID: String, recipeID: String) async throws -> FullRecipe { throw APIError.notFound }
    func repairIngredientCategories(householdID: String) async throws -> RecipeCategoryRepairResult {
        RecipeCategoryRepairResult(recipesUpdated: 0, ingredientsUpdated: 0)
    }
    func fillInRecipe(householdID: String, title: String, existingIngredients: [DraftIngredient], existingSteps: [String]) async throws -> RecipeDraft { throw APIError.notFound }
    func importRecipeFromURL(householdID: String, _ urlString: String) async throws -> RecipeDraft { throw APIError.notFound }
    func importRecipeFromText(householdID: String, _ text: String, sourceURL: String?) async throws -> RecipeDraft { throw APIError.notFound }
}

private final class WeekScreenFakeSelectionStore: HouseholdSelectionPersisting {
    private var selectedID: String?
    func selectedHouseholdID() -> String? { selectedID }
    func setSelectedHouseholdID(_ householdID: String) { selectedID = householdID }
    func clearSelectedHouseholdID() { selectedID = nil }
}

private final class WeekScreenFakePrepBatchCache: PrepBatchStoreCachePersisting {
    func loadBatches(householdID: String, weekStartDate: String) -> PersistedPrepBatchCache? { nil }
    func saveBatches(_ cache: PersistedPrepBatchCache) {}
    func deleteBatches(householdID: String, weekStartDate: String) {}
}

private final class WeekScreenFakeRecipeCache: RecipeStoreCachePersisting {
    func loadRecipes(householdID: String) -> PersistedRecipeCache? { nil }
    func saveRecipes(_ cache: PersistedRecipeCache) {}
    func deleteRecipes(householdID: String) {}
}

private final class WeekScreenFakeSessionStorage: AuthSessionPersisting {
    func load() -> AuthSession? { nil }
    func save(_ session: AuthSession) {}
    func clear() {}
}

private final class WeekScreenFakeAuthClient: AuthServicing {
    func signInWithEmail(email: String, password: String) async throws -> AuthSession { throw APIError.notFound }
    func signUpWithEmail(email: String, password: String, redirectTo: URL) async throws -> AuthSession? { nil }
    func signInWithApple(identityToken: String, nonce: String?) async throws -> AuthSession { throw APIError.notFound }
    func resendSignupConfirmation(email: String, redirectTo: URL) async throws {}
    func requestPasswordReset(email: String, redirectTo: URL) async throws {}
    func updatePassword(_ password: String, accessToken: String) async throws {}
    func deleteUser(accessToken: String) async throws {}
    func refreshSession(refreshToken: String) async throws -> AuthSession { throw APIError.notFound }
}

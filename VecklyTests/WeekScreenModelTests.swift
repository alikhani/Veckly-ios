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
    // MARK: Generate, undo, session end

    @Test func regenerateOffersNoUndoWhenTheUserNavigatedAwayDuringTheCall() async {
        let harness = await WeekScreenHarness.make()
        harness.api.onGenerate = { @MainActor in
            harness.model.viewedWeekOffset = .next
        }

        await harness.model.performGenerate(regenerate: true)

        #expect(harness.api.generateCalls.map(\.weekStartDate) == [WeekCalendar.currentWeekStartDate()])
        #expect(harness.model.regenerateUndo == nil)
    }

    @Test func regenerateOnTheSameWeekSnapshotsOnlyOpenUnlockedUnskippedDays() async {
        let weekStartDate = WeekCalendar.currentWeekStartDate()
        let api = WeekScreenFakeAPIClient()
        api.summaries[weekStartDate] = WeekScreenFixtures.summary(
            weekStartDate: weekStartDate,
            locked: [.monday],
            skipped: [.tuesday]
        )
        let harness = await WeekScreenHarness.make(api: api)
        let expected = harness.weekStore.dayRows
            .filter { !$0.isPast && !$0.isLocked && !$0.isSkipped }
            .map(\.weekday)

        await harness.model.performGenerate(regenerate: true)

        let undo = harness.model.regenerateUndo
        #expect(undo?.weekStartDate == weekStartDate)
        #expect(undo?.rows.map(\.weekday) == expected)
        #expect(undo?.rows.contains { $0.weekday == .monday || $0.weekday == .tuesday } == false)
        #expect(undo?.rows.contains { $0.weekday == .sunday } == true)
    }

    @Test func theUndoBannerDismissesItselfAfterItsTimeout() async throws {
        let harness = await WeekScreenHarness.make(regenerateUndoDuration: .milliseconds(10))

        await harness.model.performGenerate(regenerate: true)
        #expect(harness.model.regenerateUndo != nil)

        try await Task.sleep(for: .milliseconds(200))
        #expect(harness.model.regenerateUndo == nil)
    }

    @Test func undoReplaysTheSnapshotIntoTheWeekItWasTakenFrom() async {
        let harness = await WeekScreenHarness.make()
        await harness.model.performGenerate(regenerate: true)
        guard let context = harness.model.regenerateUndo else {
            Issue.record("Expected an undo context after regenerate")
            return
        }
        harness.api.weekEvents = []

        harness.model.undoRegenerate(context)
        await harness.model.lastTask?.value

        #expect(harness.model.regenerateUndo == nil)
        #expect(harness.api.weekEvents.count == context.rows.count)
        #expect(Set(harness.api.weekEvents.map(\.weekStartDate)) == [context.weekStartDate])
    }

    @Test func undoForAWeekOtherThanTheViewedOneMutatesNothing() async {
        let harness = await WeekScreenHarness.make()
        await harness.model.performGenerate(regenerate: true)
        guard let context = harness.model.regenerateUndo else {
            Issue.record("Expected an undo context after regenerate")
            return
        }
        harness.api.weekEvents = []
        harness.model.viewedWeekOffset = .next

        harness.model.undoRegenerate(context)
        await harness.model.lastTask?.value

        #expect(harness.model.regenerateUndo == nil)
        #expect(harness.api.weekEvents.isEmpty)
    }

    @Test func navigatingToAnotherWeekDropsUndoAndFillNotices() async {
        let harness = await WeekScreenHarness.make()
        await harness.model.performGenerate(regenerate: true)
        #expect(harness.model.regenerateUndo != nil)

        harness.model.viewedWeekOffset = .next
        harness.model.viewedWeekDidChange()

        #expect(harness.model.regenerateUndo == nil)
        #expect(harness.model.failedFillWeekStartDate == nil)
        #expect(harness.model.fillCompletionNotice == nil)
    }

    @Test func theFirstFillOfAnEmptyWeekLogsFirstWeekGeneratedExactlyOnce() async {
        let weekStartDate = WeekCalendar.currentWeekStartDate()
        let api = WeekScreenFakeAPIClient()
        api.summaries[weekStartDate] = WeekScreenFixtures.summary(weekStartDate: weekStartDate, openDays: Set(Weekday.allCases))
        api.summaryAfterGenerate = { WeekScreenFixtures.summary(weekStartDate: $0, openDays: []) }
        let harness = await WeekScreenHarness.make(api: api)
        #expect(!harness.weekStore.hasWeekContent)

        await harness.model.performGenerate(regenerate: false)
        await harness.model.performGenerate(regenerate: false)

        #expect(harness.api.generateCalls.count == 2)
        #expect(harness.eventCount(.firstWeekGenerated) == 1)
        #expect(harness.events.first { $0.name == .firstWeekGenerated }?.weekStartDate == weekStartDate)
    }

    @Test func aFailedFillRemembersWhichWeekFailed() async {
        let harness = await WeekScreenHarness.make()
        harness.api.failsGenerate = true

        await harness.model.performGenerate(regenerate: false)

        #expect(harness.model.failedFillWeekStartDate == WeekCalendar.currentWeekStartDate())
        #expect(harness.model.fillCompletionNotice == nil)
        #expect(harness.eventCount(.firstWeekGenerated) == 0)

        harness.model.dismissWeekMutationError()
        #expect(harness.model.failedFillWeekStartDate == nil)
        #expect(harness.weekStore.mutationError == nil)
    }

    @Test func aSuccessfulFillOnTheViewedWeekShowsACompletionNotice() async {
        let weekStartDate = WeekCalendar.currentWeekStartDate()
        let api = WeekScreenFakeAPIClient()
        api.summaryAfterGenerate = { WeekScreenFixtures.summary(weekStartDate: $0, openDays: [], reason: .quickWeekday) }
        let harness = await WeekScreenHarness.make(api: api)

        await harness.model.performGenerate(regenerate: false)

        #expect(harness.api.generateCalls.map(\.weekStartDate) == [weekStartDate])
        #expect(harness.model.fillCompletionNotice != nil)
        #expect(harness.model.failedFillWeekStartDate == nil)
    }

    @Test func fillingTheLastOpenDayEndsTheSessionAndLogsWeekCompleted() async {
        let harness = await WeekScreenHarness.make()
        #expect(harness.model.hasOpenRelevantDays)

        harness.model.assignMeal(harness.row(.sunday), recipe: WeekScreenFixtures.recipe)
        await harness.model.lastTask?.value

        #expect(!harness.model.hasOpenRelevantDays)
        #expect(harness.model.showSessionEndBeat)
        #expect(harness.eventCount(.weekCompleted) == 1)

        harness.model.dismissSessionEndBeat()
        #expect(!harness.model.showSessionEndBeat)
    }

    @Test func completingAWeekOtherThanTheCurrentOneDoesNotEndTheSession() async {
        let harness = await WeekScreenHarness.make()
        harness.model.viewedWeekOffset = .next
        await harness.weekStore.loadWeek(household: WeekScreenFixtures.household, weekStartDate: ViewedWeekOffset.next.weekStartDate)
        #expect(harness.model.hasOpenRelevantDays)

        harness.model.assignMeal(harness.row(.sunday), recipe: WeekScreenFixtures.recipe)
        await harness.model.lastTask?.value

        #expect(!harness.model.hasOpenRelevantDays)
        #expect(!harness.model.showSessionEndBeat)
        #expect(harness.eventCount(.weekCompleted) == 0)
    }

    // MARK: Quality suggestions, deep links, loading

    @Test func aLeftoversSuggestionOpensThePrepBatchSheetAndDismissesTheSuggestion() async {
        let harness = await WeekScreenHarness.make()
        let source = harness.row(.monday)
        let suggestion = WeekQualitySuggestion(kind: .useLeftovers, day: harness.row(.sunday), replacement: nil, sourceDay: source)

        harness.model.applyQualitySuggestion(suggestion)
        #expect(harness.model.sheet == nil)
        await harness.model.lastTask?.value

        guard case let .prepBatch(seed) = harness.model.sheet else {
            Issue.record("Expected the prep batch sheet, got \(String(describing: harness.model.sheet))")
            return
        }

        #expect(seed.recipeID == source.recipe?.id)
        #expect(seed.cookDate == source.date)
        #expect(seed.assignedDate == harness.row(.sunday).date)
        #expect(seed.weekStartDate == WeekCalendar.currentWeekStartDate())
        #expect(harness.model.dismissedQualitySuggestionKeys == ["\(WeekScreenFixtures.household.id):\(WeekCalendar.currentWeekStartDate())"])
        #expect(harness.defaults.string(forKey: WeekScreenModel.dismissedQualitySuggestionKeysKey) == "\(WeekScreenFixtures.household.id):\(WeekCalendar.currentWeekStartDate())")
        #expect(harness.api.weekEvents.isEmpty)
    }

    @Test func aReplacementSuggestionAssignsTheRecipeThenDismissesTheSuggestion() async {
        let harness = await WeekScreenHarness.make()
        let suggestion = WeekQualitySuggestion(kind: .fillOpenDay, day: harness.row(.sunday), replacement: WeekScreenFixtures.fullRecipe, sourceDay: nil)

        harness.model.applyQualitySuggestion(suggestion)
        await harness.model.lastTask?.value

        #expect(harness.model.sheet == nil)
        #expect(harness.api.weekEvents.count == 1)
        if case let .mealAssigned(day, recipeID) = harness.api.weekEvents.first?.event {
            #expect(day == .sunday)
            #expect(recipeID == WeekScreenFixtures.fullRecipe.id)
        } else {
            Issue.record("Expected a mealAssigned event")
        }
        #expect(!harness.model.dismissedQualitySuggestionKeys.isEmpty)
        #expect(harness.model.showSessionEndBeat)
    }

    @Test func aFailedReplacementKeepsTheSuggestionVisible() async {
        let harness = await WeekScreenHarness.make()
        harness.api.failsWeekEvents = true
        let suggestion = WeekQualitySuggestion(kind: .fillOpenDay, day: harness.row(.sunday), replacement: WeekScreenFixtures.fullRecipe, sourceDay: nil)

        harness.model.applyQualitySuggestion(suggestion)
        await harness.model.lastTask?.value

        #expect(harness.model.dismissedQualitySuggestionKeys.isEmpty)
        #expect(!harness.model.showSessionEndBeat)
    }

    @Test func dismissedQualitySuggestionKeysSurviveANewModel() async {
        let harness = await WeekScreenHarness.make()
        harness.model.dismissQualitySuggestionsForViewedWeek()
        harness.model.viewedWeekOffset = .next
        harness.model.dismissQualitySuggestionsForViewedWeek()

        let stored = harness.defaults.string(forKey: WeekScreenModel.dismissedQualitySuggestionKeysKey)
        let id = WeekScreenFixtures.household.id
        #expect(stored == ["\(id):\(WeekCalendar.currentWeekStartDate())", "\(id):\(ViewedWeekOffset.next.weekStartDate)"].sorted().joined(separator: "|"))
    }

    @Test func aWeekPlanDeepLinkIsConsumedExactlyOnce() async {
        let harness = await WeekScreenHarness.make()
        harness.pendingWeekPlanDeepLink = true

        #expect(harness.model.consumePendingWeekPlanDeepLink())
        #expect(harness.model.viewedWeekOffset == .next)
        #expect(!harness.pendingWeekPlanDeepLink)

        harness.model.viewedWeekOffset = .current
        #expect(!harness.model.consumePendingWeekPlanDeepLink())
        #expect(harness.model.viewedWeekOffset == .current)
    }

    @Test func aMealDeepLinkOpensItsDayExactlyOnce() async {
        let harness = await WeekScreenHarness.make()
        let monday = harness.row(.monday)
        harness.pendingDeepLink = .meal(date: monday.date, recipeID: monday.recipe?.id)

        await harness.model.consumePendingMealDeepLink()

        guard case let .recipe(pair) = harness.model.sheet else {
            Issue.record("Expected the recipe sheet, got \(String(describing: harness.model.sheet))")
            return
        }
        #expect(pair.day.date == monday.date)
        #expect(pair.recipe.id == monday.recipe?.id)
        #expect(harness.pendingDeepLink == nil)

        harness.model.sheet = nil
        await harness.model.consumePendingMealDeepLink()
        #expect(harness.model.sheet == nil)
    }

    @Test func aMealDeepLinkThatNoLongerMatchesIsClearedWithoutOpening() async {
        let harness = await WeekScreenHarness.make()
        let sunday = harness.row(.sunday)
        harness.pendingDeepLink = .meal(date: sunday.date, recipeID: "gone")

        await harness.model.consumePendingMealDeepLink()

        #expect(harness.model.sheet == nil)
        #expect(harness.pendingDeepLink == nil)
    }

    @Test func reloadingTheCurrentWeekGoesThroughTheRefreshCoordinator() async {
        let harness = await WeekScreenHarness.make()
        harness.api.weekSummaryRequests = []

        await harness.model.reloadViewedWeek(trigger: .pullToRefresh)

        #expect(harness.currentWeekRefreshes.count == 1)
        #expect(harness.invalidatedWeekFreshness.isEmpty)
    }

    @Test func browsingToAnotherWeekLoadsItAndInvalidatesCurrentWeekFreshness() async {
        let harness = await WeekScreenHarness.make()
        harness.api.weekSummaryRequests = []
        harness.model.viewedWeekOffset = .last

        await harness.model.reloadViewedWeek()

        #expect(harness.api.weekSummaryRequests == [ViewedWeekOffset.last.weekStartDate])
        #expect(harness.invalidatedWeekFreshness == [WeekScreenFixtures.household.id])
        #expect(harness.currentWeekRefreshes.isEmpty)
    }

    @Test func theSeededCoreReaderNeverLoadsBrowsedWeeksOrLastWeeksRetro() async {
        let harness = await WeekScreenHarness.make(usesSeededCoreReader: true)
        harness.api.weekSummaryRequests = []
        harness.model.viewedWeekOffset = .next

        await harness.model.reloadViewedWeek()
        await harness.model.activeHouseholdDidChange()
        await harness.model.refreshNextWeekEmptyState()

        #expect(harness.api.weekSummaryRequests.isEmpty)
        #expect(harness.invalidatedWeekFreshness.isEmpty)
        #expect(harness.model.nextWeekIsEmpty == nil)
    }

    @Test func dismissingTheWeekendNudgeLastsForToday() async {
        let harness = await WeekScreenHarness.make()
        harness.model.refreshWeekendNudgeDismissalState()
        #expect(!harness.model.weekendNudgeDismissedToday)

        harness.model.dismissWeekendNudgeForToday()
        #expect(harness.model.weekendNudgeDismissedToday)

        harness.defaults.set(Date().addingTimeInterval(-3 * 24 * 60 * 60), forKey: WeekScreenModel.weekendNudgeDismissalKey)
        harness.model.refreshWeekendNudgeDismissalState()
        #expect(!harness.model.weekendNudgeDismissedToday)
    }

    // MARK: Sheet routing

    @Test func presentingTheWeekBriefPinsItToTheViewedWeek() async {
        let harness = await WeekScreenHarness.make()
        harness.model.viewedWeekOffset = .next

        harness.model.presentWeekBrief(regenerate: true)

        guard case let .weekBrief(presentation) = harness.model.sheet else {
            Issue.record("Expected the week brief sheet")
            return
        }
        #expect(presentation.weekStartDate == ViewedWeekOffset.next.weekStartDate)
        #expect(presentation.regenerate)
    }

    @Test func theWeekBriefNeedsASession() async {
        let harness = await WeekScreenHarness.make(signedIn: false)

        harness.model.presentWeekBrief(regenerate: false)
        await harness.model.lastTask?.value

        #expect(harness.model.sheet == nil)
        #expect(harness.unauthorizedCount == 1)
    }

    @Test func aSheetsOwnDismissNeverClosesTheSheetThatReplacedIt() async {
        let harness = await WeekScreenHarness.make()
        let detail = WeekSheet.dayDetail(harness.row(.monday))
        harness.model.sheet = .mealPicker(harness.row(.sunday))

        harness.model.dismissSheet(detail.id)
        #expect(harness.model.sheet?.id == WeekSheet.mealPicker(harness.row(.sunday)).id)

        harness.model.dismissSheet(WeekSheet.mealPicker(harness.row(.sunday)).id)
        #expect(harness.model.sheet == nil)
    }

    @Test func presentAfterDismissOpensTheNextSheetOnlyAfterTheDelay() async {
        let harness = await WeekScreenHarness.make()
        let day = harness.row(.monday)
        harness.model.sheet = .dayDetail(day)

        harness.model.dismissSheet(WeekSheet.dayDetail(day).id)
        harness.model.presentAfterDismiss { .mealPicker(day) }
        #expect(harness.model.sheet == nil)

        await harness.model.lastTask?.value
        #expect(harness.model.sheet?.id == WeekSheet.mealPicker(day).id)
    }

    @Test func presentAfterDismissWithNothingToShowLeavesSheetsAlone() async {
        let harness = await WeekScreenHarness.make()

        harness.model.presentAfterDismiss { nil }
        await harness.model.lastTask?.value

        #expect(harness.model.sheet == nil)
    }

    @Test func everySheetCaseHasADistinctIdentity() async {
        let harness = await WeekScreenHarness.make()
        let day = harness.row(.monday)
        let seed = PrepBatchSeed(recipeID: "r", cookDate: day.date, weekStartDate: WeekCalendar.currentWeekStartDate())
        let sheets: [WeekSheet] = [
            .recipe(SelectedDayRecipe(day: day, recipe: day.recipe!)),
            .mealPicker(day),
            .rescue(day),
            .previousWeekProposal,
            .dayDetail(day),
            .prepBatch(seed),
            .leftoversWithoutRecipe(LeftoversWithoutRecipeSeed(day: day, defaultPortions: 4)),
            .weekBrief(WeekBriefPresentation(weekStartDate: WeekCalendar.currentWeekStartDate(), regenerate: false)),
        ]

        #expect(Set(sheets.map(\.id)).count == sheets.count)
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

    static let fullRecipe = FullRecipe(
        id: "recipe-suggested",
        title: "Suggested dinner",
        description: "",
        servings: 4,
        prepTimeMinutes: 10,
        cookTimeMinutes: 10,
        tags: [],
        ingredients: [],
        steps: [],
        userVote: nil
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
    static func summary(
        weekStartDate: String,
        openDays: Set<Weekday> = [.sunday],
        locked: Set<Weekday> = [],
        skipped: Set<Weekday> = [],
        reason: AssignmentReason? = nil
    ) -> WeekSummary {
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
                    recipe: isOpen ? nil : plannedRecipe(weekday),
                    reason: isOpen ? nil : reason
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
    let mealOutcomeStore: MealOutcomeStore
    let defaults: UserDefaults
    var pendingWeekPlanDeepLink = false
    var pendingDeepLink: AppDeepLink?
    private(set) var currentWeekRefreshes: [AppRefreshCoordinator.Trigger] = []
    private(set) var invalidatedWeekFreshness: [String] = []
    private(set) var events: [(name: ProductEventName, weekStartDate: String?, properties: ProductEventProperties)] = []
    private(set) var unauthorizedCount = 0
    private(set) var model: WeekScreenModel!

    private init(api: WeekScreenFakeAPIClient, regenerateUndoDuration: Duration, usesSeededCoreReader: Bool) {
        self.api = api
        mealOutcomeStore = MealOutcomeStore(apiClient: api, pendingStore: WeekScreenFakeOutcomePendingStore())
        let suiteName = "WeekScreenModelTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
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
            mealOutcomeStore: mealOutcomeStore,
            retroClient: api,
            weekBriefClient: api,
            usesSeededCoreReader: usesSeededCoreReader,
            refreshCurrentWeek: { [unowned self] household, trigger in
                currentWeekRefreshes.append(trigger)
                await weekStore.loadCurrentWeek(household: household, force: true)
            },
            invalidateWeekFreshness: { [unowned self] householdID in
                invalidatedWeekFreshness.append(householdID)
            },
            deepLinks: WeekDeepLinkInbox(
                pendingWeekPlan: { [unowned self] in pendingWeekPlanDeepLink },
                clearPendingWeekPlan: { [unowned self] in pendingWeekPlanDeepLink = false },
                pendingDeepLink: { [unowned self] in pendingDeepLink },
                clearPendingDeepLink: { [unowned self] in pendingDeepLink = nil }
            ),
            defaults: defaults,
            recordEvent: { [unowned self] name, weekStartDate, properties in
                events.append((name, weekStartDate, properties))
            },
            onUnauthorized: { [unowned self] in
                unauthorizedCount += 1
            },
            regenerateUndoDuration: regenerateUndoDuration
        )
    }

    /// An active household with an all-seven-days planning profile, the
    /// current week loaded, and (by default) a signed-in user.
    static func make(
        signedIn: Bool = true,
        hasHousehold: Bool = true,
        api: WeekScreenFakeAPIClient = WeekScreenFakeAPIClient(),
        regenerateUndoDuration: Duration = .seconds(60),
        usesSeededCoreReader: Bool = false
    ) async -> WeekScreenHarness {
        let harness = WeekScreenHarness(api: api, regenerateUndoDuration: regenerateUndoDuration, usesSeededCoreReader: usesSeededCoreReader)
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
    RecipeStoreAPIClient,
    MealOutcomeStoreAPIClient,
    RetroCardAPIClient,
    WeekBriefAPIClient
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

    /// Assign/unassign writes are applied to the stored summary, so the
    /// store's post-mutation refetch sees them like it would on the server.
    func appendWeekPlanEvent(householdID: String, weekStartDate: String, userID: String, event: WeekPlanEventInput) async throws {
        if failsWeekEvents { throw APIError.server(statusCode: 500) }
        weekEvents.append(WeekEvent(weekStartDate: weekStartDate, event: event))
        let current = summaries[weekStartDate] ?? WeekScreenFixtures.summary(weekStartDate: weekStartDate)
        let change: (Weekday, WeekSummaryRecipe?)
        switch event {
        case let .mealAssigned(day, recipeID):
            change = (day, WeekSummaryRecipe(id: recipeID, title: recipeID, description: "", servings: 4, prepTimeMinutes: 10, cookTimeMinutes: 10, tags: []))
        case let .mealUnassigned(day):
            change = (day, nil)
        default:
            return
        }
        summaries[weekStartDate] = WeekSummary(
            household: current.household,
            weekStartDate: current.weekStartDate,
            updatedAt: current.updatedAt,
            days: current.days.map { day in
                guard day.dayOfWeek == change.0 else { return day }
                return WeekSummaryDay(
                    dayOfWeek: day.dayOfWeek,
                    date: day.date,
                    state: change.1 == nil ? .empty : .planned,
                    isLocked: day.isLocked,
                    recipe: change.1
                )
            }
        )
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

    // MealOutcomeStoreAPIClient, RetroCardAPIClient, WeekBriefAPIClient

    func mealOutcomes(householdID: String, weekStartDate: String) async throws -> [MealOutcomeRecord] { [] }
    func upsertMealOutcome(_ draft: MealOutcomeDraft) async throws -> MealOutcomeRecord { throw APIError.notFound }
    func familyRecap(householdID: String) async throws -> FamilyRecap { throw APIError.notFound }
    func weekContextOverrides(householdID: String, weekStartDate: String) async throws -> [WeekContextOverride] { [] }
    func upsertWeekContextOverride(householdID: String, weekStartDate: String, override: WeekContextOverride) async throws {}
    func clearWeekContextOverride(householdID: String, weekStartDate: String, date: String) async throws {}
}

private final class WeekScreenFakeOutcomePendingStore: MealOutcomePendingPersisting {
    private var drafts: [MealOutcomeDraft] = []
    func load() -> [MealOutcomeDraft] { drafts }
    func save(_ drafts: [MealOutcomeDraft]) { self.drafts = drafts }
    func delete() { drafts = [] }
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

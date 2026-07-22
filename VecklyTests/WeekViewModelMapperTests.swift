import Foundation
import Testing
@testable import Veckly

struct WeekViewModelMapperTests {
    @Test func mapsPlannedRecipeIntoReadableDayRow() {
        let recipe = WeekSummaryRecipe(
            id: "22222222-2222-2222-2222-222222222222",
            title: "Monday Pasta",
            description: "Fast family pasta",
            servings: 4,
            prepTimeMinutes: 10,
            cookTimeMinutes: 15,
            tags: ["weekday"]
        )
        let summary = WeekSummary(
            household: SummaryHousehold(id: "11111111-1111-1111-1111-111111111111", name: "Test household"),
            weekStartDate: "2026-06-08",
            updatedAt: nil,
            days: [
                WeekSummaryDay(dayOfWeek: .monday, date: "2026-06-08", state: .planned, recipe: recipe),
                WeekSummaryDay(dayOfWeek: .tuesday, date: "2026-06-09", state: .empty, recipe: nil),
            ]
        )
        let today = WeekCalendar.date(from: "2026-06-08")!

        let mapped = WeekViewModelMapper.map(summary: summary, today: today)

        #expect(mapped.days.first?.mealTitle == "Monday Pasta")
        #expect(mapped.days.first?.detail == "\(L10n.format("format.servings", 4)) · 25 min")
        #expect(mapped.days.first?.date == "2026-06-08")
        #expect(mapped.today?.id == "2026-06-08")
        #expect(mapped.days[1].mealTitle == "")
        #expect(mapped.days[1].date == "2026-06-09")
        #expect(mapped.days[1].isEmpty == true)
        #expect(mapped.days[1].isLocked == false)
        #expect(mapped.days[1].isSkipped == false)
    }

    @Test func mapsReasonAndConfidenceFromAnAlgorithmAssignedMeal() {
        let recipe = WeekSummaryRecipe(
            id: "22222222-2222-2222-2222-222222222222",
            title: "Monday Pasta",
            description: "Fast family pasta",
            servings: 4,
            prepTimeMinutes: 10,
            cookTimeMinutes: 15,
            tags: ["weekday"]
        )
        let summary = WeekSummary(
            household: SummaryHousehold(id: "11111111-1111-1111-1111-111111111111", name: "Test household"),
            weekStartDate: "2026-06-08",
            updatedAt: nil,
            days: [
                WeekSummaryDay(dayOfWeek: .monday, date: "2026-06-08", state: .planned, recipe: recipe, reason: .likedBefore, confidence: .low),
            ]
        )
        let today = WeekCalendar.date(from: "2026-06-08")!

        let mapped = WeekViewModelMapper.map(summary: summary, today: today)

        #expect(mapped.days.first?.reason == .likedBefore)
        #expect(mapped.days.first?.confidence == .low)
    }

    @Test func manualReassignmentClearsAnyPreviousReasonAndConfidence() {
        let recipe = WeekSummaryRecipe(
            id: "33333333-3333-3333-3333-333333333333",
            title: "Tuesday Tacos",
            description: "Quick weeknight tacos",
            servings: 4,
            prepTimeMinutes: 10,
            cookTimeMinutes: 15,
            tags: []
        )
        let generated = WeekViewModelMapper.emptyRows(weekStartDate: "2026-06-08")[0]

        let manuallyAssigned = generated.withPlannedRecipe(recipe)

        #expect(manuallyAssigned.reason == nil)
        #expect(manuallyAssigned.confidence == nil)
    }

    @Test func skippingAndLockingPreserveReasonAndConfidence() {
        let recipe = WeekSummaryRecipe(
            id: "44444444-4444-4444-4444-444444444444",
            title: "Wednesday Stew",
            description: "Hearty stew",
            servings: 4,
            prepTimeMinutes: 10,
            cookTimeMinutes: 60,
            tags: []
        )
        let summary = WeekSummary(
            household: SummaryHousehold(id: "11111111-1111-1111-1111-111111111111", name: "Test household"),
            weekStartDate: "2026-06-08",
            updatedAt: nil,
            days: [
                WeekSummaryDay(dayOfWeek: .monday, date: "2026-06-08", state: .planned, recipe: recipe, reason: .backAfterBreak, confidence: .ok),
            ]
        )
        let today = WeekCalendar.date(from: "2026-06-08")!
        let day = WeekViewModelMapper.map(summary: summary, today: today).days[0]

        let skipped = day.withSkipped(true)
        let locked = day.withLocked(true)

        #expect(skipped.reason == .backAfterBreak)
        #expect(skipped.confidence == .ok)
        #expect(locked.reason == .backAfterBreak)
        #expect(locked.confidence == .ok)
    }

    @Test func mapsStreakWeeksFromASatiationEligibleMeal() {
        let recipe = WeekSummaryRecipe(
            id: "55555555-5555-5555-5555-555555555555",
            title: "Friday Salmon",
            description: "Weekend salmon",
            servings: 4,
            prepTimeMinutes: 10,
            cookTimeMinutes: 20,
            tags: []
        )
        let summary = WeekSummary(
            household: SummaryHousehold(id: "11111111-1111-1111-1111-111111111111", name: "Test household"),
            weekStartDate: "2026-06-08",
            updatedAt: nil,
            days: [
                WeekSummaryDay(dayOfWeek: .monday, date: "2026-06-08", state: .planned, recipe: recipe, streakWeeks: 3),
            ]
        )
        let today = WeekCalendar.date(from: "2026-06-08")!

        let mapped = WeekViewModelMapper.map(summary: summary, today: today)

        #expect(mapped.days.first?.streakWeeks == 3)
    }

    @Test func skippingAndLockingPreserveStreakWeeks() {
        let recipe = WeekSummaryRecipe(
            id: "66666666-6666-6666-6666-666666666666",
            title: "Friday Salmon",
            description: "Weekend salmon",
            servings: 4,
            prepTimeMinutes: 10,
            cookTimeMinutes: 20,
            tags: []
        )
        let summary = WeekSummary(
            household: SummaryHousehold(id: "11111111-1111-1111-1111-111111111111", name: "Test household"),
            weekStartDate: "2026-06-08",
            updatedAt: nil,
            days: [
                WeekSummaryDay(dayOfWeek: .monday, date: "2026-06-08", state: .planned, recipe: recipe, streakWeeks: 4),
            ]
        )
        let today = WeekCalendar.date(from: "2026-06-08")!
        let day = WeekViewModelMapper.map(summary: summary, today: today).days[0]

        #expect(day.withSkipped(true).streakWeeks == 4)
        #expect(day.withLocked(true).streakWeeks == 4)
    }

    @Test func manualReassignmentClearsStreakWeeks() {
        let recipe = WeekSummaryRecipe(
            id: "77777777-7777-7777-7777-777777777777",
            title: "Tuesday Tacos",
            description: "Quick weeknight tacos",
            servings: 4,
            prepTimeMinutes: 10,
            cookTimeMinutes: 15,
            tags: []
        )
        let generated = WeekViewModelMapper.emptyRows(weekStartDate: "2026-06-08")[0]

        let manuallyAssigned = generated.withPlannedRecipe(recipe)

        #expect(manuallyAssigned.streakWeeks == nil)
    }

    @Test func withPlannedRecipeAppliesRecipeWhilePreservingDayIdentity() {
        let empty = WeekViewModelMapper.emptyRows(weekStartDate: "2026-06-08")[0].withLocked(true)
        let recipe = WeekSummaryRecipe(
            id: "33333333-3333-3333-3333-333333333333",
            title: "Tuesday Tacos",
            description: "Quick weeknight tacos",
            servings: 4,
            prepTimeMinutes: 10,
            cookTimeMinutes: 15,
            tags: []
        )

        let planned = empty.withPlannedRecipe(recipe)

        #expect(planned.mealTitle == "Tuesday Tacos")
        #expect(planned.detail == "\(L10n.format("format.servings", 4)) · 25 min")
        #expect(planned.isEmpty == false)
        #expect(planned.isSkipped == false)
        #expect(planned.recipe == recipe)
        #expect(planned.isLocked == true)
        #expect(planned.date == empty.date)
        #expect(planned.id == empty.id)
    }

    @Test func emptyRowsCarryTheCorrectIsoDatePerWeekday() {
        let rows = WeekViewModelMapper.emptyRows(weekStartDate: "2026-06-08")

        #expect(rows[0].date == "2026-06-08")
        #expect(rows[1].date == "2026-06-09")
        #expect(rows.allSatisfy { $0.isEmpty })
    }

    /// A week with no day matching "today" (e.g. Last/Next week in the new
    /// week-browsing UI) must map to zero `isToday` rows and a nil `today` —
    /// this is the upstream invariant `WeekTabView`'s hero card relies on to
    /// know it needs its no-today-row guard instead of "Tonight" framing.
    @Test func mapsWeekWithNoMatchingTodayRowToNilToday() {
        let summary = WeekSummary(
            household: SummaryHousehold(id: "11111111-1111-1111-1111-111111111111", name: "Test household"),
            weekStartDate: "2026-06-15",
            updatedAt: nil,
            days: [
                WeekSummaryDay(dayOfWeek: .monday, date: "2026-06-15", state: .empty, recipe: nil),
                WeekSummaryDay(dayOfWeek: .tuesday, date: "2026-06-16", state: .empty, recipe: nil),
            ]
        )
        // "Today" (2026-06-08) falls outside the week being mapped (2026-06-15 week).
        let today = WeekCalendar.date(from: "2026-06-08")!

        let mapped = WeekViewModelMapper.map(summary: summary, today: today)

        #expect(mapped.days.allSatisfy { $0.isToday == false })
        #expect(mapped.today == nil)
    }

    @Test func mapsLockedDayState() {
        let recipe = WeekSummaryRecipe(
            id: "22222222-2222-2222-2222-222222222222",
            title: "Monday Pasta",
            description: "Fast family pasta",
            servings: 4,
            prepTimeMinutes: 10,
            cookTimeMinutes: 15,
            tags: ["weekday"]
        )
        let summary = WeekSummary(
            household: SummaryHousehold(id: "11111111-1111-1111-1111-111111111111", name: "Test household"),
            weekStartDate: "2026-06-08",
            updatedAt: nil,
            days: [
                WeekSummaryDay(dayOfWeek: .monday, date: "2026-06-08", state: .planned, isLocked: true, recipe: recipe),
                WeekSummaryDay(dayOfWeek: .tuesday, date: "2026-06-09", state: .empty, recipe: nil),
            ]
        )
        let today = WeekCalendar.date(from: "2026-06-08")!

        let mapped = WeekViewModelMapper.map(summary: summary, today: today)

        #expect(mapped.days[0].isLocked == true)
        #expect(mapped.days[0].isSkipped == false)
        #expect(mapped.days[1].isLocked == false)
    }

    @Test func mapsSkippedDayState() {
        let summary = WeekSummary(
            household: SummaryHousehold(id: "11111111-1111-1111-1111-111111111111", name: "Test household"),
            weekStartDate: "2026-06-08",
            updatedAt: nil,
            days: [
                WeekSummaryDay(dayOfWeek: .monday, date: "2026-06-08", state: .skipped, recipe: nil),
                WeekSummaryDay(dayOfWeek: .tuesday, date: "2026-06-09", state: .empty, recipe: nil),
            ]
        )
        let today = WeekCalendar.date(from: "2026-06-08")!

        let mapped = WeekViewModelMapper.map(summary: summary, today: today)

        #expect(mapped.days[0].isSkipped == true)
        #expect(mapped.days[0].isEmpty == false)
        #expect(mapped.days[1].isSkipped == false)
        #expect(mapped.days[1].isEmpty == true)
    }

    @MainActor
    @Test func generateWeekShowsNoRecipesMessageWhenPlannerHasNoPool() async {
        let store = WeekStore(apiClient: GenerateFailingWeekStoreAPIClient(error: .noRecipesForGeneration))

        await store.generateWeek(
            household: Household(id: "11111111-1111-1111-1111-111111111111", name: "Test household", role: .owner),
            userID: "33333333-3333-3333-3333-333333333333"
        )

        #expect(store.mutationError == L10n.string("error.week.noRecipes"))
    }

    @MainActor
    @Test func generateWeekShowsAvoidListMessageWhenEveryRecipeIsExcluded() async {
        let store = WeekStore(apiClient: GenerateFailingWeekStoreAPIClient(error: .allRecipesExcludedForGeneration))

        await store.generateWeek(
            household: Household(id: "11111111-1111-1111-1111-111111111111", name: "Test household", role: .owner),
            userID: "33333333-3333-3333-3333-333333333333"
        )

        #expect(store.mutationError != L10n.string("error.week.generate"))
        #expect(store.mutationError != L10n.string("error.week.noRecipes"))
        #expect(store.mutationError?.contains("undvik") == true || store.mutationError?.contains("avoid") == true)
    }

    @MainActor
    @Test func toggleSkipKeepsLocalDayRowWhenAPIRequestFails() async {
        let store = WeekStore(
            apiClient: FailingWeekStoreAPIClient(),
            syncDebounceNanoseconds: 0,
            retryDelayNanoseconds: 60_000_000_000
        )
        store.seedForUITests()

        let monday = store.dayRows.first { $0.weekday == .monday }!
        #expect(monday.recipe != nil)

        await store.toggleSkip(
            day: monday,
            household: Household(id: "11111111-1111-1111-1111-111111111111", name: "Test household", role: .owner),
            userID: "33333333-3333-3333-3333-333333333333"
        )
        try? await Task.sleep(nanoseconds: 20_000_000)

        let updatedMonday = store.dayRows.first { $0.weekday == .monday }!
        #expect(updatedMonday != monday)
        #expect(updatedMonday.isSkipped == true)
        #expect(updatedMonday.isEmpty == false)
        // Skip is a flag layered on top of the assignment, not a deletion — the
        // meal must survive so a quick undo restores it without a refetch.
        #expect(updatedMonday.recipe == monday.recipe)
        #expect(updatedMonday.mealTitle == monday.mealTitle)
        #expect(store.skippedDays.contains(.monday) == true)
        #expect(store.hasPendingSync == true)
        #expect(store.mutationError == L10n.string("error.week.pendingSync"))
    }

    @MainActor
    @Test func toggleSkipThenUndoRestoresTheMealWithoutARefetch() async {
        let store = WeekStore(apiClient: CapturingWeekStoreAPIClient())
        store.seedForUITests()

        let monday = store.dayRows.first { $0.weekday == .monday }!
        #expect(monday.recipe != nil)
        let household = Household(id: "11111111-1111-1111-1111-111111111111", name: "Test household", role: .owner)
        let userID = "33333333-3333-3333-3333-333333333333"

        await store.toggleSkip(day: monday, household: household, userID: userID)
        let skippedMonday = store.dayRows.first { $0.weekday == .monday }!
        #expect(skippedMonday.isSkipped == true)
        #expect(skippedMonday.recipe == monday.recipe)

        await store.toggleSkip(day: skippedMonday, household: household, userID: userID)
        let restoredMonday = store.dayRows.first { $0.weekday == .monday }!
        #expect(restoredMonday.isSkipped == false)
        #expect(restoredMonday.recipe == monday.recipe)
        #expect(restoredMonday.mealTitle == monday.mealTitle)
    }

    @MainActor
    @Test func toggleLockKeepsLocalDayRowWhenAPIRequestFails() async {
        let store = WeekStore(
            apiClient: FailingWeekStoreAPIClient(),
            syncDebounceNanoseconds: 0,
            retryDelayNanoseconds: 60_000_000_000
        )
        store.seedForUITests()

        let monday = store.dayRows.first { $0.weekday == .monday }!
        #expect(monday.isLocked == true)

        await store.toggleLock(
            day: monday,
            household: Household(id: "11111111-1111-1111-1111-111111111111", name: "Test household", role: .owner),
            userID: "33333333-3333-3333-3333-333333333333"
        )
        try? await Task.sleep(nanoseconds: 20_000_000)

        let updatedMonday = store.dayRows.first { $0.weekday == .monday }!
        #expect(updatedMonday != monday)
        #expect(updatedMonday.isLocked == false)
        #expect(store.lockedDays.contains(.monday) == false)
        #expect(store.hasPendingSync == true)
        #expect(store.mutationError == L10n.string("error.week.pendingSync"))
    }

    @MainActor
    @Test func toggleSkipUsesSeededSkippedStateAndPlansDayInstead() async {
        let apiClient = CapturingWeekStoreAPIClient()
        let store = WeekStore(
            apiClient: apiClient,
            syncDebounceNanoseconds: 0,
            retryDelayNanoseconds: 60_000_000_000
        )
        store.seedForUITests()

        let wednesday = store.dayRows.first { $0.weekday == .wednesday }!
        #expect(wednesday.isSkipped == true)
        #expect(store.skippedDays.contains(.wednesday) == true)

        await store.toggleSkip(
            day: wednesday,
            household: Household(id: "11111111-1111-1111-1111-111111111111", name: "Test household", role: .owner),
            userID: "33333333-3333-3333-3333-333333333333"
        )
        try? await Task.sleep(nanoseconds: 20_000_000)

        let plannedWednesday = store.dayRows.first { $0.weekday == .wednesday }!
        #expect(plannedWednesday.isSkipped == false)
        #expect(plannedWednesday.isEmpty == true)
        #expect(store.skippedDays.contains(.wednesday) == false)
        #expect(apiClient.events.count == 1)
        switch apiClient.events.first {
        case .dayUnskipped(day: .wednesday):
            break
        default:
            Issue.record("Expected dayUnskipped for Wednesday")
        }
    }

    @MainActor
    @Test func skippedOnlyWeekCountsAsContentButNotPlannedMeals() async {
        let store = WeekStore(apiClient: CapturingWeekStoreAPIClient())
        store.seedForUITests()

        let monday = store.dayRows.first { $0.weekday == .monday }!
        await store.unassignMeal(
            day: monday,
            household: Household(id: "11111111-1111-1111-1111-111111111111", name: "Test household", role: .owner),
            userID: "33333333-3333-3333-3333-333333333333"
        )

        #expect(store.hasPlannedMeals == false)
        #expect(store.hasWeekContent == true)
    }

    @MainActor
    @Test func toggleSkipUsesCurrentRowStateWhenCapturedDayIsStale() async {
        let apiClient = CapturingWeekStoreAPIClient()
        let store = WeekStore(
            apiClient: apiClient,
            syncDebounceNanoseconds: 0,
            retryDelayNanoseconds: 60_000_000_000
        )
        store.seedForUITests()

        let staleWednesday = WeekDayRowViewModel(
            id: "2026-06-10",
            weekday: .wednesday,
            weekdayLabel: "Wednesday",
            date: "2026-06-10",
            dateLabel: "Jun 10",
            mealTitle: "",
            detail: "",
            isToday: false,
            isEmpty: true,
            isSkipped: false,
            recipe: nil
        )

        await store.toggleSkip(
            day: staleWednesday,
            household: Household(id: "11111111-1111-1111-1111-111111111111", name: "Test household", role: .owner),
            userID: "33333333-3333-3333-3333-333333333333"
        )
        try? await Task.sleep(nanoseconds: 20_000_000)

        #expect(apiClient.events.count == 1)
        switch apiClient.events.first {
        case .dayUnskipped(day: .wednesday):
            break
        default:
            Issue.record("Expected stale Wednesday row to unskip current skipped state")
        }
    }

    @MainActor
    @Test func loadWeekPopulatesDayRowsWithoutMutatingActiveWeekStartDate() async {
        let store = WeekStore(apiClient: StubbedWeekSummaryAPIClient(weekStartDate: "2026-06-15"))
        let activeWeekStartDateBefore = store.weekStartDate

        await store.loadWeek(
            household: Household(id: "11111111-1111-1111-1111-111111111111", name: "Test household", role: .owner),
            weekStartDate: "2026-06-15"
        )

        // Other tabs (Shopping List, Prep) read `weekStartDate` as "the active
        // week" — browsing a different week must never repurpose it.
        #expect(store.weekStartDate == activeWeekStartDateBefore)
        #expect(store.dayRows.first?.id == "2026-06-15")
        #expect(store.summary?.weekStartDate == "2026-06-15")
    }

    @MainActor
    @Test func loadCurrentWeekRefetchesWhenFreshSummaryBelongsToAnotherWeek() async {
        let currentWeek = WeekCalendar.currentWeekStartDate()
        let previousWeek = WeekCalendar.addWeeks(to: currentWeek, offset: -1)
        let apiClient = SequencedWeekSummaryAPIClient(
            summaries: [
                makeWeekSummary(weekStartDate: previousWeek),
                makeWeekSummary(weekStartDate: currentWeek),
            ]
        )
        let store = WeekStore(apiClient: apiClient)
        let household = Household(id: "11111111-1111-1111-1111-111111111111", name: "Test household", role: .owner)

        await store.loadCurrentWeek(household: household)
        await store.loadCurrentWeek(household: household)

        #expect(apiClient.fetchCount == 2)
        #expect(store.summary?.weekStartDate == currentWeek)
    }

    @MainActor
    @Test func toggleLockUsesCurrentRowStateWhenCapturedDayIsStale() async {
        let apiClient = CapturingWeekStoreAPIClient()
        let store = WeekStore(
            apiClient: apiClient,
            syncDebounceNanoseconds: 0,
            retryDelayNanoseconds: 60_000_000_000
        )
        store.seedForUITests()

        let staleMonday = WeekDayRowViewModel(
            id: "2026-06-08",
            weekday: .monday,
            weekdayLabel: "Monday",
            date: "2026-06-08",
            dateLabel: "Jun 8",
            mealTitle: "Monday Pasta",
            detail: "\(L10n.format("format.servings", 4)) · 25 min",
            isToday: true,
            isEmpty: false,
            isLocked: false,
            recipe: store.dayRows.first { $0.weekday == .monday }!.recipe
        )

        await store.toggleLock(
            day: staleMonday,
            household: Household(id: "11111111-1111-1111-1111-111111111111", name: "Test household", role: .owner),
            userID: "33333333-3333-3333-3333-333333333333"
        )
        try? await Task.sleep(nanoseconds: 20_000_000)

        #expect(apiClient.events.count == 1)
        switch apiClient.events.first {
        case .mealUnlocked(day: .monday):
            break
        default:
            Issue.record("Expected stale Monday row to unlock current locked state")
        }
    }

    @MainActor
    @Test func rapidLockAndSkipChangesCollapseToFinalDesiredState() async throws {
        let apiClient = SequencedEventWeekStoreAPIClient()
        let store = WeekStore(
            apiClient: apiClient,
            syncDebounceNanoseconds: 50_000_000,
            retryDelayNanoseconds: 60_000_000_000
        )
        store.seedForUITests()

        let monday = store.dayRows.first { $0.weekday == .monday }!

        await store.toggleLock(
            day: monday,
            household: Household(id: "11111111-1111-1111-1111-111111111111", name: "Test household", role: .owner),
            userID: "33333333-3333-3333-3333-333333333333"
        )
        await store.toggleSkip(
            day: store.dayRows.first { $0.weekday == .monday }!,
            household: Household(id: "11111111-1111-1111-1111-111111111111", name: "Test household", role: .owner),
            userID: "33333333-3333-3333-3333-333333333333"
        )

        #expect(store.dayRows.first { $0.weekday == .monday }?.isSkipped == true)
        #expect(store.hasPendingSync == true)

        try await Task.sleep(nanoseconds: 120_000_000)

        #expect(apiClient.events.count == 1)
        switch apiClient.events.first {
        case .daySkipped(day: .monday):
            break
        default:
            Issue.record("Expected final desired state to collapse to a single skip event for Monday")
        }
        #expect(store.hasPendingSync == false)
    }

    /// The Last/Next-and-back regression, fixed properly this time: each
    /// week's summary is now cached independently by `weekStartDate` (see
    /// `WeekStore.loadWeekData`), so returning to the current week after
    /// browsing away shows the *correct* week's data immediately —
    /// synchronously, from cache, before any network round trip — rather
    /// than either flashing the browsed week's stale cards (the original
    /// bug) or forcing the user to wait through a loading spinner for data
    /// that was already fetched moments ago (the cost of the first fix).
    @MainActor
    @Test func loadCurrentWeekShowsTheCorrectWeekInstantlyFromCacheAfterBrowsingAway() async {
        let apiClient = PausableWeekStoreAPIClient()
        let store = WeekStore(apiClient: apiClient)
        let household = Household(id: "11111111-1111-1111-1111-111111111111", name: "Test household", role: .owner)
        let currentWeekStart = WeekCalendar.currentWeekStartDate()
        let lastWeekStart = WeekCalendar.addWeeks(to: currentWeekStart, offset: -1)

        await apiClient.queueResult(makeWeekSummary(weekStartDate: currentWeekStart))
        await store.loadCurrentWeek(household: household, force: true)
        #expect(store.isLoading == false)

        // Browse to Last week — `loadWeek` leaves the display slot pointing
        // at a different week than `loadCurrentWeek` will ask for next.
        await apiClient.queueResult(makeWeekSummary(weekStartDate: lastWeekStart))
        await store.loadWeek(household: household, weekStartDate: lastWeekStart)
        #expect(store.summary?.weekStartDate == lastWeekStart)

        // Return to This week: pause the network call so the only way this
        // can already be correct is the synchronous cache-apply at the top
        // of `loadWeekData`, before the (still-pending) fetch resolves.
        await apiClient.pauseNextRequest()
        let loadTask = Task { await store.loadCurrentWeek(household: household, force: true) }
        await apiClient.waitUntilRequestStarted()
        #expect(store.summary?.weekStartDate == currentWeekStart)
        #expect(store.isLoading == false)

        await apiClient.resumePausedRequest(with: makeWeekSummary(weekStartDate: currentWeekStart))
        await loadTask.value
        #expect(store.isLoading == false)
        #expect(store.summary?.weekStartDate == currentWeekStart)
    }

    /// Guards the original behavior the fix above must not regress: an
    /// ordinary same-week refresh (no browsing detour in between) still
    /// updates quietly in place, without flashing the loading panel over
    /// content that's already correct for the week being shown.
    @MainActor
    @Test func loadCurrentWeekStaysQuietWhenRefreshingTheSameWeekItAlreadyHas() async {
        let apiClient = PausableWeekStoreAPIClient()
        let store = WeekStore(apiClient: apiClient)
        let household = Household(id: "11111111-1111-1111-1111-111111111111", name: "Test household", role: .owner)
        let currentWeekStart = WeekCalendar.currentWeekStartDate()

        await apiClient.queueResult(makeWeekSummary(weekStartDate: currentWeekStart))
        await store.loadCurrentWeek(household: household, force: true)

        await apiClient.pauseNextRequest()
        let loadTask = Task { await store.loadCurrentWeek(household: household, force: true) }
        await apiClient.waitUntilRequestStarted()
        #expect(store.isLoading == false)

        await apiClient.resumePausedRequest(with: makeWeekSummary(weekStartDate: currentWeekStart))
        await loadTask.value
    }

    /// A successful mutation (`assignMeal`) leaves the per-week cache
    /// pointing at pre-mutation data unless it's explicitly invalidated —
    /// without that, browsing away and back within the freshness window
    /// would silently revert the just-made change back to what the week
    /// looked like before it, straight from cache.
    @MainActor
    @Test func assignMealInvalidatesTheCacheSoBrowsingBackDoesNotShowThePreMutationWeek() async {
        let currentWeek = WeekCalendar.currentWeekStartDate()
        let otherWeek = WeekCalendar.addWeeks(to: currentWeek, offset: -1)
        let apiClient = SequencedWeekSummaryAPIClient(summaries: [
            makeWeekSummary(weekStartDate: currentWeek),
            makeWeekSummary(weekStartDate: otherWeek),
            makeWeekSummary(weekStartDate: currentWeek),
        ])
        let store = WeekStore(apiClient: apiClient)
        let household = Household(id: "11111111-1111-1111-1111-111111111111", name: "Test household", role: .owner)

        await store.loadCurrentWeek(household: household)
        #expect(apiClient.fetchCount == 1)

        let monday = store.dayRows.first { $0.weekday == .monday }!
        let recipe = WeekSummaryRecipe(id: "r1", title: "New recipe", description: "", servings: 4, prepTimeMinutes: 10, cookTimeMinutes: 10, tags: [])
        await store.assignMeal(day: monday, recipe: recipe, household: household, userID: "33333333-3333-3333-3333-333333333333")

        await store.loadWeek(household: household, weekStartDate: otherWeek)
        #expect(apiClient.fetchCount == 2)

        // Without invalidating the cache on a successful mutation, this
        // would be a cache hit (fetchCount staying at 2) that silently
        // redisplays the pre-`assignMeal` week.
        await store.loadCurrentWeek(household: household)
        #expect(apiClient.fetchCount == 3)
    }
}

private final class GenerateFailingWeekStoreAPIClient: WeekStoreAPIClient {
    let error: APIError

    init(error: APIError) {
        self.error = error
    }

    func weekSummary(householdID: String, weekStartDate: String) async throws -> WeekSummary {
        throw APIError.notFound
    }

    func appendWeekPlanEvent(
        householdID: String,
        weekStartDate: String,
        userID: String,
        event: WeekPlanEventInput
    ) async throws {}

    func generateWeekPlan(householdID: String, weekStartDate: String, regenerate: Bool) async throws {
        throw error
    }

    func recipe(householdID: String, recipeID: String) async throws -> FullRecipe {
        throw APIError.notFound
    }
}

private final class FailingWeekStoreAPIClient: WeekStoreAPIClient {
    func weekSummary(householdID: String, weekStartDate: String) async throws -> WeekSummary {
        throw APIError.server(statusCode: 500)
    }

    func appendWeekPlanEvent(
        householdID: String,
        weekStartDate: String,
        userID: String,
        event: WeekPlanEventInput
    ) async throws {
        throw APIError.server(statusCode: 500)
    }

    func generateWeekPlan(householdID: String, weekStartDate: String, regenerate: Bool) async throws {}

    func recipe(householdID: String, recipeID: String) async throws -> FullRecipe {
        throw APIError.notFound
    }
}

/// Returns a fixed, recognizable week summary for whatever date is requested
/// (it ignores the field value and stamps the requested date through), used to
/// verify that `WeekStore.loadWeek` correctly threads through an explicit
/// browsing date.
private final class StubbedWeekSummaryAPIClient: WeekStoreAPIClient {
    let weekStartDate: String

    init(weekStartDate: String) {
        self.weekStartDate = weekStartDate
    }

    func weekSummary(householdID: String, weekStartDate: String) async throws -> WeekSummary {
        WeekSummary(
            household: SummaryHousehold(id: householdID, name: "Test household"),
            weekStartDate: weekStartDate,
            updatedAt: nil,
            days: Weekday.allCases.enumerated().map { index, weekday in
                WeekSummaryDay(
                    dayOfWeek: weekday,
                    date: WeekCalendar.addDays(to: weekStartDate, offset: index),
                    state: .empty,
                    recipe: nil
                )
            }
        )
    }

    func appendWeekPlanEvent(
        householdID: String,
        weekStartDate: String,
        userID: String,
        event: WeekPlanEventInput
    ) async throws {}

    func generateWeekPlan(householdID: String, weekStartDate: String, regenerate: Bool) async throws {}

    func recipe(householdID: String, recipeID: String) async throws -> FullRecipe {
        throw APIError.notFound
    }
}

private final class SequencedWeekSummaryAPIClient: WeekStoreAPIClient {
    private var summaries: [WeekSummary]
    private(set) var fetchCount = 0

    init(summaries: [WeekSummary]) {
        self.summaries = summaries
    }

    func weekSummary(householdID: String, weekStartDate: String) async throws -> WeekSummary {
        fetchCount += 1
        if !summaries.isEmpty {
            return summaries.removeFirst()
        }
        return makeWeekSummary(weekStartDate: weekStartDate)
    }

    func recipe(householdID: String, recipeID: String) async throws -> FullRecipe {
        FullRecipe(
            id: recipeID,
            title: "Recipe",
            description: "Description",
            servings: 4,
            prepTimeMinutes: 10,
            cookTimeMinutes: 15,
            tags: [],
            ingredients: [],
            steps: [],
            userVote: nil
        )
    }

    func appendWeekPlanEvent(
        householdID: String,
        weekStartDate: String,
        userID: String,
        event: WeekPlanEventInput
    ) async throws {}

    func generateWeekPlan(householdID: String, weekStartDate: String, regenerate: Bool) async throws {}
}

private func makeWeekSummary(weekStartDate: String) -> WeekSummary {
    WeekSummary(
        household: SummaryHousehold(id: "11111111-1111-1111-1111-111111111111", name: "Test household"),
        weekStartDate: weekStartDate,
        updatedAt: nil,
        days: Weekday.allCases.enumerated().map { index, weekday in
            WeekSummaryDay(
                dayOfWeek: weekday,
                date: WeekCalendar.addDays(to: weekStartDate, offset: index),
                state: .empty,
                recipe: nil
            )
        }
    )
}

/// An `actor` (not a plain class, unlike the other fakes in this file) since
/// `loadCurrentWeekShowsLoadingWhenTheCachedSummaryIsForADifferentWeek`
/// needs to pause a request mid-flight and resume it from the test's own
/// `Task`, running concurrently with `WeekStore`'s `@MainActor` caller — the
/// same continuation-gating pattern `AppRefreshCoordinatorTests`'
/// `FakeAppRefreshAPIClient` uses.
private actor PausableWeekStoreAPIClient: WeekStoreAPIClient {
    private var queuedResult: WeekSummary?
    private var shouldPauseNextRequest = false
    private var hasStartedARequestSinceLastWait = false
    private var requestStartedContinuation: CheckedContinuation<Void, Never>?
    private var pauseContinuation: CheckedContinuation<Void, Never>?
    private var pausedResult: WeekSummary?

    /// The next `weekSummary` call returns this immediately.
    func queueResult(_ summary: WeekSummary) {
        queuedResult = summary
    }

    /// The next `weekSummary` call suspends until `resumePausedRequest` is
    /// called, so a test can observe `WeekStore.isLoading` while the fetch
    /// is still in flight.
    func pauseNextRequest() {
        shouldPauseNextRequest = true
    }

    func waitUntilRequestStarted() async {
        if hasStartedARequestSinceLastWait {
            hasStartedARequestSinceLastWait = false
            return
        }
        await withCheckedContinuation { requestStartedContinuation = $0 }
    }

    func resumePausedRequest(with summary: WeekSummary) {
        pausedResult = summary
        pauseContinuation?.resume()
        pauseContinuation = nil
    }

    func weekSummary(householdID: String, weekStartDate: String) async throws -> WeekSummary {
        hasStartedARequestSinceLastWait = true
        requestStartedContinuation?.resume()
        requestStartedContinuation = nil

        if shouldPauseNextRequest {
            shouldPauseNextRequest = false
            await withCheckedContinuation { pauseContinuation = $0 }
            return pausedResult!
        }
        return queuedResult!
    }

    func appendWeekPlanEvent(householdID: String, weekStartDate: String, userID: String, event: WeekPlanEventInput) async throws {}
    func generateWeekPlan(householdID: String, weekStartDate: String, regenerate: Bool) async throws {}
    func recipe(householdID: String, recipeID: String) async throws -> FullRecipe { throw APIError.notFound }
}

private final class CapturingWeekStoreAPIClient: WeekStoreAPIClient {
    private(set) var events: [WeekPlanEventInput] = []

    func weekSummary(householdID: String, weekStartDate: String) async throws -> WeekSummary {
        throw APIError.notFound
    }

    func appendWeekPlanEvent(
        householdID: String,
        weekStartDate: String,
        userID: String,
        event: WeekPlanEventInput
    ) async throws {
        events.append(event)
    }

    func generateWeekPlan(householdID: String, weekStartDate: String, regenerate: Bool) async throws {}

    func recipe(householdID: String, recipeID: String) async throws -> FullRecipe {
        throw APIError.notFound
    }
}

private final class SequencedEventWeekStoreAPIClient: WeekStoreAPIClient {
    private(set) var events: [WeekPlanEventInput] = []

    func weekSummary(householdID: String, weekStartDate: String) async throws -> WeekSummary {
        throw APIError.notFound
    }

    func appendWeekPlanEvent(
        householdID: String,
        weekStartDate: String,
        userID: String,
        event: WeekPlanEventInput
    ) async throws {
        events.append(event)
    }

    func generateWeekPlan(householdID: String, weekStartDate: String, regenerate: Bool) async throws {}

    func recipe(householdID: String, recipeID: String) async throws -> FullRecipe {
        throw APIError.notFound
    }
}

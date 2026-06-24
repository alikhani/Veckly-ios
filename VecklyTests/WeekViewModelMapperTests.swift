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
    @Test func toggleSkipKeepsLocalDayRowWhenAPIRequestFails() async {
        let store = WeekStore(
            apiClient: FailingWeekStoreAPIClient(),
            syncDebounceNanoseconds: 0,
            retryDelayNanoseconds: 60_000_000_000
        )
        store.seedForUITests()

        let monday = store.dayRows.first { $0.weekday == .monday }!

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
        #expect(updatedMonday.recipe == nil)
        #expect(store.skippedDays.contains(.monday) == true)
        #expect(store.hasPendingSync == true)
        #expect(store.mutationError == L10n.string("error.week.pendingSync"))
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

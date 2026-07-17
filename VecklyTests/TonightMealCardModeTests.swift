import Foundation
import Testing
@testable import Veckly

/// Beslut 16 (Fas 3): the hero card has four distinct states. These tests
/// exercise `TonightMealCardMode.compute` directly — no view hierarchy —
/// covering the Mon–Fri and weekend-planning households the plan calls out
/// explicitly.
struct TonightMealCardModeTests {
    // MARK: - Mode 1: tonight has a meal

    @Test func todayWithARecipeIsTonightMeal() {
        let scope = WeekPlanningScope(profile: monFriProfile())
        let days = [
            day(.monday, "2026-06-08", recipe: recipe(), isToday: true),
            day(.tuesday, "2026-06-09", recipe: nil),
        ]

        let mode = TonightMealCardMode.compute(dayRows: days, scope: scope, hasCoverage: { _ in false })

        #expect(mode == .tonightMeal(day: days[0]))
    }

    @Test func todayCoveredByLeftoversWithNoRecipeOfItsOwnIsStillTonightMeal() {
        let scope = WeekPlanningScope(profile: monFriProfile())
        let today = day(.monday, "2026-06-08", recipe: nil, isToday: true)
        let days = [today]

        let mode = TonightMealCardMode.compute(dayRows: days, scope: scope, hasCoverage: { $0.id == today.id })

        #expect(mode == .tonightMeal(day: today))
    }

    @Test func skippedTodayIsNeverTonightMealEvenWithARecipeAttached() {
        // Skip is a flag layered on top of an assignment (see
        // `WeekDayRowViewModel.withSkipped`) — a skipped day keeps its
        // `recipe` but must not surface as "tonight's dinner".
        let scope = WeekPlanningScope(profile: monFriProfile())
        let today = day(.monday, "2026-06-08", recipe: recipe(), isToday: true, isSkipped: true)
        let tuesday = day(.tuesday, "2026-06-09", recipe: recipe())
        let days = [today, tuesday]

        let mode = TonightMealCardMode.compute(dayRows: days, scope: scope, hasCoverage: { _ in false })

        #expect(mode == .upcomingMeal(day: tuesday))
    }

    // MARK: - Mode 2: open tonight

    @Test func relevantTodayWithNothingAssignedIsOpenTonight() {
        let scope = WeekPlanningScope(profile: monFriProfile())
        let today = day(.wednesday, "2026-06-10", recipe: nil, isToday: true)
        let days = [
            day(.monday, "2026-06-08", recipe: recipe()),
            day(.tuesday, "2026-06-09", recipe: recipe()),
            today,
            day(.thursday, "2026-06-11", recipe: nil),
        ]

        let mode = TonightMealCardMode.compute(dayRows: days, scope: scope, hasCoverage: { _ in false })

        #expect(mode == .openTonight(day: today))
    }

    @Test func weekendPlanningHouseholdSeesSaturdayAsOpenTonightWhenUnassigned() {
        let scope = WeekPlanningScope(profile: profile(selecting: Weekday.allCases))
        let today = day(.saturday, "2026-06-13", recipe: nil, isToday: true)
        let days = [today, day(.sunday, "2026-06-14", recipe: nil)]

        let mode = TonightMealCardMode.compute(dayRows: days, scope: scope, hasCoverage: { _ in false })

        #expect(mode == .openTonight(day: today))
    }

    // MARK: - Mode 3: not a planning day (or already resolved) — show what's next

    @Test func monFriHouseholdOnAnUnplannedSaturdayWithOnlyAPastPlannedDayIsWeekDone() {
        let scope = WeekPlanningScope(profile: monFriProfile())
        let monday = day(.monday, "2026-06-08", recipe: recipe(), isToday: false, isPast: true)
        let saturdayToday = day(.saturday, "2026-06-13", recipe: nil, isToday: true)
        let sunday = day(.sunday, "2026-06-14", recipe: nil)
        let days = [monday, saturdayToday, sunday]

        // No planned day remains *after* today in this loaded week, and the
        // only planned day is in the past — so the closed state applies,
        // not an upcoming meal.
        let mode = TonightMealCardMode.compute(dayRows: days, scope: scope, hasCoverage: { _ in false })
        #expect(mode == .weekDone)
    }

    @Test func weekendPlanningHouseholdSeesSaturdaysOwnDinnerAsAnOrdinaryTonightNotUpcoming() {
        // Acceptance: "helgplanerande hushåll ser lördagens middag som en
        // vanlig kväll" — Saturday with its own recipe is `.tonightMeal`,
        // not treated specially just because it's a weekend day.
        let scope = WeekPlanningScope(profile: profile(selecting: Weekday.allCases))
        let saturdayToday = day(.saturday, "2026-06-13", recipe: recipe(), isToday: true)
        let days = [saturdayToday, day(.sunday, "2026-06-14", recipe: nil)]

        let mode = TonightMealCardMode.compute(dayRows: days, scope: scope, hasCoverage: { _ in false })

        #expect(mode == .tonightMeal(day: saturdayToday))
    }

    @Test func nonRelevantTodayWithAPlannedDayLaterInTheWeekShowsThatUpcomingDay() {
        let scope = WeekPlanningScope(profile: monFriProfile())
        let today = day(.saturday, "2026-06-13", recipe: nil, isToday: true)
        let nextMonday = day(.monday, "2026-06-15", recipe: recipe())
        let days = [today, nextMonday]

        let mode = TonightMealCardMode.compute(dayRows: days, scope: scope, hasCoverage: { _ in false })

        #expect(mode == .upcomingMeal(day: nextMonday))
    }

    // MARK: - Mode 4: nothing left to cook

    @Test func noTodayRowAndNoUpcomingPlannedDayIsWeekDone() {
        let scope = WeekPlanningScope(profile: monFriProfile())
        let days = [
            day(.monday, "2026-06-08", recipe: nil, isPast: true),
            day(.tuesday, "2026-06-09", recipe: nil, isPast: true),
        ]

        let mode = TonightMealCardMode.compute(dayRows: days, scope: scope, hasCoverage: { _ in false })

        #expect(mode == .weekDone)
    }

    @Test func todaysOwnMealTakesPriorityEvenWhenNothingIsPlannedAfterIt() {
        let scope = WeekPlanningScope(profile: monFriProfile())
        let today = day(.friday, "2026-06-12", recipe: recipe(), isToday: true)
        let days = [today, day(.saturday, "2026-06-13", recipe: nil), day(.sunday, "2026-06-14", recipe: nil)]

        // Today itself has a meal, so this is `.tonightMeal` — the "nothing
        // left after today" case (`weekDone`) needs today itself to be
        // resolved with no meal (e.g. skipped), covered separately below.
        let mode = TonightMealCardMode.compute(dayRows: days, scope: scope, hasCoverage: { _ in false })
        #expect(mode == .tonightMeal(day: today))
    }

    @Test func skippedTodayWithNoPlannedDaysAheadIsWeekDone() {
        let scope = WeekPlanningScope(profile: monFriProfile())
        let today = day(.friday, "2026-06-12", recipe: nil, isToday: true, isSkipped: true)
        let days = [today, day(.saturday, "2026-06-13", recipe: nil), day(.sunday, "2026-06-14", recipe: nil)]

        let mode = TonightMealCardMode.compute(dayRows: days, scope: scope, hasCoverage: { _ in false })

        #expect(mode == .weekDone)
    }

    // MARK: - `day` accessor

    @Test func dayAccessorReturnsNilOnlyForWeekDone() {
        #expect(TonightMealCardMode.weekDone.day == nil)
        let d = day(.monday, "2026-06-08", recipe: recipe(), isToday: true)
        #expect(TonightMealCardMode.tonightMeal(day: d).day == d)
        #expect(TonightMealCardMode.openTonight(day: d).day == d)
        #expect(TonightMealCardMode.upcomingMeal(day: d).day == d)
    }

    // MARK: - Helpers

    private func monFriProfile() -> HouseholdProfile {
        profile(selecting: [.monday, .tuesday, .wednesday, .thursday, .friday])
    }

    private func profile(selecting weekdays: [Weekday]) -> HouseholdProfile {
        HouseholdProfile(
            householdId: "household-1",
            adults: 2,
            children: 0,
            priorities: [],
            avoidIngredients: [],
            selectedDays: weekdays.map { HouseholdDaySelection(day: $0) }
        )
    }

    private func recipe() -> WeekSummaryRecipe {
        WeekSummaryRecipe(
            id: "recipe-1",
            title: "Pasta",
            description: "",
            servings: 4,
            prepTimeMinutes: 10,
            cookTimeMinutes: 15,
            tags: []
        )
    }

    private func day(
        _ weekday: Weekday,
        _ date: String,
        recipe: WeekSummaryRecipe?,
        isToday: Bool = false,
        isPast: Bool = false,
        isSkipped: Bool = false
    ) -> WeekDayRowViewModel {
        WeekDayRowViewModel(
            id: date,
            weekday: weekday,
            weekdayLabel: weekday.displayName,
            date: date,
            dateLabel: date,
            mealTitle: recipe?.title ?? "",
            detail: "",
            isToday: isToday,
            isPast: isPast,
            isEmpty: recipe == nil && !isSkipped,
            isLocked: false,
            isSkipped: isSkipped,
            recipe: recipe
        )
    }
}

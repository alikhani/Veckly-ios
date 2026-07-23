import Foundation
import Testing
@testable import Veckly

struct WeekPlanningScopeTests {
    // MARK: - Mon–Fri household

    @Test func monFriHouseholdReportsOnlyRelevantOpenDays() {
        // Monday planned, Wednesday skipped, Tuesday/Thursday/Friday still
        // open, weekend untouched — acceptance: "3 planeringsdagar kvar".
        let scope = WeekPlanningScope(profile: monFriProfile())
        let days = [
            day(.monday, "2026-06-08", recipe: recipe()),
            day(.tuesday, "2026-06-09", recipe: nil),
            day(.wednesday, "2026-06-10", recipe: nil, isSkipped: true),
            day(.thursday, "2026-06-11", recipe: nil),
            day(.friday, "2026-06-12", recipe: nil),
            day(.saturday, "2026-06-13", recipe: nil),
            day(.sunday, "2026-06-14", recipe: nil),
        ]

        let open = scope.openDays(in: days, coveredDates: [])

        #expect(open.map(\.weekday) == [.tuesday, .thursday, .friday])
        #expect(!scope.isComplete(days: days, coveredDates: []))
    }

    @Test func weekendDaysNeverAffectCompletenessForAMonFriHousehold() {
        // Every weekday is open, but the household never planned Sat/Sun —
        // acceptance: "Lördag och söndag påverkar inte färdigstatus."
        let scope = WeekPlanningScope(profile: monFriProfile())
        let days = [
            day(.monday, "2026-06-08", recipe: nil),
            day(.tuesday, "2026-06-09", recipe: nil),
            day(.wednesday, "2026-06-10", recipe: nil),
            day(.thursday, "2026-06-11", recipe: nil),
            day(.friday, "2026-06-12", recipe: nil),
            day(.saturday, "2026-06-13", recipe: recipe()),
            day(.sunday, "2026-06-14", recipe: recipe()),
        ]

        let open = scope.openDays(in: days, coveredDates: [])

        #expect(open.count == 5)
        #expect(!open.contains { $0.weekday == .saturday || $0.weekday == .sunday })
    }

    @Test func monFriWeekIsCompleteOnceAllRelevantDaysAreFilled() {
        // Tuesday/Thursday/Friday get filled after Monday+Wednesday were
        // already done — acceptance: "Veckan är klar."
        let scope = WeekPlanningScope(profile: monFriProfile())
        let days = [
            day(.monday, "2026-06-08", recipe: recipe()),
            day(.tuesday, "2026-06-09", recipe: recipe()),
            day(.wednesday, "2026-06-10", recipe: nil, isSkipped: true),
            day(.thursday, "2026-06-11", recipe: recipe()),
            day(.friday, "2026-06-12", recipe: recipe()),
            day(.saturday, "2026-06-13", recipe: nil),
            day(.sunday, "2026-06-14", recipe: nil),
        ]

        #expect(scope.isComplete(days: days, coveredDates: []))
    }

    // MARK: - Household planning the weekend

    @Test func householdWithWeekendSelectedTreatsSaturdayAndSundayAsRegularDays() {
        let scope = WeekPlanningScope(profile: profile(selecting: Weekday.allCases))
        #expect(scope.includesWeekend)

        let days = [
            day(.monday, "2026-06-08", recipe: recipe()),
            day(.tuesday, "2026-06-09", recipe: recipe()),
            day(.wednesday, "2026-06-10", recipe: recipe()),
            day(.thursday, "2026-06-11", recipe: recipe()),
            day(.friday, "2026-06-12", recipe: recipe()),
            day(.saturday, "2026-06-13", recipe: nil),
            day(.sunday, "2026-06-14", recipe: nil),
        ]

        let open = scope.openDays(in: days, coveredDates: [])

        #expect(open.map(\.weekday) == [.saturday, .sunday])
        #expect(!scope.isComplete(days: days, coveredDates: []))
    }

    @Test func monFriHouseholdDoesNotIncludeWeekend() {
        #expect(!WeekPlanningScope(profile: monFriProfile()).includesWeekend)
    }

    // MARK: - "Done" definitions

    @Test func skippedDayCountsAsDone() {
        let scope = WeekPlanningScope(profile: monFriProfile())
        let days = [
            day(.monday, "2026-06-08", recipe: nil, isSkipped: true),
            day(.tuesday, "2026-06-09", recipe: recipe()),
            day(.wednesday, "2026-06-10", recipe: recipe()),
            day(.thursday, "2026-06-11", recipe: recipe()),
            day(.friday, "2026-06-12", recipe: recipe()),
        ]

        #expect(scope.isComplete(days: days, coveredDates: []))
    }

    @Test func prepCoveredDayCountsAsDoneEvenWithoutItsOwnRecipe() {
        let scope = WeekPlanningScope(profile: monFriProfile())
        let days = [
            day(.monday, "2026-06-08", recipe: recipe()),
            day(.tuesday, "2026-06-09", recipe: nil), // covered by leftovers
            day(.wednesday, "2026-06-10", recipe: recipe()),
            day(.thursday, "2026-06-11", recipe: recipe()),
            day(.friday, "2026-06-12", recipe: recipe()),
        ]

        let openWithoutCoverage = scope.openDays(in: days, coveredDates: [])
        #expect(openWithoutCoverage.map(\.weekday) == [.tuesday])

        #expect(scope.isComplete(days: days, coveredDates: ["2026-06-09"]))
    }

    @Test func pastEmptyDaysDoNotCountAsOpenWhenPlanningMidweek() {
        let scope = WeekPlanningScope(profile: monFriProfile())
        let days = [
            day(.monday, "2026-07-20", recipe: nil, isPast: true),
            day(.tuesday, "2026-07-21", recipe: nil, isPast: true),
            day(.wednesday, "2026-07-22", recipe: nil),
            day(.thursday, "2026-07-23", recipe: recipe()),
            day(.friday, "2026-07-24", recipe: nil),
        ]

        let open = scope.openDays(in: days, coveredDates: [])

        #expect(open.map(\.weekday) == [.wednesday, .friday])
    }

    // MARK: - Missing profile fallback

    @Test func missingProfileFallsBackToMonFri() {
        let scope = WeekPlanningScope(profile: nil)
        #expect(scope.selectedWeekdays == WeekPlanningScope.defaultWeekdays)
        #expect(!scope.includesWeekend)
    }

    @Test func emptySelectedDaysFallsBackToMonFri() {
        let scope = WeekPlanningScope(profile: profile(selecting: []))
        #expect(scope.selectedWeekdays == WeekPlanningScope.defaultWeekdays)
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
        isSkipped: Bool = false,
        isPast: Bool = false
    ) -> WeekDayRowViewModel {
        WeekDayRowViewModel(
            id: date,
            weekday: weekday,
            weekdayLabel: weekday.displayName,
            date: date,
            dateLabel: date,
            mealTitle: recipe?.title ?? "",
            detail: "",
            isToday: false,
            isPast: isPast,
            isEmpty: recipe == nil && !isSkipped,
            isLocked: false,
            isSkipped: isSkipped,
            recipe: recipe
        )
    }
}

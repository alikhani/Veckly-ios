import Foundation
import Testing
@testable import Veckly

struct WeekSessionSummaryTests {
    @Test func countsPlannedQuickAndPrepFriendlyDinners() {
        let days = [
            day("2026-06-08", recipe: recipe("Pasta", total: 25, tags: ["italian"])),
            day("2026-06-09", recipe: recipe("Leftover night", total: 45, tags: ["leftover"])),
            day("2026-06-10", recipe: nil, isSkipped: true),
            day("2026-06-11", recipe: nil),
        ]

        let summary = WeekSessionSummary.make(relevantDays: days, prepCoveredDates: [])

        #expect(summary.plannedDinnerCount == 2)
        #expect(summary.quickDinnerCount == 1)
        #expect(summary.prepFriendlyDinnerCount == 1)
    }

    @Test func prepCoverageWithoutARecipeStillCountsAsPlannedAndPrepFriendly() {
        let days = [
            day("2026-06-08", recipe: recipe("Lasagna", total: 60, tags: ["italian"])),
            day("2026-06-09", recipe: nil),
        ]

        let summary = WeekSessionSummary.make(relevantDays: days, prepCoveredDates: ["2026-06-09"])

        #expect(summary.plannedDinnerCount == 2)
        #expect(summary.prepFriendlyDinnerCount == 1)
    }

    @Test func skippedDaysNeverCountTowardAnyBucketEvenWithPrepCoverage() {
        let days = [day("2026-06-08", recipe: recipe("Pasta", total: 20, tags: []), isSkipped: true)]

        let summary = WeekSessionSummary.make(relevantDays: days, prepCoveredDates: ["2026-06-08"])

        #expect(summary.plannedDinnerCount == 0)
        #expect(summary.quickDinnerCount == 0)
        #expect(summary.prepFriendlyDinnerCount == 0)
    }

    private func recipe(_ title: String, total: Int, tags: [String]) -> WeekSummaryRecipe {
        WeekSummaryRecipe(
            id: title.lowercased(),
            title: title,
            description: "",
            servings: 4,
            prepTimeMinutes: total,
            cookTimeMinutes: nil,
            tags: tags
        )
    }

    private func day(
        _ date: String,
        recipe: WeekSummaryRecipe?,
        isSkipped: Bool = false
    ) -> WeekDayRowViewModel {
        WeekDayRowViewModel(
            id: date,
            weekday: .monday,
            weekdayLabel: "Mon",
            date: date,
            dateLabel: date,
            mealTitle: recipe?.title ?? "",
            detail: "",
            isToday: false,
            isPast: false,
            isEmpty: recipe == nil,
            isLocked: false,
            isSkipped: isSkipped,
            recipe: recipe,
            reason: nil,
            confidence: nil,
            streakWeeks: nil
        )
    }
}

struct SessionEndTriggerTests {
    @Test func showsOnlyWhenAMutationJustClosedTheLastOpenDayOfAPopulatedWeek() {
        // The exact transition that should fire the "Veckan är klar" beat:
        // the week was open before this mutation, and this mutation closed it.
        #expect(SessionEndTrigger.shouldShow(wasEmptyBeforeMutation: true, isCompleteNow: true, plannedDinnerCount: 5))
    }

    @Test func doesNotShowWhenReturningToAWeekThatWasAlreadyCompleteBeforeThisSession() {
        // "Bestäm om kortet även ska visas när användaren återvänder till en
        // redan komplett vecka" (Fas 2) — beslut: nej. Merely viewing an
        // already-complete week (wasEmptyBeforeMutation false, since no
        // mutation closed a gap this session) must not re-trigger the beat;
        // it's a one-time ritual, not a persistent banner.
        #expect(!SessionEndTrigger.shouldShow(wasEmptyBeforeMutation: false, isCompleteNow: true, plannedDinnerCount: 5))
    }

    @Test func doesNotShowIfTheWeekIsStillIncompleteAfterTheMutation() {
        #expect(!SessionEndTrigger.shouldShow(wasEmptyBeforeMutation: true, isCompleteNow: false, plannedDinnerCount: 3))
    }

    @Test func doesNotShowForAZeroDinnerWeekEvenIfNominallyComplete() {
        #expect(!SessionEndTrigger.shouldShow(wasEmptyBeforeMutation: true, isCompleteNow: true, plannedDinnerCount: 0))
    }
}

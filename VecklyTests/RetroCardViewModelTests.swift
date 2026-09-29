import Foundation
import Testing
@testable import Veckly

@MainActor
struct RetroCardViewModelTests {
    private func recipe(_ id: String, title: String) -> WeekSummaryRecipe {
        WeekSummaryRecipe(id: id, title: title, description: "", servings: 4, prepTimeMinutes: 10, cookTimeMinutes: 15, tags: [])
    }

    @Test func includesAPlannedDayWithItsDateAsIdentity() {
        let pasta = recipe("pasta", title: "Monday Pasta")
        let days = [WeekSummaryDay(dayOfWeek: .monday, date: "2026-06-08", state: .planned, recipe: pasta)]

        let rows = RetroCardViewModel.buildRows(days: days)

        #expect(rows.map(\.id) == ["2026-06-08"])
        #expect(rows.first?.recipeID == "pasta")
        #expect(rows.first?.title == "Monday Pasta")
        #expect(rows.first?.weekdayLabel == Weekday.monday.shortDisplayName)
    }

    @Test func excludesSkippedEmptyAndRecipeLessDays() {
        let pasta = recipe("pasta", title: "Pasta")
        let days = [
            WeekSummaryDay(dayOfWeek: .monday, date: "2026-06-08", state: .skipped, recipe: pasta),
            WeekSummaryDay(dayOfWeek: .tuesday, date: "2026-06-09", state: .empty, recipe: nil),
            WeekSummaryDay(dayOfWeek: .wednesday, date: "2026-06-10", state: .planned, recipe: nil),
        ]

        #expect(RetroCardViewModel.buildRows(days: days).isEmpty)
    }

    @Test func keepsTheSameRecipeAsSeparateRowsOnSeparateDates() {
        let stew = recipe("stew", title: "Beef Stew")
        let days = [
            WeekSummaryDay(dayOfWeek: .tuesday, date: "2026-06-09", state: .planned, recipe: stew),
            WeekSummaryDay(dayOfWeek: .thursday, date: "2026-06-11", state: .planned, recipe: stew),
        ]

        let rows = RetroCardViewModel.buildRows(days: days)

        #expect(rows.map(\.id) == ["2026-06-09", "2026-06-11"])
        #expect(rows.map(\.recipeID) == ["stew", "stew"])
    }

    @Test func doneCopyFallsBackToThePlainConfirmationWithNoRecap() {
        #expect(RetroCardViewModel.doneCopy(recap: nil, monthName: "June") == L10n.string("retro.done"))
    }

    @Test func doneCopyFallsBackToThePlainConfirmationWhenNoWeeksArePlannedYet() {
        let recap = FamilyRecap(plannedWeekCount: 0, topRecipeThisMonth: nil)
        #expect(RetroCardViewModel.doneCopy(recap: recap, monthName: "June") == L10n.string("retro.done"))
    }

    @Test func doneCopyShowsWeekCountAloneWithNoTopRecipe() {
        let recap = FamilyRecap(plannedWeekCount: 8, topRecipeThisMonth: nil)
        #expect(RetroCardViewModel.doneCopy(recap: recap, monthName: "June") == L10n.format("retro.done.weekCount", 8))
    }

    @Test func doneCopyIncludesTheTopRecipeWhenAvailable() {
        let recap = FamilyRecap(plannedWeekCount: 8, topRecipeThisMonth: .init(title: "Korvstroganoff", count: 3))
        #expect(RetroCardViewModel.doneCopy(recap: recap, monthName: "June") == "\(L10n.format("retro.done.weekCount", 8)) \(L10n.format("retro.done.topRecipe", "June", "Korvstroganoff"))")
    }

    @Test func doneCopySeparatesConfirmedDinnersFromLegacyPlans() {
        let recap = FamilyRecap(
            plannedWeekCount: 8,
            topRecipeThisMonth: .init(title: "Korvstroganoff", count: 3),
            cookedDinnerCountThisMonth: 5,
            legacyPlannedDinnerCountThisMonth: 4
        )

        #expect(
            RetroCardViewModel.doneCopy(recap: recap, monthName: "June")
                == [
                    L10n.format("retro.done.weekCount", 8),
                    L10n.format("retro.done.cookedDinnerCount", 5, "June"),
                    L10n.format("retro.done.legacyPlanCount", 4, "June"),
                    L10n.format("retro.done.topRecipe", "June", "Korvstroganoff"),
                ].joined(separator: " ")
        )
    }

    @Test func betaFeedbackMailURLIncludesSubjectAndWeekContext() {
        let url = RetroCardViewModel.betaFeedbackMailURL(weekStartDate: "2026-07-06")

        #expect(url?.scheme == "mailto")
        #expect(url?.absoluteString.contains("support@veckly.app") == true)
        #expect(url?.absoluteString.contains("subject=") == true)
        #expect(url?.absoluteString.contains("2026-07-06") == true)
    }
}

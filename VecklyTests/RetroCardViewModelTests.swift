import Foundation
import Testing
@testable import Veckly

@MainActor
struct RetroCardViewModelTests {
    private func recipe(_ id: String, title: String) -> WeekSummaryRecipe {
        WeekSummaryRecipe(id: id, title: title, description: "", servings: 4, prepTimeMinutes: 10, cookTimeMinutes: 15, tags: [])
    }

    private func feedbackStore(seeded votes: [String: MealVote] = [:]) -> FeedbackStore {
        let store = FeedbackStore(apiClient: NoopFeedbackStoreAPIClient())
        for (id, vote) in votes {
            store.seedVote(for: id, vote: vote)
        }
        return store
    }

    @Test func includesAPlannedDayWithNoVoteYet() {
        let pasta = recipe("pasta", title: "Monday Pasta")
        let days = [WeekSummaryDay(dayOfWeek: .monday, date: "2026-06-08", state: .planned, recipe: pasta)]

        let rows = RetroCardViewModel.buildRows(days: days, feedbackStore: feedbackStore())

        #expect(rows.map(\.recipeID) == ["pasta"])
        #expect(rows.first?.title == "Monday Pasta")
        #expect(rows.first?.weekdayLabel == Weekday.monday.shortDisplayName)
    }

    @Test func excludesAMealAlreadyRatedByTheCurrentUser() {
        let pasta = recipe("pasta", title: "Monday Pasta")
        let days = [WeekSummaryDay(dayOfWeek: .monday, date: "2026-06-08", state: .planned, recipe: pasta)]

        let rows = RetroCardViewModel.buildRows(days: days, feedbackStore: feedbackStore(seeded: ["pasta": .up]))

        #expect(rows.isEmpty)
    }

    @Test func excludesSkippedAndEmptyDays() {
        let days = [
            WeekSummaryDay(dayOfWeek: .monday, date: "2026-06-08", state: .skipped, recipe: nil),
            WeekSummaryDay(dayOfWeek: .tuesday, date: "2026-06-09", state: .empty, recipe: nil),
        ]

        let rows = RetroCardViewModel.buildRows(days: days, feedbackStore: feedbackStore())

        #expect(rows.isEmpty)
    }

    @Test func excludesAPlannedDayWithNoRecipeEvenIfMislabeled() {
        // Defensive: a leftover-covered day has no recipe of its own — never
        // give it a row, regardless of what `state` claims.
        let days = [WeekSummaryDay(dayOfWeek: .monday, date: "2026-06-08", state: .planned, recipe: nil)]

        let rows = RetroCardViewModel.buildRows(days: days, feedbackStore: feedbackStore())

        #expect(rows.isEmpty)
    }

    @Test func groupsTheSameRecipeCookedTwiceIntoOneRowWithBothWeekdays() {
        let stew = recipe("stew", title: "Beef Stew")
        let days = [
            WeekSummaryDay(dayOfWeek: .tuesday, date: "2026-06-09", state: .planned, recipe: stew),
            WeekSummaryDay(dayOfWeek: .thursday, date: "2026-06-11", state: .planned, recipe: stew),
        ]

        let rows = RetroCardViewModel.buildRows(days: days, feedbackStore: feedbackStore())

        #expect(rows.count == 1)
        #expect(rows.first?.weekdayLabel == "\(Weekday.tuesday.shortDisplayName) + \(Weekday.thursday.shortDisplayName)")
    }

    @Test func keepsWeeklyOrderAndOnlyDropsTheRatedRecipe() {
        let pasta = recipe("pasta", title: "Monday Pasta")
        let tacos = recipe("tacos", title: "Tuesday Tacos")
        let days = [
            WeekSummaryDay(dayOfWeek: .monday, date: "2026-06-08", state: .planned, recipe: pasta),
            WeekSummaryDay(dayOfWeek: .tuesday, date: "2026-06-09", state: .planned, recipe: tacos),
        ]

        let rows = RetroCardViewModel.buildRows(days: days, feedbackStore: feedbackStore(seeded: ["pasta": .down]))

        #expect(rows.map(\.recipeID) == ["tacos"])
    }
}

private final class NoopFeedbackStoreAPIClient: FeedbackStoreAPIClient {
    func mealFeedback(householdID: String) async throws -> [String: MealVote] { [:] }
    func removeMealFeedback(householdID: String, mealID: String) async throws {}
    func submitMealFeedback(householdID: String, mealID: String, vote: MealVote) async throws {}
}

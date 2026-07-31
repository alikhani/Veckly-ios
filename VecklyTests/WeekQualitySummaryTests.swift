import Foundation
import Testing
@testable import Veckly

struct WeekQualitySummaryTests {
    @Test func highlightsQuickRhythmAndVariation() {
        let days = [
            day("2026-06-08", recipe: recipe("Pasta", total: 25, tags: ["italian"])),
            day("2026-06-09", recipe: recipe("Tacos", total: 20, tags: ["mexican"])),
            day("2026-06-10", recipe: recipe("Salmon", total: 30, tags: ["fish"])),
            day("2026-06-11", recipe: recipe("Curry", total: 35, tags: ["indian"])),
        ]

        let summary = WeekQualitySummary.make(days: days)

        #expect(summary.insights.map(\.id).contains("quick-rhythm"))
        #expect(summary.insights.map(\.id).contains("good-variation"))
    }

    @Test func openDaysAndLowConfidenceTakePriority() {
        let days = [
            day("2026-06-08", recipe: recipe("Pasta", total: 25, tags: ["italian"]), confidence: .low),
            day("2026-06-09", recipe: nil),
            day("2026-06-10", recipe: recipe("Soup", total: 50, tags: ["vegetarian"])),
        ]

        let summary = WeekQualitySummary.make(days: days)

        #expect(summary.insights.prefix(2).map(\.id) == ["open-days", "low-confidence"])
    }

    @Test func detectsPrepCoverageWithoutRecipeOnThatDay() {
        let days = [
            day("2026-06-08", recipe: recipe("Lasagna", total: 60, tags: ["italian"])),
            day("2026-06-09", recipe: nil),
        ]

        let summary = WeekQualitySummary.make(days: days, prepCoveredDates: ["2026-06-09"])

        #expect(summary.insights.map(\.id).contains("prep-friendly"))
        #expect(!summary.insights.map(\.id).contains("open-days"))
    }

    @Test func fallsBackToLooksReasonableForAPlainPlannedWeek() {
        let days = [
            day("2026-06-08", recipe: recipe("Pasta", total: 35, tags: ["weekday"])),
            day("2026-06-09", recipe: recipe("Soup", total: 35, tags: ["weekday"])),
            day("2026-06-10", recipe: recipe("Rice", total: 35, tags: ["weekday"])),
        ]

        let summary = WeekQualitySummary.make(days: days)

        #expect(summary.insights.map(\.id) == ["looks-reasonable"])
    }

    @Test func flagsDishesOnASatiationStreakAsAWarning() {
        let repeated = recipe("Taco Tuesday", total: 25, tags: ["mexican"])
        let days = [
            day("2026-06-08", recipe: repeated, streakWeeks: 3),
            day("2026-06-09", recipe: recipe("Soup", total: 35, tags: ["vegetarian"])),
        ]

        let summary = WeekQualitySummary.make(days: days)

        #expect(summary.insights.map(\.id).contains("repeated-dish"))
    }

    @Test func countsUniqueDishesNotDaysForRepeatedDishInsight() {
        let repeated = recipe("Taco Tuesday", total: 25, tags: ["mexican"])
        let days = [
            day("2026-06-08", recipe: repeated, streakWeeks: 3),
            day("2026-06-09", recipe: repeated, streakWeeks: 4),
        ]

        let summary = WeekQualitySummary.make(days: days)

        guard case .repeatedDish(let count) = summary.insights.first(where: { $0.id == "repeated-dish" })?.kind else {
            Issue.record("Expected a repeatedDish insight")
            return
        }
        #expect(count == 1)
    }

    @Test func heavyWeekWarningTakesPriorityOverRepeatedDishInTopThree() {
        let days = [
            day("2026-06-08", recipe: recipe("Lasagna", total: 50, tags: ["weekday"]), confidence: .low),
            day("2026-06-09", recipe: recipe("Stew", total: 50, tags: ["weekday"])),
            day("2026-06-10", recipe: recipe("Roast", total: 50, tags: ["weekday"]), streakWeeks: 3),
            day("2026-06-11", recipe: nil),
        ]

        let summary = WeekQualitySummary.make(days: days)
        let ids = summary.insights.map(\.id)

        #expect(ids.count == 3)
        #expect(ids.contains("heavy-week"))
        #expect(!ids.contains("repeated-dish"))
    }

    @Test func sessionEndInviteNudgeRequiresSoloOwnerWithLoadedDetails() {
        let household = Household(id: "household-1", name: "Home", role: .owner)

        #expect(SessionEndInviteNudgeEligibility.shouldShow(
            activeHousehold: household,
            detailsHouseholdID: "household-1",
            memberCount: 1
        ))
        #expect(!SessionEndInviteNudgeEligibility.shouldShow(
            activeHousehold: Household(id: "household-1", name: "Home", role: .member),
            detailsHouseholdID: "household-1",
            memberCount: 1
        ))
        #expect(!SessionEndInviteNudgeEligibility.shouldShow(
            activeHousehold: household,
            detailsHouseholdID: "other-household",
            memberCount: 1
        ))
        #expect(!SessionEndInviteNudgeEligibility.shouldShow(
            activeHousehold: household,
            detailsHouseholdID: "household-1",
            memberCount: 2
        ))
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
        confidence: AssignmentConfidence? = nil,
        streakWeeks: Int? = nil
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
            isSkipped: false,
            recipe: recipe,
            reason: nil,
            confidence: confidence,
            streakWeeks: streakWeeks
        )
    }
}

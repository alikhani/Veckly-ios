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
        confidence: AssignmentConfidence? = nil
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
            streakWeeks: nil
        )
    }
}

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
        #expect(mapped.days.first?.detail == "4 servings · 25 min")
        #expect(mapped.today?.id == "2026-06-08")
        #expect(mapped.days[1].mealTitle == "")
        #expect(mapped.days[1].isEmpty == true)
        #expect(mapped.days[1].isSkipped == false)
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
}

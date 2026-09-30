import Foundation
import Testing
@testable import Veckly

struct WeekQualitySuggestionTests {
    @Test func openDayPrefersConcreteLeftoverChainWhenEarlierMealSupportsIt() throws {
        let batchMeal = weekRecipe("Chili", total: 40, tags: ["batch"])
        let days = [
            day(.monday, "2026-10-05", recipe: batchMeal),
            day(.tuesday, "2026-10-06", recipe: nil)
        ]

        let suggestion = try #require(WeekQualitySuggestion.make(days: days, recipes: [fullRecipe("Pasta")]))

        #expect(suggestion.kind == .useLeftovers)
        #expect(suggestion.day.weekday == .tuesday)
        #expect(suggestion.sourceDay?.recipe?.title == "Chili")
        #expect(suggestion.replacement == nil)
    }

    @Test func openDayUsesAnUnusedRecipeWhenNoLeftoverChainExists() throws {
        let pasta = fullRecipe("Pasta")
        let soup = fullRecipe("Soup")
        let days = [
            day(.monday, "2026-10-05", recipe: WeekSummaryRecipe(fullRecipe: pasta)),
            day(.tuesday, "2026-10-06", recipe: nil)
        ]

        let suggestion = try #require(WeekQualitySuggestion.make(days: days, recipes: [pasta, soup]))

        #expect(suggestion.kind == .fillOpenDay)
        #expect(suggestion.replacement?.title == "Soup")
    }

    @Test func heavyWeekTargetsSlowestEditableDinnerAndOffersFasterRecipe() throws {
        let days = [
            day(.monday, "2026-10-05", recipe: weekRecipe("Stew", total: 70)),
            day(.tuesday, "2026-10-06", recipe: weekRecipe("Roast", total: 60)),
            day(.wednesday, "2026-10-07", recipe: weekRecipe("Lasagna", total: 50))
        ]

        let suggestion = try #require(WeekQualitySuggestion.make(
            days: days,
            recipes: [fullRecipe("Fast pasta", total: 20, tags: ["quick"])]
        ))

        #expect(suggestion.kind == .makeQuicker)
        #expect(suggestion.day.recipe?.title == "Stew")
        #expect(suggestion.replacement?.title == "Fast pasta")
    }

    @Test func lowConfidenceMealGetsSimplerShoppingAlternative() throws {
        let current = fullRecipe("Project lasagna", ingredients: 14)
        let easy = fullRecipe("Pantry soup", ingredients: 5, tags: ["pantry"])
        let days = [
            day(.monday, "2026-10-05", recipe: WeekSummaryRecipe(fullRecipe: current), confidence: .low),
            day(.tuesday, "2026-10-06", recipe: weekRecipe("Tacos", total: 30))
        ]

        let suggestion = try #require(WeekQualitySuggestion.make(days: days, recipes: [current, easy]))

        #expect(suggestion.kind == .makeEasier)
        #expect(suggestion.day.weekday == .monday)
        #expect(suggestion.replacement?.title == "Pantry soup")
    }

    @Test func repeatedDishGetsDifferentVariationButLockedDinnerIsNeverTargeted() throws {
        let repeated = weekRecipe("Tacos", total: 25, tags: ["mexican"])
        let days = [
            day(.monday, "2026-10-05", recipe: repeated, isLocked: true, streakWeeks: 5),
            day(.tuesday, "2026-10-06", recipe: repeated, streakWeeks: 3)
        ]
        let alternative = fullRecipe("Curry", tags: ["indian"])

        let suggestion = try #require(WeekQualitySuggestion.make(days: days, recipes: [alternative]))

        #expect(suggestion.kind == .addVariation)
        #expect(suggestion.day.weekday == .tuesday)
        #expect(suggestion.replacement?.title == "Curry")
    }

    @Test func hidesSuggestionWhenWarningHasNoRealAlternative() {
        let days = [
            day(.monday, "2026-10-05", recipe: weekRecipe("Stew", total: 70), isLocked: true),
            day(.tuesday, "2026-10-06", recipe: weekRecipe("Roast", total: 60), isLocked: true),
            day(.wednesday, "2026-10-07", recipe: weekRecipe("Lasagna", total: 50), isLocked: true)
        ]

        #expect(WeekQualitySuggestion.make(days: days, recipes: [fullRecipe("Fast", total: 15)]) == nil)
    }

    private func day(
        _ weekday: Weekday,
        _ date: String,
        recipe: WeekSummaryRecipe?,
        confidence: AssignmentConfidence? = nil,
        isLocked: Bool = false,
        streakWeeks: Int? = nil
    ) -> WeekDayRowViewModel {
        WeekDayRowViewModel(
            id: date,
            weekday: weekday,
            weekdayLabel: weekday.rawValue,
            date: date,
            dateLabel: date,
            mealTitle: recipe?.title ?? "",
            detail: "",
            isToday: false,
            isEmpty: recipe == nil,
            isLocked: isLocked,
            recipe: recipe,
            confidence: confidence,
            streakWeeks: streakWeeks
        )
    }

    private func weekRecipe(_ title: String, total: Int, tags: [String] = []) -> WeekSummaryRecipe {
        WeekSummaryRecipe(
            id: id(title),
            title: title,
            description: "",
            servings: 4,
            prepTimeMinutes: total,
            cookTimeMinutes: nil,
            tags: tags
        )
    }

    private func fullRecipe(
        _ title: String,
        total: Int = 30,
        ingredients: Int = 7,
        tags: [String] = []
    ) -> FullRecipe {
        FullRecipe(
            id: id(title),
            title: title,
            description: "",
            servings: 4,
            prepTimeMinutes: total,
            cookTimeMinutes: nil,
            tags: tags,
            ingredients: (0..<ingredients).map { RecipeIngredient(item: "item-\($0)", amount: nil, unit: nil, category: nil) },
            steps: [],
            userVote: nil
        )
    }

    private func id(_ title: String) -> String {
        title.lowercased().replacingOccurrences(of: " ", with: "-")
    }
}

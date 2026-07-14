import Foundation
import Testing
@testable import Veckly

struct MealSwapIntentRankerTests {
    @Test func quickerIntentKeepsAndRanksFastRecipes() {
        let slow = fullRecipe("Slow Stew", prep: 15, cook: 60, tags: [])
        let fast = fullRecipe("Fast Pasta", prep: 10, cook: 10, tags: ["quick"])
        let medium = fullRecipe("Rice Bowl", prep: 15, cook: 15, tags: [])

        let ranked = MealSwapIntentRanker.rank([slow, medium, fast], intent: .quicker, currentRecipe: weekRecipe("Current", prep: 15, cook: 45, tags: []))

        #expect(ranked.map(\.title) == ["Fast Pasta", "Rice Bowl"])
    }

    @Test func childFriendlyIntentUsesFamilyTags() {
        let grownUp = fullRecipe("Spicy Curry", prep: 10, cook: 20, tags: ["spicy"])
        let family = fullRecipe("Family Tacos", prep: 10, cook: 20, tags: ["kid-friendly"])

        let ranked = MealSwapIntentRanker.rank([grownUp, family], intent: .childFriendly, currentRecipe: nil)

        #expect(ranked.map(\.title) == ["Family Tacos"])
    }

    @Test func simplerShoppingIntentPrefersShortIngredientLists() {
        let long = fullRecipe("Project Lasagna", ingredients: 12, tags: [])
        let short = fullRecipe("Pantry Soup", ingredients: 5, tags: ["pantry"])

        let ranked = MealSwapIntentRanker.rank([long, short], intent: .simplerShopping, currentRecipe: nil)

        #expect(ranked.map(\.title) == ["Pantry Soup"])
    }

    @Test func variationAndSameFeelUseCurrentRecipeSignals() {
        let current = weekRecipe("Pasta", prep: 10, cook: 20, tags: ["italian"])
        let italian = fullRecipe("Risotto", tags: ["italian"])
        let mexican = fullRecipe("Tacos", tags: ["mexican"])

        let varied = MealSwapIntentRanker.rank([italian, mexican], intent: .moreVariation, currentRecipe: current)
        let sameFeel = MealSwapIntentRanker.rank([italian, mexican], intent: .sameFeel, currentRecipe: current)

        #expect(varied.map(\.title) == ["Tacos"])
        #expect(sameFeel.map(\.title) == ["Risotto"])
    }

    private func fullRecipe(
        _ title: String,
        prep: Int? = 10,
        cook: Int? = 20,
        ingredients: Int = 6,
        tags: [String]
    ) -> FullRecipe {
        FullRecipe(
            id: title.lowercased().replacingOccurrences(of: " ", with: "-"),
            title: title,
            description: "",
            servings: 4,
            prepTimeMinutes: prep,
            cookTimeMinutes: cook,
            tags: tags,
            ingredients: (0..<ingredients).map { RecipeIngredient(item: "item-\($0)", amount: nil, unit: nil, category: nil) },
            steps: [],
            userVote: nil
        )
    }

    private func weekRecipe(_ title: String, prep: Int, cook: Int, tags: [String]) -> WeekSummaryRecipe {
        WeekSummaryRecipe(
            id: title.lowercased(),
            title: title,
            description: "",
            servings: 4,
            prepTimeMinutes: prep,
            cookTimeMinutes: cook,
            tags: tags
        )
    }
}

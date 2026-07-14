import Foundation

enum MealSwapIntent: String, CaseIterable, Identifiable {
    case any
    case quicker
    case childFriendly
    case simplerShopping
    case moreVariation
    case sameFeel

    var id: String { rawValue }

    var label: String {
        switch self {
        case .any: L10n.string("meal.swapIntent.any")
        case .quicker: L10n.string("meal.swapIntent.quicker")
        case .childFriendly: L10n.string("meal.swapIntent.childFriendly")
        case .simplerShopping: L10n.string("meal.swapIntent.simplerShopping")
        case .moreVariation: L10n.string("meal.swapIntent.moreVariation")
        case .sameFeel: L10n.string("meal.swapIntent.sameFeel")
        }
    }

    var reasonLabel: String? {
        switch self {
        case .any: nil
        case .quicker: L10n.string("meal.swapIntent.reason.quicker")
        case .childFriendly: L10n.string("meal.swapIntent.reason.childFriendly")
        case .simplerShopping: L10n.string("meal.swapIntent.reason.simplerShopping")
        case .moreVariation: L10n.string("meal.swapIntent.reason.moreVariation")
        case .sameFeel: L10n.string("meal.swapIntent.reason.sameFeel")
        }
    }
}

struct MealSwapIntentRanker {
    struct Result: Equatable {
        let recipes: [FullRecipe]
        let isFallback: Bool
    }

    static func rankWithFallback(
        _ recipes: [FullRecipe],
        intent: MealSwapIntent,
        currentRecipe: WeekSummaryRecipe?
    ) -> Result {
        let ranked = rank(recipes, intent: intent, currentRecipe: currentRecipe)
        guard intent != .any, ranked.isEmpty, !recipes.isEmpty else {
            return Result(recipes: ranked, isFallback: false)
        }
        return Result(recipes: recipes, isFallback: true)
    }

    static func rank(
        _ recipes: [FullRecipe],
        intent: MealSwapIntent,
        currentRecipe: WeekSummaryRecipe?
    ) -> [FullRecipe] {
        guard intent != .any else { return recipes }
        return recipes
            .map { recipe in (recipe, score(recipe, intent: intent, currentRecipe: currentRecipe)) }
            .filter { _, score in score > 0 }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return lhs.0.title.localizedCaseInsensitiveCompare(rhs.0.title) == .orderedAscending
            }
            .map(\.0)
    }

    static func score(
        _ recipe: FullRecipe,
        intent: MealSwapIntent,
        currentRecipe: WeekSummaryRecipe?
    ) -> Int {
        switch intent {
        case .any:
            return 1
        case .quicker:
            guard let total = totalMinutes(for: recipe) else { return 0 }
            var score = total <= 30 ? 4 : 0
            if total <= 20 { score += 2 }
            if hasAnyTag(recipe, matching: ["quick", "snabb", "weekday", "weeknight"]) { score += 2 }
            if let currentRecipe, let currentTotal = totalMinutes(for: currentRecipe), total < currentTotal {
                score += 2
            }
            return score
        case .childFriendly:
            var score = hasAnyTag(recipe, matching: ["child", "kid", "kids", "barn", "family", "familj"]) ? 5 : 0
            if recipe.cuisine?.localizedCaseInsensitiveContains("pasta") == true { score += 1 }
            if recipe.title.localizedCaseInsensitiveContains("pasta") { score += 1 }
            return score
        case .simplerShopping:
            var score = recipe.ingredients.count <= 8 ? 4 : 0
            if recipe.ingredients.count <= 5 { score += 2 }
            if hasAnyTag(recipe, matching: ["simple", "easy", "budget", "pantry", "enkel", "billig"]) { score += 2 }
            return score
        case .moreVariation:
            guard let currentRecipe else { return 1 }
            let currentSignals = variationSignals(for: currentRecipe)
            let candidateSignals = variationSignals(for: recipe)
            if !currentSignals.isEmpty, !candidateSignals.isEmpty, currentSignals.isDisjoint(with: candidateSignals) {
                return 5
            }
            if let currentCuisine = currentRecipe.tags.first, let cuisine = recipe.cuisine, !cuisine.localizedCaseInsensitiveContains(currentCuisine) {
                return 2
            }
            return 0
        case .sameFeel:
            guard let currentRecipe else { return 1 }
            let currentSignals = variationSignals(for: currentRecipe)
            let candidateSignals = variationSignals(for: recipe)
            if !currentSignals.isEmpty, !candidateSignals.isEmpty, !currentSignals.isDisjoint(with: candidateSignals) {
                return 5
            }
            return 0
        }
    }

    private static func totalMinutes(for recipe: FullRecipe) -> Int? {
        let total = [recipe.prepTimeMinutes, recipe.cookTimeMinutes].compactMap { $0 }.reduce(0, +)
        return total > 0 ? total : nil
    }

    private static func totalMinutes(for recipe: WeekSummaryRecipe) -> Int? {
        let total = [recipe.prepTimeMinutes, recipe.cookTimeMinutes].compactMap { $0 }.reduce(0, +)
        return total > 0 ? total : nil
    }

    private static func hasAnyTag(_ recipe: FullRecipe, matching needles: [String]) -> Bool {
        recipe.tags.contains { tag in
            let normalized = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return needles.contains { normalized.contains($0) }
        }
    }

    private static func variationSignals(for recipe: FullRecipe) -> Set<String> {
        Set(([recipe.cuisine].compactMap { $0 } + recipe.tags).map(normalizeVariationSignal).filter { !$0.isEmpty })
    }

    private static func variationSignals(for recipe: WeekSummaryRecipe) -> Set<String> {
        Set(recipe.tags.map(normalizeVariationSignal).filter { !$0.isEmpty })
    }

    private static func normalizeVariationSignal(_ signal: String) -> String {
        let ignored: Set<String> = [
            "quick", "snabb", "weekday", "weeknight", "family", "familj",
            "kid", "kids", "child", "barn", "simple", "easy", "budget",
            "pantry", "leftover", "leftovers", "rester", "meal prep"
        ]
        let normalized = signal.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ignored.contains(normalized) ? "" : normalized
    }
}

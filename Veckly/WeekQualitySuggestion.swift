import Foundation

struct WeekQualitySuggestion: Equatable, Identifiable {
    enum Kind: String, Equatable {
        case fillOpenDay
        case useLeftovers
        case makeQuicker
        case makeEasier
        case addVariation
    }

    let kind: Kind
    let day: WeekDayRowViewModel
    let replacement: FullRecipe?
    let sourceDay: WeekDayRowViewModel?

    var id: String {
        [kind.rawValue, day.date, replacement?.id, sourceDay?.date]
            .compactMap { $0 }
            .joined(separator: ":")
    }

    static func make(
        days: [WeekDayRowViewModel],
        recipes: [FullRecipe],
        prepCoveredDates: Set<String> = []
    ) -> WeekQualitySuggestion? {
        let editableDays = days.filter { !$0.isPast && !$0.isSkipped && !$0.isLocked }
        let summary = WeekQualitySummary.make(days: days, prepCoveredDates: prepCoveredDates)
        let insightIDs = Set(summary.insights.map(\.id))

        if insightIDs.contains("open-days"),
           let openDay = editableDays.first(where: { $0.recipe == nil && !prepCoveredDates.contains($0.date) }) {
            if let source = editableDays.last(where: { candidate in
                candidate.date < openDay.date
                    && candidate.recipe.map(RecipeTimingSignals.isPrepFriendly) == true
            }) {
                return WeekQualitySuggestion(kind: .useLeftovers, day: openDay, replacement: nil, sourceDay: source)
            }

            let usedIDs = Set(days.compactMap(\.recipe?.id))
            let candidate = recipes.first(where: { !usedIDs.contains($0.id) }) ?? recipes.first
            guard let candidate else { return nil }
            return WeekQualitySuggestion(kind: .fillOpenDay, day: openDay, replacement: candidate, sourceDay: nil)
        }

        if insightIDs.contains("low-confidence"),
           let target = editableDays.first(where: { $0.confidence == .low && $0.recipe != nil }),
           let current = target.recipe {
            let currentFull = recipes.first(where: { $0.id == current.id })
            let ranked = MealSwapIntentRanker.rank(
                recipes.filter { $0.id != current.id },
                intent: .simplerShopping,
                currentRecipe: current
            )
            let candidate = ranked.first(where: { recipe in
                guard let currentFull else { return true }
                return recipe.ingredients.count < currentFull.ingredients.count
            })
            if let candidate {
                return WeekQualitySuggestion(kind: .makeEasier, day: target, replacement: candidate, sourceDay: nil)
            }
        }

        if insightIDs.contains("heavy-week"),
           let target = editableDays
            .filter({ $0.recipe != nil })
            .max(by: { totalMinutes($0.recipe) < totalMinutes($1.recipe) }),
           let current = target.recipe {
            let currentMinutes = totalMinutes(current)
            let candidate = MealSwapIntentRanker.rank(
                recipes.filter { $0.id != current.id },
                intent: .quicker,
                currentRecipe: current
            ).first(where: { totalMinutes($0) < currentMinutes })
            if let candidate {
                return WeekQualitySuggestion(kind: .makeQuicker, day: target, replacement: candidate, sourceDay: nil)
            }
        }

        if insightIDs.contains("repeated-dish"),
           let target = editableDays
            .filter({ $0.streakWeeks != nil && $0.recipe != nil })
            .max(by: { ($0.streakWeeks ?? 0) < ($1.streakWeeks ?? 0) }),
           let current = target.recipe,
           let candidate = MealSwapIntentRanker.rank(
                recipes.filter { $0.id != current.id },
                intent: .moreVariation,
                currentRecipe: current
           ).first {
            return WeekQualitySuggestion(kind: .addVariation, day: target, replacement: candidate, sourceDay: nil)
        }

        return nil
    }

    private static func totalMinutes(_ recipe: WeekSummaryRecipe?) -> Int {
        guard let recipe else { return .max }
        return (recipe.prepTimeMinutes ?? 0) + (recipe.cookTimeMinutes ?? 0)
    }

    private static func totalMinutes(_ recipe: FullRecipe) -> Int {
        (recipe.prepTimeMinutes ?? 0) + (recipe.cookTimeMinutes ?? 0)
    }
}

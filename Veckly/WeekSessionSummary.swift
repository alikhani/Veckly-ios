import Foundation

/// Shared recipe-timing/tagging rules for summarizing a week. Extracted once
/// `WeekTabView`'s session-end counts and `WeekQualitySummary`'s insights
/// turned out to have quietly duplicated the same "quick" / "prep-friendly"
/// definitions — a single source keeps them from drifting apart.
enum RecipeTimingSignals {
    static func totalMinutes(for recipe: WeekSummaryRecipe) -> Int? {
        let total = [recipe.prepTimeMinutes, recipe.cookTimeMinutes].compactMap { $0 }.reduce(0, +)
        return total > 0 ? total : nil
    }

    static func isQuick(_ recipe: WeekSummaryRecipe) -> Bool {
        guard let total = totalMinutes(for: recipe) else { return false }
        return total <= 30
    }

    static func isPrepFriendly(_ recipe: WeekSummaryRecipe) -> Bool {
        recipe.tags.contains { tag in
            let normalized = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized.contains("leftover")
                || normalized.contains("rester")
                || normalized.contains("meal prep")
                || normalized.contains("batch")
                || normalized.contains("storkok")
        }
    }
}

/// Pure counts behind the "Veckan är klar" completion beat — same
/// `relevantDays`/`prepCoveredDates` shape `WeekQualitySummary` already
/// takes, so both read the identical set of days for a given week.
struct WeekSessionSummary: Equatable {
    let plannedDinnerCount: Int
    let quickDinnerCount: Int
    let prepFriendlyDinnerCount: Int

    static func make(relevantDays: [WeekDayRowViewModel], prepCoveredDates: Set<String>) -> WeekSessionSummary {
        let plannedDinnerCount = relevantDays
            .filter { !$0.isSkipped && ($0.recipe != nil || prepCoveredDates.contains($0.date)) }
            .count
        let quickDinnerCount = relevantDays.filter { day in
            guard !day.isSkipped, let recipe = day.recipe else { return false }
            return RecipeTimingSignals.isQuick(recipe)
        }.count
        let prepFriendlyDinnerCount = relevantDays.filter { day in
            guard !day.isSkipped else { return false }
            if prepCoveredDates.contains(day.date) { return true }
            guard let recipe = day.recipe else { return false }
            return RecipeTimingSignals.isPrepFriendly(recipe)
        }.count
        return WeekSessionSummary(
            plannedDinnerCount: plannedDinnerCount,
            quickDinnerCount: quickDinnerCount,
            prepFriendlyDinnerCount: prepFriendlyDinnerCount
        )
    }
}

/// The pure predicate behind firing the "Veckan är klar" beat: true only when
/// a mutation just closed the last open day of an already-populated week —
/// never merely from browsing to a week that was already complete before
/// this session touched it (see `WeekTabView.checkForSessionEnd`).
enum SessionEndTrigger {
    static func shouldShow(wasEmptyBeforeMutation: Bool, isCompleteNow: Bool, plannedDinnerCount: Int) -> Bool {
        wasEmptyBeforeMutation && isCompleteNow && plannedDinnerCount > 0
    }
}

import Foundation

/// Resolves whether a given calendar day is covered by a prep batch's
/// leftovers. Kept separate from `WeekStore`/`PrepBatchStore` so the two
/// stores stay decoupled — the view layer is what cross-references them.
struct PrepBatchCoverage: Equatable {
    let recipeTitle: String
    let cookDate: String
    let totalPortions: Int
}

func prepBatchCoverage(for date: String, batches: [PrepBatch], recipes: [FullRecipe]) -> PrepBatchCoverage? {
    for batch in batches where batch.assignments.contains(where: { $0.date == date }) {
        let title = recipes.first(where: { $0.id == batch.recipeId })?.title ?? L10n.string("prep.fallbackTitle")
        return PrepBatchCoverage(recipeTitle: title, cookDate: batch.cookDate, totalPortions: batch.totalPortions)
    }
    return nil
}

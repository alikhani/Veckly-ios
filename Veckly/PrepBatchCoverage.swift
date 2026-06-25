import Foundation

/// Resolves whether a given calendar day is covered by a prep batch's
/// leftovers. Kept separate from `WeekStore`/`PrepBatchStore` so the two
/// stores stay decoupled — the view layer is what cross-references them.
struct PrepBatchCoverage: Equatable {
    let batchID: String
    let recipeTitle: String
    let cookDate: String
    let totalPortions: Int
    let mealType: MealType
}

func prepBatchCoverage(for date: String, mealType: MealType, batches: [PrepBatch], recipes: [FullRecipe]) -> PrepBatchCoverage? {
    for batch in batches {
        guard let assignment = batch.assignments.first(where: { $0.date == date && $0.mealType == mealType }) else { continue }
        let title = recipes.first(where: { $0.id == batch.recipeId })?.title ?? L10n.string("prep.fallbackTitle")
        return PrepBatchCoverage(
            batchID: batch.id,
            recipeTitle: title,
            cookDate: batch.cookDate,
            totalPortions: batch.totalPortions,
            mealType: assignment.mealType
        )
    }
    return nil
}

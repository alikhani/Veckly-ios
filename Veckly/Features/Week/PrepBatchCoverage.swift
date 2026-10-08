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
        let title = recipeTitle(for: batch, recipes: recipes)
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

/// A batch built from a custom (non-catalog) recipe isn't the same thing as a
/// true leftovers-only batch (no recipe at all) — it just has no detail view
/// to show on iOS yet. Conflating the two would silently misreport what's for
/// dinner, so it gets its own honest, distinct label instead of either the
/// real title or the leftovers fallback.
private func recipeTitle(for batch: PrepBatch, recipes: [FullRecipe]) -> String {
    if let recipe = recipes.first(where: { $0.id == batch.recipeId }) {
        return recipe.title
    }
    if batch.customRecipeId != nil {
        return L10n.string("prep.customRecipeTitle")
    }
    return L10n.string("prep.fallbackTitle")
}

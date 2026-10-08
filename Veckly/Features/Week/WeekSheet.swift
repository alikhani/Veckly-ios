import Foundation

/// Every sheet the Week tab can present. One optional value (owned by
/// `WeekScreenModel`) replaces what used to be eight separate pieces of
/// sheet state in `WeekTabView`, so at most one sheet can be requested at a
/// time and "close this, then open that" flows go through
/// `WeekScreenModel.presentAfterDismiss`.
enum WeekSheet: Identifiable {
    case recipe(SelectedDayRecipe)
    case mealPicker(WeekDayRowViewModel)
    case rescue(WeekDayRowViewModel)
    case previousWeekProposal
    case dayDetail(WeekDayRowViewModel)
    case prepBatch(PrepBatchSeed)
    case leftoversWithoutRecipe(LeftoversWithoutRecipeSeed)
    case weekBrief(WeekBriefPresentation)

    var id: String {
        switch self {
        case let .recipe(pair): "recipe:\(pair.id)"
        case let .mealPicker(day): "mealPicker:\(day.id)"
        case let .rescue(day): "rescue:\(day.id)"
        case .previousWeekProposal: "previousWeekProposal"
        case let .dayDetail(day): "dayDetail:\(day.id)"
        case let .prepBatch(seed): "prepBatch:\(seed.id)"
        case let .leftoversWithoutRecipe(seed): "leftoversWithoutRecipe:\(seed.id)"
        case let .weekBrief(presentation): "weekBrief:\(presentation.id)"
        }
    }
}

/// Pairs a recipe with the day it belongs to, so RecipeDetailView can offer
/// day-level actions (skip/plan) in context.
struct SelectedDayRecipe: Identifiable {
    let day: WeekDayRowViewModel
    let recipe: WeekSummaryRecipe
    var id: String { recipe.id + day.id }
}

/// Seeds a new prep batch from a day that's already planned — "we made
/// extra of this, mark it as eaten again on other days" — without making
/// the user re-pick the recipe or cook date in `PrepBatchFormSheet`.
struct PrepBatchSeed: Identifiable {
    let recipeID: String
    let cookDate: String
    let weekStartDate: String
    var assignedDate: String? = nil
    var id: String { recipeID + cookDate + weekStartDate + (assignedDate ?? "") }
}

struct LeftoversWithoutRecipeSeed: Identifiable {
    let day: WeekDayRowViewModel
    let defaultPortions: Int
    var id: String { day.id }
}

struct WeekBriefPresentation: Identifiable {
    let weekStartDate: String
    let regenerate: Bool
    var id: String { "\(weekStartDate):\(regenerate)" }
}

import Foundation

struct Household: Decodable, Equatable, Identifiable {
    let id: String
    let name: String
    let role: HouseholdRole
}

enum HouseholdRole: String, Decodable {
    case owner
    case member
}

struct MyHouseholdsResponse: Decodable, Equatable {
    let households: [Household]
}

struct WeekSummary: Decodable, Equatable {
    let household: SummaryHousehold
    let weekStartDate: String
    let updatedAt: String?
    let days: [WeekSummaryDay]
}

struct SummaryHousehold: Decodable, Equatable {
    let id: String
    let name: String
}

struct WeekSummaryDay: Decodable, Equatable, Identifiable {
    let dayOfWeek: Weekday
    let date: String
    let state: WeekDayState
    let recipe: WeekSummaryRecipe?

    var id: String { date }
}

enum Weekday: String, Decodable, CaseIterable {
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday
    case sunday
}

enum WeekDayState: String, Decodable {
    case empty
    case planned
    case skipped
}

struct WeekSummaryRecipe: Decodable, Equatable, Identifiable {
    let id: String
    let title: String
    let description: String
    let servings: Int
    let prepTimeMinutes: Int?
    let cookTimeMinutes: Int?
    let tags: [String]
}

struct ShoppingListSummary: Decodable, Equatable {
    let household: SummaryHousehold
    let weekStartDate: String
    let updatedAt: String?
    let groups: [ShoppingListGroup]
}

struct ShoppingListGroup: Decodable, Equatable, Identifiable {
    let category: String
    let items: [ShoppingListItem]

    var id: String { category }
}

struct ShoppingListItem: Decodable, Equatable, Identifiable {
    let itemKey: String
    let label: String
    let amount: String?
    let unit: String?
    let checked: Bool

    var id: String { itemKey }
}

enum WeekPlanEventInput {
    case mealAssigned(day: Weekday, recipeID: String)
    case mealUnassigned(day: Weekday)
    case mealLocked(day: Weekday)
    case mealUnlocked(day: Weekday)
    case daySkipped(day: Weekday)
    case dayUnskipped(day: Weekday)
}

struct RecipeIngredient: Decodable, Equatable {
    let item: String
    let amount: String?
    let unit: String?
    let category: String?
}

struct RecipeStep: Decodable, Equatable {
    let text: String
}

struct FullRecipe: Decodable, Equatable, Identifiable {
    let id: String
    let title: String
    let description: String
    let servings: Int
    let prepTimeMinutes: Int?
    let cookTimeMinutes: Int?
    let tags: [String]
    let ingredients: [RecipeIngredient]
    let steps: [RecipeStep]
}

enum MealVote: String, Codable {
    case up
    case down
}

struct DraftIngredient: Identifiable {
    var id = UUID()
    var item: String = ""
    var amount: String = ""
    var unit: String = ""
}

struct RecipeDraft {
    var title: String = ""
    var description: String = ""
    var servings: Int = 4
    var prepTimeMinutes: Int? = nil
    var cookTimeMinutes: Int? = nil
    var ingredients: [DraftIngredient] = []
    var steps: [String] = []
    var sourceUrl: String? = nil

    static var empty: RecipeDraft { RecipeDraft() }

    init(from recipe: FullRecipe) {
        title = recipe.title
        description = recipe.description
        servings = recipe.servings
        prepTimeMinutes = recipe.prepTimeMinutes
        cookTimeMinutes = recipe.cookTimeMinutes
        ingredients = recipe.ingredients.map { DraftIngredient(item: $0.item, amount: $0.amount ?? "", unit: $0.unit ?? "") }
        steps = recipe.steps.map(\.text)
        sourceUrl = nil
    }

    init(title: String = "", description: String = "", servings: Int = 4,
         prepTimeMinutes: Int? = nil, cookTimeMinutes: Int? = nil,
         ingredients: [DraftIngredient] = [], steps: [String] = [], sourceUrl: String? = nil) {
        self.title = title; self.description = description; self.servings = servings
        self.prepTimeMinutes = prepTimeMinutes; self.cookTimeMinutes = cookTimeMinutes
        self.ingredients = ingredients; self.steps = steps; self.sourceUrl = sourceUrl
    }
}

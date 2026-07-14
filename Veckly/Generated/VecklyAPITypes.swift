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
    let isLocked: Bool
    let recipe: WeekSummaryRecipe?
    let reason: AssignmentReason?
    let confidence: AssignmentConfidence?
    let streakWeeks: Int?

    var id: String { date }

    init(
        dayOfWeek: Weekday,
        date: String,
        state: WeekDayState,
        isLocked: Bool = false,
        recipe: WeekSummaryRecipe?,
        reason: AssignmentReason? = nil,
        confidence: AssignmentConfidence? = nil,
        streakWeeks: Int? = nil
    ) {
        self.dayOfWeek = dayOfWeek
        self.date = date
        self.state = state
        self.isLocked = isLocked
        self.recipe = recipe
        self.reason = reason
        self.confidence = confidence
        self.streakWeeks = streakWeeks
    }

    private enum CodingKeys: String, CodingKey {
        case dayOfWeek
        case date
        case state
        case isLocked
        case recipe
        case reason
        case confidence
        case streakWeeks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dayOfWeek = try container.decode(Weekday.self, forKey: .dayOfWeek)
        date = try container.decode(String.self, forKey: .date)
        state = try container.decode(WeekDayState.self, forKey: .state)
        isLocked = try container.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        recipe = try container.decodeIfPresent(WeekSummaryRecipe.self, forKey: .recipe)
        reason = try container.decodeIfPresent(AssignmentReason.self, forKey: .reason)
        confidence = try container.decodeIfPresent(AssignmentConfidence.self, forKey: .confidence)
        streakWeeks = try container.decodeIfPresent(Int.self, forKey: .streakWeeks)
    }
}

/// Why the generator picked this meal — only ever set for algorithm
/// assignments (see `Veckly-backend`'s `deriveAssignmentReason`); a manual
/// pick via the meal picker has none. Drives the discreet reason line in
/// the week view.
enum AssignmentReason: String, Decodable {
    case familyRecipe = "family-recipe"
    case likedBefore = "liked-before"
    case backAfterBreak = "back-after-break"
    case basedOnFeedback = "based-on-feedback"
    case newForVariety = "new-for-variety"
    case quickWeekday = "quick-weekday"

    var label: String {
        switch self {
        case .familyRecipe: return L10n.string("week.reason.familyRecipe")
        case .likedBefore: return L10n.string("week.reason.likedBefore")
        case .backAfterBreak: return L10n.string("week.reason.backAfterBreak")
        case .basedOnFeedback: return L10n.string("week.reason.basedOnFeedback")
        case .newForVariety: return L10n.string("week.reason.newForVariety")
        case .quickWeekday: return L10n.string("week.reason.quickWeekday")
        }
    }
}

/// `.low` means the pick was a compromise (e.g. a repeated cuisine/protein,
/// or two hearty meals back to back) — see `evaluateAssignmentConfidence`.
enum AssignmentConfidence: String, Decodable {
    case ok
    case low
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

extension WeekSummaryRecipe {
    init(fullRecipe: FullRecipe) {
        self.init(
            id: fullRecipe.id,
            title: fullRecipe.title,
            description: fullRecipe.description,
            servings: fullRecipe.servings,
            prepTimeMinutes: fullRecipe.prepTimeMinutes,
            cookTimeMinutes: fullRecipe.cookTimeMinutes,
            tags: fullRecipe.tags
        )
    }
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
    let isCustom: Bool

    var id: String { itemKey }

    init(
        itemKey: String,
        label: String,
        amount: String?,
        unit: String?,
        checked: Bool,
        isCustom: Bool = false
    ) {
        self.itemKey = itemKey
        self.label = label
        self.amount = amount
        self.unit = unit
        self.checked = checked
        self.isCustom = isCustom
    }

    private enum CodingKeys: String, CodingKey {
        case itemKey
        case label
        case amount
        case unit
        case checked
        case isCustom
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        itemKey = try container.decode(String.self, forKey: .itemKey)
        label = try container.decode(String.self, forKey: .label)
        amount = try container.decodeIfPresent(String.self, forKey: .amount)
        unit = try container.decodeIfPresent(String.self, forKey: .unit)
        checked = try container.decode(Bool.self, forKey: .checked)
        isCustom = try container.decodeIfPresent(Bool.self, forKey: .isCustom) ?? false
    }
}

struct ShoppingCustomItem: Codable, Equatable, Identifiable {
    let itemKey: String
    let label: String
    let category: String

    var id: String { itemKey }
}

struct ShoppingListSharedState: Codable, Equatable {
    let checkedItems: [String]
    let pantryStock: [String: Double]
    let customItems: [ShoppingCustomItem]
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
    let userVote: String? // "up" | "down" | nil
    let cuisine: String?
    let householdId: String?

    var isLiked: Bool { userVote == "up" }

    init(
        id: String,
        title: String,
        description: String,
        servings: Int,
        prepTimeMinutes: Int?,
        cookTimeMinutes: Int?,
        tags: [String],
        ingredients: [RecipeIngredient],
        steps: [RecipeStep],
        userVote: String?,
        cuisine: String? = nil,
        householdId: String? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.servings = servings
        self.prepTimeMinutes = prepTimeMinutes
        self.cookTimeMinutes = cookTimeMinutes
        self.tags = tags
        self.ingredients = ingredients
        self.steps = steps
        self.userVote = userVote
        self.cuisine = cuisine
        self.householdId = householdId
    }
}

enum MealVote: String, Codable {
    case up
    case down
}

extension HouseholdMealSignal {
    var apiModel: Components.Schemas.HouseholdMealSignal {
        switch self {
        case .worksForFamily: return .works_for_family
        case .notForUs: return .not_for_us
        }
    }
}

extension Components.Schemas.HouseholdMealSignal {
    var appModel: HouseholdMealSignal? {
        switch self {
        case .works_for_family: return .worksForFamily
        case .not_for_us: return .notForUs
        }
    }
}

struct HouseholdMember: Identifiable, Equatable {
    var id: String { userId }
    let userId: String
    let role: HouseholdRole
    let givenName: String?
    let familyName: String?
}

struct UserProfile: Equatable {
    let userId: String
    let givenName: String
    let familyName: String?
}

enum HouseholdPriority: String, CaseIterable {
    case quick
    case budget
    case childFriendly = "child-friendly"
    case mealPrep = "meal-prep"
    case varied

    var label: String {
        switch self {
        case .quick: return L10n.string("priority.quick")
        case .budget: return L10n.string("priority.budget")
        case .childFriendly: return L10n.string("priority.childFriendly")
        case .mealPrep: return L10n.string("priority.mealPrep")
        case .varied: return L10n.string("priority.varied")
        }
    }
}

struct HouseholdProfile: Equatable {
    let householdId: String
    let adults: Int
    let children: Int
    let priorities: [HouseholdPriority]
    let avoidIngredients: [String]
    let selectedDays: [HouseholdDaySelection]
}

enum DayOccasion: String, CaseIterable, Hashable {
    case standard
    case guests
    case treat

    var label: String {
        switch self {
        case .standard: return L10n.string("daySettings.occasion.standard")
        case .guests: return L10n.string("daySettings.occasion.guests")
        case .treat: return L10n.string("daySettings.occasion.treat")
        }
    }
}

enum DayEffortLevel: String, CaseIterable, Hashable {
    case standard
    case busy

    var label: String {
        switch self {
        case .standard: return L10n.string("daySettings.effort.standard")
        case .busy: return L10n.string("daySettings.effort.busy")
        }
    }
}

enum DayCookingTolerance: String, CaseIterable, Hashable {
    case standard
    case relaxed

    var label: String {
        switch self {
        case .standard: return L10n.string("daySettings.tolerance.standard")
        case .relaxed: return L10n.string("daySettings.tolerance.relaxed")
        }
    }
}

struct HouseholdDaySelection: Equatable, Identifiable {
    let day: Weekday
    var servingsOverride: Int?
    var occasion: DayOccasion
    var effortLevel: DayEffortLevel
    var leftoversIntent: Bool
    var lateEvening: Bool
    var cookingTolerance: DayCookingTolerance

    var id: Weekday { day }

    init(
        day: Weekday,
        servingsOverride: Int? = nil,
        occasion: DayOccasion = .standard,
        effortLevel: DayEffortLevel = .standard,
        leftoversIntent: Bool = false,
        lateEvening: Bool = false,
        cookingTolerance: DayCookingTolerance = .standard
    ) {
        self.day = day
        self.servingsOverride = servingsOverride
        self.occasion = occasion
        self.effortLevel = effortLevel
        self.leftoversIntent = leftoversIntent
        self.lateEvening = lateEvening
        self.cookingTolerance = cookingTolerance
    }
}

/// Input to `POST /recipes/recommend` — one vote from `FeedbackStore.allVotes`,
/// paired with the recipe title the AI prompt needs (the store only keys
/// votes by id).
struct MealRecommendationFeedbackItem {
    let mealID: String
    let mealTitle: String
    let vote: MealVote
}

/// Input to `POST /recipes/recommend` — the pool of recipes the AI is allowed
/// to choose from.
struct MealRecommendationCandidate {
    let id: String
    let title: String
}

/// One AI-ranked suggestion — `reason` is a short, already-localized-to-the-
/// meal's-language sentence from Claude, shown directly under the title.
struct MealRecommendation: Equatable, Identifiable {
    let mealID: String
    let reason: String
    var id: String { mealID }
}

/// D5's Sunday-recap summary — a lightweight, presentation-only read of the
/// household's planning history (never used for scoring/generation).
struct FamilyRecap: Equatable {
    let plannedWeekCount: Int
    let topRecipeThisMonth: TopRecipe?

    struct TopRecipe: Equatable {
        let title: String
        let count: Int
    }
}

/// D3's "Er familj"-panel — the signed-in family member's own liked recipes
/// (feedback is per-user; see `getFamilyCookbook`'s backend doc comment),
/// split into still-active favorites and ones due for a repeat.
struct FamilyCookbook: Equatable {
    let totalFamilyLikedCount: Int
    let favorites: [Recipe]
    let dueAgain: [Recipe]

    struct Recipe: Equatable, Identifiable {
        let recipeID: String
        let title: String
        let timesCooked: Int
        let weeksSinceCooked: Int
        var id: String { recipeID }
    }
}

struct HouseholdInvite: Identifiable, Equatable {
    let id: String
    let token: String
    let email: String?
    let status: String
    let expiresAt: String
}

struct InviteLanding: Equatable {
    let householdName: String
    let status: String
}

enum MealType: String, CaseIterable, Codable {
    case lunch, dinner

    var label: String { rawValue.capitalized }
}

struct PrepBatchAssignment: Identifiable, Equatable {
    let id: String
    let batchId: String
    let date: String
    let mealType: MealType
}

struct PrepBatch: Identifiable, Equatable {
    let id: String
    let householdId: String
    let recipeId: String?
    /// Set when this batch was built from a household's own custom (non-catalog)
    /// recipe rather than a shared catalog recipe. iOS has no custom-recipe
    /// browsing/detail UI yet, so this is rendered with a distinct, honest
    /// label rather than the real title — see `prepBatchCoverage`.
    let customRecipeId: String?
    let cookDate: String
    let totalPortions: Int
    let assignments: [PrepBatchAssignment]
}

struct DraftIngredient: Identifiable, Equatable {
    var id = UUID()
    var item: String = ""
    var amount: String = ""
    var unit: String = ""
}

struct StepItem: Identifiable, Equatable {
    let id: UUID
    var text: String
    init(_ text: String = "") { id = UUID(); self.text = text }
}

enum RecipeDraftSource: Equatable {
    case userCreated
    case urlImport
    case aiGenerated
}

struct RecipeDraft: Equatable {
    var title: String = ""
    var description: String = ""
    var servings: Int = 4
    var prepTimeMinutes: Int? = nil
    var cookTimeMinutes: Int? = nil
    var ingredients: [DraftIngredient] = []
    var steps: [StepItem] = []
    var tags: [String] = []
    var sourceUrl: String? = nil
    var source: RecipeDraftSource = .userCreated

    static var empty: RecipeDraft { RecipeDraft() }

    init(from recipe: FullRecipe) {
        title = recipe.title
        description = recipe.description
        servings = recipe.servings
        prepTimeMinutes = recipe.prepTimeMinutes
        cookTimeMinutes = recipe.cookTimeMinutes
        ingredients = recipe.ingredients.map { DraftIngredient(item: $0.item, amount: $0.amount ?? "", unit: $0.unit ?? "") }
        steps = recipe.steps.map { StepItem($0.text) }
        tags = recipe.tags
        sourceUrl = nil
        source = .userCreated
    }

    init(title: String = "", description: String = "", servings: Int = 4,
         prepTimeMinutes: Int? = nil, cookTimeMinutes: Int? = nil,
         ingredients: [DraftIngredient] = [], steps: [StepItem] = [], tags: [String] = [],
         sourceUrl: String? = nil, source: RecipeDraftSource = .userCreated) {
        self.title = title; self.description = description; self.servings = servings
        self.prepTimeMinutes = prepTimeMinutes; self.cookTimeMinutes = cookTimeMinutes
        self.ingredients = ingredients; self.steps = steps; self.tags = tags
        self.sourceUrl = sourceUrl; self.source = source
    }
}

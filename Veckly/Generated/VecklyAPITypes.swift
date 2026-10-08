import Foundation

struct Household: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let role: HouseholdRole
}

enum HouseholdRole: String, Codable {
    case owner
    case member
}

struct MyHouseholdsResponse: Decodable, Equatable {
    let households: [Household]
}

struct WeekSummary: Codable, Equatable {
    let household: SummaryHousehold
    let weekStartDate: String
    let updatedAt: String?
    let explanations: [WeekExplanation]
    let pulse: WeekPulseOutcome?
    let days: [WeekSummaryDay]

    init(
        household: SummaryHousehold,
        weekStartDate: String,
        updatedAt: String?,
        explanations: [WeekExplanation] = [],
        pulse: WeekPulseOutcome? = nil,
        days: [WeekSummaryDay]
    ) {
        self.household = household
        self.weekStartDate = weekStartDate
        self.updatedAt = updatedAt
        self.explanations = explanations
        self.pulse = pulse
        self.days = days
    }

    private enum CodingKeys: String, CodingKey {
        case household, weekStartDate, updatedAt, explanations, pulse, days
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        household = try container.decode(SummaryHousehold.self, forKey: .household)
        weekStartDate = try container.decode(String.self, forKey: .weekStartDate)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        explanations = try container.decodeIfPresent([WeekExplanation].self, forKey: .explanations) ?? []
        pulse = try container.decodeIfPresent(WeekPulseOutcome.self, forKey: .pulse)
        days = try container.decode([WeekSummaryDay].self, forKey: .days)
    }
}

struct WeekPulseOutcome: Codable, Equatable {
    let responseCount: Int
    let memberCount: Int
    let wishes: [WeekPulseWishOutcome]
}

struct WeekPulseWishOutcome: Codable, Equatable, Identifiable {
    enum Status: String, Codable { case fulfilled, unavailable, notSelected = "not-selected" }
    var id: String { userId }
    let userId: String
    let givenName: String?
    let wishedMeal: String
    let status: Status

    var sentence: String {
        let name = givenName ?? L10n.string("pulse.memberFallback")
        switch status {
        case .fulfilled: return L10n.format("pulse.outcome.fulfilled", name, wishedMeal)
        case .unavailable: return L10n.format("pulse.outcome.unavailable", name, wishedMeal)
        case .notSelected: return L10n.format("pulse.outcome.notSelected", name, wishedMeal)
        }
    }
}

enum WeekExplanation: Codable, Equatable {
    case weekContext(date: String, recipeTitle: String)
    case leftoverChain(recipeTitle: String, cookDate: String, coveredDates: [String])
    case sharedIngredient(ingredient: String, dinnerCount: Int)
    case pantryCoverage(ingredients: [String])

    private enum CodingKeys: String, CodingKey {
        case kind, date, recipeTitle, cookDate, coveredDates, ingredient, dinnerCount, ingredients
    }

    private enum Kind: String, Codable {
        case weekContext = "week-context"
        case leftoverChain = "leftover-chain"
        case sharedIngredient = "shared-ingredient"
        case pantryCoverage = "pantry-coverage"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .weekContext:
            self = .weekContext(
                date: try container.decode(String.self, forKey: .date),
                recipeTitle: try container.decode(String.self, forKey: .recipeTitle)
            )
        case .leftoverChain:
            self = .leftoverChain(
                recipeTitle: try container.decode(String.self, forKey: .recipeTitle),
                cookDate: try container.decode(String.self, forKey: .cookDate),
                coveredDates: try container.decode([String].self, forKey: .coveredDates)
            )
        case .sharedIngredient:
            self = .sharedIngredient(
                ingredient: try container.decode(String.self, forKey: .ingredient),
                dinnerCount: try container.decode(Int.self, forKey: .dinnerCount)
            )
        case .pantryCoverage:
            self = .pantryCoverage(ingredients: try container.decode([String].self, forKey: .ingredients))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .weekContext(date, recipeTitle):
            try container.encode(Kind.weekContext, forKey: .kind)
            try container.encode(date, forKey: .date)
            try container.encode(recipeTitle, forKey: .recipeTitle)
        case let .leftoverChain(recipeTitle, cookDate, coveredDates):
            try container.encode(Kind.leftoverChain, forKey: .kind)
            try container.encode(recipeTitle, forKey: .recipeTitle)
            try container.encode(cookDate, forKey: .cookDate)
            try container.encode(coveredDates, forKey: .coveredDates)
        case let .sharedIngredient(ingredient, dinnerCount):
            try container.encode(Kind.sharedIngredient, forKey: .kind)
            try container.encode(ingredient, forKey: .ingredient)
            try container.encode(dinnerCount, forKey: .dinnerCount)
        case let .pantryCoverage(ingredients):
            try container.encode(Kind.pantryCoverage, forKey: .kind)
            try container.encode(ingredients, forKey: .ingredients)
        }
    }

    var sentence: String {
        switch self {
        case let .weekContext(_, recipeTitle):
            L10n.format("week.explanation.context", recipeTitle)
        case let .leftoverChain(recipeTitle, _, _):
            L10n.format("week.explanation.leftovers", recipeTitle)
        case let .sharedIngredient(ingredient, _):
            L10n.format("week.explanation.sharedIngredient", ingredient)
        case let .pantryCoverage(ingredients):
            L10n.format("week.explanation.pantryCoverage", ingredients.joined(separator: ", "))
        }
    }
}

struct SummaryHousehold: Codable, Equatable {
    let id: String
    let name: String
}

struct WeekSummaryDay: Codable, Equatable, Identifiable {
    let dayOfWeek: Weekday
    let date: String
    let state: WeekDayState
    let isLocked: Bool
    let recipe: WeekSummaryRecipe?
    let reason: AssignmentReason?
    let confidence: AssignmentConfidence?
    let streakWeeks: Int?
    let portionSuggestion: PortionSuggestion?

    var id: String { date }

    init(
        dayOfWeek: Weekday,
        date: String,
        state: WeekDayState,
        isLocked: Bool = false,
        recipe: WeekSummaryRecipe?,
        reason: AssignmentReason? = nil,
        confidence: AssignmentConfidence? = nil,
        streakWeeks: Int? = nil,
        portionSuggestion: PortionSuggestion? = nil
    ) {
        self.dayOfWeek = dayOfWeek
        self.date = date
        self.state = state
        self.isLocked = isLocked
        self.recipe = recipe
        self.reason = reason
        self.confidence = confidence
        self.streakWeeks = streakWeeks
        self.portionSuggestion = portionSuggestion
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
        case portionSuggestion
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
        portionSuggestion = try container.decodeIfPresent(PortionSuggestion.self, forKey: .portionSuggestion)
    }
}

struct PortionSuggestion: Codable, Equatable {
    enum Direction: String, Codable { case more, less }
    let direction: Direction
    let suggestedServings: Int
    let evidenceCount: Int
    let matchingCount: Int
}

/// Why the generator picked this meal — only ever set for algorithm
/// assignments (see `Veckly-backend`'s `deriveAssignmentReason`); a manual
/// pick via the meal picker has none. Drives the discreet reason line in
/// the week view.
enum AssignmentReason: String, Codable {
    case familyRecipe = "family-recipe"
    case likedBefore = "liked-before"
    case backAfterBreak = "back-after-break"
    case basedOnFeedback = "based-on-feedback"
    case newForVariety = "new-for-variety"
    case quickWeekday = "quick-weekday"
    case weekOverride = "week-override"
    case pantryCoverage = "pantry-coverage"

    var label: String {
        switch self {
        case .familyRecipe: return L10n.string("week.reason.familyRecipe")
        case .likedBefore: return L10n.string("week.reason.likedBefore")
        case .backAfterBreak: return L10n.string("week.reason.backAfterBreak")
        case .basedOnFeedback: return L10n.string("week.reason.basedOnFeedback")
        case .newForVariety: return L10n.string("week.reason.newForVariety")
        case .quickWeekday: return L10n.string("week.reason.quickWeekday")
        case .weekOverride: return L10n.string("week.reason.weekOverride")
        case .pantryCoverage: return L10n.string("week.reason.pantryCoverage")
        }
    }
}

struct ShoppingPreferences: Equatable {
    let categoryOrder: [String]
    let updatedAt: String?
}

/// `.low` means the pick was a compromise (e.g. a repeated cuisine/protein,
/// or two hearty meals back to back) — see `evaluateAssignmentConfidence`.
enum AssignmentConfidence: String, Codable {
    case ok
    case low
}

enum Weekday: String, Codable, CaseIterable {
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday
    case sunday
}

enum WeekDayState: String, Codable {
    case empty
    case planned
    case skipped
}

struct WeekSummaryRecipe: Codable, Equatable, Identifiable {
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

struct ShoppingListSummary: Codable, Equatable {
    let household: SummaryHousehold
    let weekStartDate: String
    let updatedAt: String?
    let groups: [ShoppingListGroup]
}

struct ShoppingListGroup: Codable, Equatable, Identifiable {
    let category: String
    let items: [ShoppingListItem]

    var id: String { category }
}

struct ShoppingListItem: Codable, Equatable, Identifiable {
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
    case servingsChanged(day: Weekday, servings: Int)
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

enum RecipeSource: String, Codable {
    case userCreated = "user_created"
    case urlImport = "url_import"
    case aiGenerated = "ai_generated"
    case builtin
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
    let proteinSource: String?
    let mealWeight: String?
    let householdId: String?
    let source: RecipeSource

    var isLiked: Bool { userVote == "up" }
    var isBuiltIn: Bool { source == .builtin }

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
        proteinSource: String? = nil,
        mealWeight: String? = nil,
        householdId: String? = nil,
        source: RecipeSource = .builtin
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
        self.proteinSource = proteinSource
        self.mealWeight = mealWeight
        self.householdId = householdId
        self.source = source
    }
}

enum MealVote: String, Codable {
    case up
    case down
}

enum MealOutcomeStatus: String, Codable, CaseIterable, Equatable {
    case cooked
    case changedPlan = "changed_plan"
    case skipped
}

enum MealPortionOutcome: String, Codable, CaseIterable, Equatable {
    case tooLittle = "too_little"
    case rightAmount = "right_amount"
    case tooMuch = "too_much"
}

enum MealOutcomeReason: String, Codable, CaseIterable, Equatable {
    case easyWeeknight = "easy_weeknight"
    case familyApproved = "family_approved"
    case goodLeftovers = "good_leftovers"
    case tooMuchEffort = "too_much_effort"
    case familyPushback = "family_pushback"
    case poorLeftovers = "poor_leftovers"
}

struct MealOutcomeDraft: Codable, Equatable, Identifiable {
    let householdID: String
    let weekStartDate: String
    let date: String
    let plannedRecipeID: String
    var status: MealOutcomeStatus
    var portionOutcome: MealPortionOutcome?
    var intentionalLeftovers: Bool? = nil
    var reason: MealOutcomeReason?
    var actualRecipeID: String?
    var actualMealLabel: String?

    var id: String { "\(householdID):\(weekStartDate):\(date)" }

    func normalized() -> MealOutcomeDraft {
        var copy = self
        if status == .skipped {
            copy.portionOutcome = nil
        }
        if copy.portionOutcome != .tooMuch {
            copy.intentionalLeftovers = nil
        }
        if status != .changedPlan {
            copy.actualRecipeID = nil
            copy.actualMealLabel = nil
        } else {
            let trimmed = copy.actualMealLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
            copy.actualMealLabel = trimmed?.isEmpty == false ? trimmed : nil
        }
        return copy
    }
}

struct MealOutcomeRecord: Codable, Equatable, Identifiable {
    let householdID: String
    let weekStartDate: String
    let date: String
    let plannedRecipeID: String
    let status: MealOutcomeStatus
    let portionOutcome: MealPortionOutcome?
    let intentionalLeftovers: Bool
    let reason: MealOutcomeReason?
    let actualRecipeID: String?
    let actualMealLabel: String?
    let updatedAt: String?

    var id: String { "\(householdID):\(weekStartDate):\(date)" }

    init(draft: MealOutcomeDraft, updatedAt: String? = nil) {
        let draft = draft.normalized()
        householdID = draft.householdID
        weekStartDate = draft.weekStartDate
        date = draft.date
        plannedRecipeID = draft.plannedRecipeID
        status = draft.status
        portionOutcome = draft.portionOutcome
        intentionalLeftovers = draft.intentionalLeftovers ?? false
        reason = draft.reason
        actualRecipeID = draft.actualRecipeID
        actualMealLabel = draft.actualMealLabel
        self.updatedAt = updatedAt
    }

    var draft: MealOutcomeDraft {
        MealOutcomeDraft(
            householdID: householdID,
            weekStartDate: weekStartDate,
            date: date,
            plannedRecipeID: plannedRecipeID,
            status: status,
            portionOutcome: portionOutcome,
            intentionalLeftovers: intentionalLeftovers,
            reason: reason,
            actualRecipeID: actualRecipeID,
            actualMealLabel: actualMealLabel
        )
    }
}

extension MealOutcomeStatus {
    var apiModel: Components.Schemas.MealOutcomeStatus {
        switch self {
        case .cooked: return .cooked
        case .changedPlan: return .changed_plan
        case .skipped: return .skipped
        }
    }
}

extension MealPortionOutcome {
    var apiModel: Components.Schemas.MealPortionOutcome {
        switch self {
        case .tooLittle: return .too_little
        case .rightAmount: return .right_amount
        case .tooMuch: return .too_much
        }
    }
}

extension MealOutcomeReason {
    var apiModel: Components.Schemas.MealOutcomeReason {
        switch self {
        case .easyWeeknight: return .easy_weeknight
        case .familyApproved: return .family_approved
        case .goodLeftovers: return .good_leftovers
        case .tooMuchEffort: return .too_much_effort
        case .familyPushback: return .family_pushback
        case .poorLeftovers: return .poor_leftovers
        }
    }
}

extension Components.Schemas.MealOutcomeRecord {
    var appModel: MealOutcomeRecord {
        MealOutcomeRecord(
            draft: MealOutcomeDraft(
                householdID: householdId,
                weekStartDate: weekStartDate,
                date: date,
                plannedRecipeID: plannedRecipeId,
                status: MealOutcomeStatus(rawValue: status.rawValue) ?? .cooked,
                portionOutcome: portionOutcome.flatMap { MealPortionOutcome(rawValue: $0.rawValue) },
                intentionalLeftovers: intentionalLeftovers,
                reason: reason.flatMap { MealOutcomeReason(rawValue: $0.rawValue) },
                actualRecipeID: actualRecipeId,
                actualMealLabel: actualMealLabel
            ),
            updatedAt: updatedAt
        )
    }
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

struct WeekPulse: Equatable {
    let householdID: String
    let weekStartDate: String
    let responseCount: Int
    let memberCount: Int
    let members: [WeekPulseMember]

    var currentMember: WeekPulseMember? { members.first(where: \.isCurrentUser) }
}

struct WeekPulseMember: Identifiable, Equatable {
    var id: String { userID }
    let userID: String
    let givenName: String?
    let familyName: String?
    let responded: Bool
    let isCurrentUser: Bool
    let awayDates: [String]
    let wishedMeal: String?
    let simpleDate: String?

    var displayName: String {
        let fullName = [givenName, familyName].compactMap { $0 }.joined(separator: " ")
        return fullName.isEmpty ? L10n.string("pulse.memberFallback") : fullName
    }
}

struct WeekPulseDraft: Equatable {
    var awayDates: Set<String>
    var wishedMeal: String
    var simpleDate: String?

    init(member: WeekPulseMember? = nil) {
        awayDates = Set(member?.awayDates ?? [])
        wishedMeal = member?.wishedMeal ?? ""
        simpleDate = member?.simpleDate
    }
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

struct WeekContextOverride: Equatable, Identifiable {
    let date: String
    var servingsOverride: Int?
    var occasion: DayOccasion?
    var effortLevel: DayEffortLevel?
    var leftoversIntent: Bool?
    var lateEvening: Bool?
    var cookingTolerance: DayCookingTolerance?

    var id: String { date }

    var isEmpty: Bool {
        servingsOverride == nil && occasion == nil && effortLevel == nil
            && leftoversIntent == nil && lateEvening == nil && cookingTolerance == nil
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
    let tags: [String]
    let ingredients: [String]
    let prepTimeMinutes: Int?
    let cookTimeMinutes: Int?
    let cuisine: String?
    let proteinSource: String?
    let mealWeight: String?
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
    let cookedDinnerCountThisMonth: Int?
    let legacyPlannedDinnerCountThisMonth: Int?

    init(
        plannedWeekCount: Int,
        topRecipeThisMonth: TopRecipe?,
        cookedDinnerCountThisMonth: Int? = nil,
        legacyPlannedDinnerCountThisMonth: Int? = nil
    ) {
        self.plannedWeekCount = plannedWeekCount
        self.topRecipeThisMonth = topRecipeThisMonth
        self.cookedDinnerCountThisMonth = cookedDinnerCountThisMonth
        self.legacyPlannedDinnerCountThisMonth = legacyPlannedDinnerCountThisMonth
    }

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
        enum HistoryBasis: String, Equatable {
            case confirmedOutcomes = "confirmed_outcomes"
            case mixed
            case legacyPlans = "legacy_plans"
            case none
        }

        let recipeID: String
        let title: String
        let timesCooked: Int
        let weeksSinceCooked: Int?
        let legacyTimesPlanned: Int
        let weeksSinceLegacyPlanned: Int?
        let historyBasis: HistoryBasis

        init(
            recipeID: String,
            title: String,
            timesCooked: Int,
            weeksSinceCooked: Int?,
            legacyTimesPlanned: Int = 0,
            weeksSinceLegacyPlanned: Int? = nil,
            historyBasis: HistoryBasis? = nil
        ) {
            self.recipeID = recipeID
            self.title = title
            self.timesCooked = timesCooked
            self.weeksSinceCooked = weeksSinceCooked
            self.legacyTimesPlanned = legacyTimesPlanned
            self.weeksSinceLegacyPlanned = weeksSinceLegacyPlanned
            self.historyBasis = historyBasis ?? (timesCooked > 0 ? .confirmedOutcomes : legacyTimesPlanned > 0 ? .legacyPlans : .none)
        }

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
    var category: String? = nil
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
        ingredients = recipe.ingredients.map {
            DraftIngredient(item: $0.item, amount: $0.amount ?? "", unit: $0.unit ?? "", category: $0.category)
        }
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

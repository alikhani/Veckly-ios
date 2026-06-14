import Foundation
import HTTPTypes
import OpenAPIRuntime
import OpenAPIURLSession

struct VecklyAPIClient {
    let baseURL: URL
    let accessToken: () -> String?

    private var generatedClient: Client {
        Client(
            serverURL: baseURL,
            transport: URLSessionTransport(),
            middlewares: [AuthorizationMiddleware(accessToken: accessToken())]
        )
    }

    func bootstrapHousehold() async throws -> Household {
        let output = try await generatedClient.bootstrapMyHousehold()
        switch output {
        case let .ok(response):
            return try response.body.json.appModel
        case let .created(response):
            return try response.body.json.appModel
        case .unauthorized:
            throw APIError.unauthorized
        case let .undocumented(statusCode, _):
            throw APIError.server(statusCode: statusCode)
        }
    }

    func listHouseholds() async throws -> [Household] {
        let output = try await generatedClient.getMyHouseholds()
        switch output {
        case let .ok(response):
            return try response.body.json.households.map(\.appModel)
        case .unauthorized:
            throw APIError.unauthorized
        case let .undocumented(statusCode, _):
            throw APIError.server(statusCode: statusCode)
        }
    }

    func weekSummary(householdID: String, weekStartDate: String) async throws -> WeekSummary {
        let output = try await generatedClient.getWeekPlanSummary(
            path: .init(householdId: householdID, weekStartDate: weekStartDate)
        )
        switch output {
        case let .ok(response):
            return try response.body.json.appModel
        case .unauthorized:
            throw APIError.unauthorized
        case .notFound:
            throw APIError.notFound
        case let .undocumented(statusCode, _):
            throw APIError.server(statusCode: statusCode)
        }
    }

    func shoppingListSummary(householdID: String, weekStartDate: String) async throws -> ShoppingListSummary {
        let output = try await generatedClient.getShoppingListSummary(
            path: .init(householdId: householdID, weekStartDate: weekStartDate)
        )
        switch output {
        case let .ok(response):
            return try response.body.json.appModel
        case .unauthorized:
            throw APIError.unauthorized
        case .notFound:
            throw APIError.notFound
        case let .undocumented(statusCode, _):
            throw APIError.server(statusCode: statusCode)
        }
    }

    func appendWeekPlanEvent(
        householdID: String,
        weekStartDate: String,
        userID: String,
        event: WeekPlanEventInput
    ) async throws {
        let causedBy = Components.Schemas.CausedBy.case1(
            .init(source: .user, userId: userID)
        )
        let req = Components.Schemas.AppendWeekPlanEventRequest(
            value1: .init(causedBy: causedBy),
            value2: event.requestValue2
        )
        let output = try await generatedClient.appendWeekPlanEvent(
            path: .init(householdId: householdID, weekStartDate: weekStartDate),
            body: .json(req)
        )
        switch output {
        case .created:
            return
        case .unauthorized:
            throw APIError.unauthorized
        case let .undocumented(statusCode, _):
            throw APIError.server(statusCode: statusCode)
        }
    }

    func recipe(householdID: String, recipeID: String) async throws -> FullRecipe {
        let output = try await generatedClient.getRecipe(
            path: .init(householdId: householdID, recipeId: recipeID)
        )
        switch output {
        case let .ok(response):
            return try response.body.json.appModel
        case .unauthorized:
            throw APIError.unauthorized
        case .notFound:
            throw APIError.notFound
        case let .undocumented(statusCode, _):
            throw APIError.server(statusCode: statusCode)
        }
    }

    func mealFeedback(householdID: String) async throws -> [String: MealVote] {
        let output = try await generatedClient.listMealFeedback(path: .init(householdId: householdID))
        switch output {
        case let .ok(response):
            return try response.body.json.feedback.additionalProperties.compactMapValues(\.appModel)
        case .unauthorized:
            throw APIError.unauthorized
        case let .undocumented(statusCode, _):
            throw APIError.server(statusCode: statusCode)
        }
    }

    func submitMealFeedback(householdID: String, mealID: String, vote: MealVote) async throws {
        let entry = Components.Schemas.MealFeedbackEntry(vote: vote.apiModel)
        let entryData = try JSONEncoder().encode(entry)
        let requestFeedback = try JSONDecoder().decode(
            Components.Schemas.UpsertMealFeedback.feedbackPayload.self,
            from: entryData
        )
        let requestBody = Components.Schemas.UpsertMealFeedback(
            mealId: mealID,
            feedback: requestFeedback
        )
        let output = try await generatedClient.upsertMealFeedback(
            path: .init(householdId: householdID),
            body: .json(requestBody)
        )
        switch output {
        case .ok:
            return
        case .unauthorized:
            throw APIError.unauthorized
        case let .undocumented(statusCode, _):
            throw APIError.server(statusCode: statusCode)
        }
    }

    func listHouseholdRecipes(householdID: String) async throws -> [FullRecipe] {
        let output = try await generatedClient.listRecipes(
            path: .init(householdId: householdID)
        )
        switch output {
        case let .ok(response):
            return try response.body.json.map(\.appModel)
        case .unauthorized:
            throw APIError.unauthorized
        case let .undocumented(statusCode, _):
            throw APIError.server(statusCode: statusCode)
        }
    }

    func generateWeekPlan(householdID: String, weekStartDate: String, regenerate: Bool) async throws {
        let output = try await generatedClient.generateWeekPlan(
            path: .init(householdId: householdID, weekStartDate: weekStartDate),
            body: .json(.init(regenerate: regenerate))
        )
        switch output {
        case .ok:
            return
        case .unauthorized:
            throw APIError.unauthorized
        case let .undocumented(statusCode, _):
            throw APIError.server(statusCode: statusCode)
        }
    }

    func updateShoppingListState(
        householdID: String,
        weekStartDate: String,
        checkedItems: [String],
        expectedUpdatedAt: String?
    ) async throws -> String? {
        let shopState = Components.Schemas.ShoppingStatePayload(
            checkedItems: checkedItems,
            pantryStock: .init(additionalProperties: [:])
        )
        let stateData = try JSONEncoder().encode(shopState)
        let requestState = try JSONDecoder().decode(
            Components.Schemas.UpdateShoppingListStateRequest.statePayload.self,
            from: stateData
        )
        let requestBody = Components.Schemas.UpdateShoppingListStateRequest(
            expectedUpdatedAt: expectedUpdatedAt,
            state: requestState
        )
        let output = try await generatedClient.updateShoppingListState(
            path: .init(householdId: householdID, weekStartDate: weekStartDate),
            body: .json(requestBody)
        )
        switch output {
        case let .ok(response):
            return try response.body.json.updatedAt
        case .unauthorized:
            throw APIError.unauthorized
        case .badRequest:
            throw APIError.server(statusCode: 400)
        case let .conflict(response):
            throw APIError.stale(latestUpdatedAt: try response.body.json.updatedAt)
        case let .undocumented(statusCode, _):
            throw APIError.server(statusCode: statusCode)
        }
    }
}

private struct AuthorizationMiddleware: ClientMiddleware {
    let accessToken: String?

    @concurrent func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @concurrent @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        guard let token = accessToken else { throw APIError.unauthorized }
        var request = request
        request.headerFields[.authorization] = "Bearer \(token)"
        return try await next(request, body, baseURL)
    }
}

enum APIError: Error, Equatable {
    case unauthorized
    case notFound
    case invalidResponse
    case server(statusCode: Int)
    case stale(latestUpdatedAt: String?)
}

private extension Components.Schemas.Household {
    var appModel: Household {
        Household(id: id, name: name, role: role.appModel)
    }
}

private extension Components.Schemas.Household.rolePayload {
    var appModel: HouseholdRole {
        switch self {
        case .owner:
            return .owner
        case .member:
            return .member
        }
    }
}

private extension Components.Schemas.WeekPlanSummary {
    var appModel: WeekSummary {
        WeekSummary(
            household: SummaryHousehold(id: household.id, name: household.name),
            weekStartDate: weekStartDate,
            updatedAt: updatedAt,
            days: days.map(\.appModel)
        )
    }
}

private extension Components.Schemas.WeekPlanSummaryDay {
    var appModel: WeekSummaryDay {
        WeekSummaryDay(
            dayOfWeek: dayOfWeek.appModel,
            date: date,
            state: state.appModel,
            recipe: recipe?.appModel
        )
    }
}

private extension Components.Schemas.WeekPlanSummaryDay.dayOfWeekPayload {
    var appModel: Weekday {
        switch self {
        case .monday:
            return .monday
        case .tuesday:
            return .tuesday
        case .wednesday:
            return .wednesday
        case .thursday:
            return .thursday
        case .friday:
            return .friday
        case .saturday:
            return .saturday
        case .sunday:
            return .sunday
        }
    }
}

private extension Components.Schemas.WeekPlanSummaryDay.statePayload {
    var appModel: WeekDayState {
        switch self {
        case .empty:
            return .empty
        case .planned:
            return .planned
        case .skipped:
            return .skipped
        }
    }
}

private extension Components.Schemas.WeekPlanSummaryRecipe {
    var appModel: WeekSummaryRecipe {
        WeekSummaryRecipe(
            id: id,
            title: title,
            description: description,
            servings: servings,
            prepTimeMinutes: prepTimeMinutes,
            cookTimeMinutes: cookTimeMinutes,
            tags: tags
        )
    }
}

private extension Components.Schemas.ShoppingListSummary {
    var appModel: ShoppingListSummary {
        ShoppingListSummary(
            household: SummaryHousehold(id: household.id, name: household.name),
            weekStartDate: weekStartDate,
            updatedAt: updatedAt,
            groups: groups.map(\.appModel)
        )
    }
}

private extension Components.Schemas.ShoppingListSummaryGroup {
    var appModel: ShoppingListGroup {
        ShoppingListGroup(category: category, items: items.map(\.appModel))
    }
}

private extension Components.Schemas.ShoppingListSummaryItem {
    var appModel: ShoppingListItem {
        ShoppingListItem(
            itemKey: itemKey,
            label: label,
            amount: amount,
            unit: unit,
            checked: checked
        )
    }
}

private extension WeekPlanEventInput {
    typealias V2 = Components.Schemas.AppendWeekPlanEventRequest.Value2Payload

    var requestValue2: V2 {
        switch self {
        case .mealAssigned(let day, let recipeID):
            return .case3(.init(eventType: .meal_assigned, dayOfWeek: .init(rawValue: day.rawValue)!, recipeRef: recipeID))
        case .mealUnassigned(let day):
            return .case4(.init(eventType: .meal_unassigned, dayOfWeek: .init(rawValue: day.rawValue)!))
        case .mealLocked(let day):
            return .case5(.init(eventType: .meal_locked, dayOfWeek: .init(rawValue: day.rawValue)!))
        case .mealUnlocked(let day):
            return .case6(.init(eventType: .meal_unlocked, dayOfWeek: .init(rawValue: day.rawValue)!))
        case .daySkipped(let day):
            return .case8(.init(eventType: .day_skipped, dayOfWeek: .init(rawValue: day.rawValue)!))
        case .dayUnskipped(let day):
            return .case9(.init(eventType: .day_unskipped, dayOfWeek: .init(rawValue: day.rawValue)!))
        }
    }
}

private extension Components.Schemas.Recipe {
    var appModel: FullRecipe {
        FullRecipe(
            id: id,
            title: title,
            description: description,
            servings: servings,
            prepTimeMinutes: prepTimeMinutes,
            cookTimeMinutes: cookTimeMinutes,
            tags: tags,
            ingredients: ingredients.map(\.appModel),
            steps: steps.map(\.appModel)
        )
    }
}

private extension Components.Schemas.RecipeIngredient {
    var appModel: RecipeIngredient {
        RecipeIngredient(item: item, amount: amount, unit: unit, category: category)
    }
}

private extension Components.Schemas.RecipeStep {
    var appModel: RecipeStep {
        RecipeStep(text: text)
    }
}

private extension Components.Schemas.MealFeedbackEntry {
    var appModel: MealVote? {
        vote.appModel
    }
}

private extension Components.Schemas.MealFeedbackVote {
    var appModel: MealVote? {
        switch self {
        case .up:
            return .up
        case .down:
            return .down
        }
    }
}

private extension MealVote {
    var apiModel: Components.Schemas.MealFeedbackVote {
        switch self {
        case .up:
            return .up
        case .down:
            return .down
        }
    }
}

import Foundation
import HTTPTypes
import OpenAPIRuntime
import OpenAPIURLSession

struct VecklyAPIClient {
    private let _client: Client

    init(baseURL: URL, accessToken: @escaping @Sendable () async -> String?) {
        _client = Client(
            serverURL: baseURL,
            transport: URLSessionTransport(),
            middlewares: [AuthorizationMiddleware(getToken: accessToken)]
        )
    }

    func bootstrapHousehold() async throws -> Household {
        let output = try await _client.bootstrapMyHousehold()
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
        let output = try await _client.getMyHouseholds()
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
        let output = try await _client.getWeekPlanSummary(
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
        let output = try await _client.getShoppingListSummary(
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
        let output = try await _client.appendWeekPlanEvent(
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
        let output = try await _client.getRecipe(
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
        let output = try await _client.listMealFeedback(path: .init(householdId: householdID))
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
        let output = try await _client.upsertMealFeedback(
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

    func createRecipe(householdID: String, draft: RecipeDraft) async throws -> FullRecipe {
        let output = try await _client.createRecipe(
            path: .init(householdId: householdID),
            body: .json(draft.createPayload)
        )
        switch output {
        case let .created(r): return try r.body.json.appModel
        case .unauthorized: throw APIError.unauthorized
        case let .undocumented(statusCode, _): throw APIError.server(statusCode: statusCode)
        }
    }

    func updateRecipe(householdID: String, recipeID: String, draft: RecipeDraft) async throws -> FullRecipe {
        let output = try await _client.updateRecipe(
            path: .init(householdId: householdID, recipeId: recipeID),
            body: .json(draft.updatePayload)
        )
        switch output {
        case let .ok(r): return try r.body.json.appModel
        case .unauthorized: throw APIError.unauthorized
        case .notFound: throw APIError.notFound
        case let .undocumented(statusCode, _): throw APIError.server(statusCode: statusCode)
        }
    }

    func archiveRecipe(householdID: String, recipeID: String) async throws -> FullRecipe {
        let output = try await _client.updateRecipe(
            path: .init(householdId: householdID, recipeId: recipeID),
            body: .json(.init(isArchived: true))
        )
        switch output {
        case let .ok(r): return try r.body.json.appModel
        case .unauthorized: throw APIError.unauthorized
        case .notFound: throw APIError.notFound
        case let .undocumented(statusCode, _): throw APIError.server(statusCode: statusCode)
        }
    }

    func fillInRecipe(title: String) async throws -> RecipeDraft {
        let output = try await _client.fillInRecipe(
            body: .json(.init(title: title))
        )
        switch output {
        case let .ok(r): return try RecipeDraft(fillIn: r.body.json.recipe, originalTitle: title)
        case .unauthorized: throw APIError.unauthorized
        case .badRequest: throw APIError.server(statusCode: 400)
        case .unprocessableContent: throw APIError.server(statusCode: 422)
        case .tooManyRequests: throw APIError.server(statusCode: 429)
        case .internalServerError: throw APIError.server(statusCode: 500)
        case let .undocumented(statusCode, _): throw APIError.server(statusCode: statusCode)
        }
    }

    func importRecipeFromURL(_ urlString: String) async throws -> RecipeDraft {
        let output = try await _client.importRecipeFromUrl(
            body: .json(.init(url: urlString))
        )
        switch output {
        case let .ok(r): return try RecipeDraft(imported: r.body.json.recipe)
        case .unauthorized: throw APIError.unauthorized
        case .badRequest: throw APIError.server(statusCode: 400)
        case .unprocessableContent: throw APIError.server(statusCode: 422)
        case .tooManyRequests: throw APIError.server(statusCode: 429)
        case .internalServerError: throw APIError.server(statusCode: 500)
        case let .undocumented(statusCode, _): throw APIError.server(statusCode: statusCode)
        }
    }

    func listHouseholdRecipes(householdID: String, includePublic: Bool = false) async throws -> [FullRecipe] {
        let output = try await _client.listRecipes(
            path: .init(householdId: householdID),
            query: .init(includePublic: includePublic ? ._true : nil)
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
        let output = try await _client.generateWeekPlan(
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

    func listMembers(householdID: String) async throws -> [HouseholdMember] {
        let output = try await _client.listHouseholdMembers(path: .init(householdId: householdID))
        switch output {
        case let .ok(r): return try r.body.json.members.map(\.appModel)
        case .unauthorized: throw APIError.unauthorized
        case let .undocumented(statusCode, _): throw APIError.server(statusCode: statusCode)
        }
    }

    func getProfile(householdID: String) async throws -> HouseholdProfile? {
        let output = try await _client.getHouseholdProfile(path: .init(householdId: householdID))
        switch output {
        case let .ok(r): return try r.body.json.profile?.appModel
        case .unauthorized: throw APIError.unauthorized
        case let .undocumented(statusCode, _): throw APIError.server(statusCode: statusCode)
        }
    }

    func saveProfile(
        householdID: String,
        adults: Int, children: Int,
        priorities: [HouseholdPriority],
        avoidIngredients: [String],
        selectedDays: [Weekday]
    ) async throws -> HouseholdProfile {
        typealias DayPayload = Components.Schemas.UpsertHouseholdProfile.selectedDaysPayloadPayload
        typealias PrioPayload = Components.Schemas.UpsertHouseholdProfile.prioritiesPayloadPayload
        let payload = Components.Schemas.UpsertHouseholdProfile(
            adults: adults,
            children: children,
            priorities: priorities.compactMap { PrioPayload(rawValue: $0.rawValue) },
            avoidIngredients: avoidIngredients.filter { !$0.isEmpty },
            selectedDays: selectedDays.compactMap { DayPayload(day: .init(rawValue: $0.rawValue)!) }
        )
        let output = try await _client.upsertHouseholdProfile(path: .init(householdId: householdID), body: .json(payload))
        switch output {
        case let .ok(r): return try r.body.json.appModel
        case .unauthorized: throw APIError.unauthorized
        case let .undocumented(statusCode, _): throw APIError.server(statusCode: statusCode)
        }
    }

    func createInvite(householdID: String) async throws -> HouseholdInvite {
        let output = try await _client.createHouseholdInvite(path: .init(householdId: householdID))
        switch output {
        case let .created(r): return try r.body.json.appModel
        case .unauthorized: throw APIError.unauthorized
        case let .undocumented(statusCode, _): throw APIError.server(statusCode: statusCode)
        }
    }

    func listInvites(householdID: String) async throws -> [HouseholdInvite] {
        let output = try await _client.listHouseholdInvites(path: .init(householdId: householdID))
        switch output {
        case let .ok(r): return try r.body.json.invites.map(\.appModel)
        case .unauthorized: throw APIError.unauthorized
        case let .undocumented(statusCode, _): throw APIError.server(statusCode: statusCode)
        }
    }

    func revokeInvite(householdID: String, inviteID: String) async throws {
        let output = try await _client.revokeHouseholdInvite(path: .init(householdId: householdID, inviteId: inviteID))
        switch output {
        case .noContent: return
        case .unauthorized: throw APIError.unauthorized
        case let .undocumented(statusCode, _): throw APIError.server(statusCode: statusCode)
        }
    }

    func lookupInvite(token: String) async throws -> InviteLanding {
        let output = try await _client.getInviteLanding(path: .init(token: token))
        switch output {
        case let .ok(r):
            let json = try r.body.json
            return InviteLanding(householdName: json.householdName, status: json.status.rawValue)
        case .unauthorized: throw APIError.unauthorized
        case .notFound: throw APIError.notFound
        case let .undocumented(statusCode, _): throw APIError.server(statusCode: statusCode)
        }
    }

    func acceptInvite(token: String) async throws -> String {
        let output = try await _client.acceptInvite(path: .init(token: token))
        switch output {
        case let .ok(r): return try r.body.json.householdId
        case .unauthorized: throw APIError.unauthorized
        case .notFound: throw APIError.notFound
        case .conflict: throw APIError.server(statusCode: 409)
        case let .undocumented(statusCode, _): throw APIError.server(statusCode: statusCode)
        }
    }

    func listPrepBatches(householdID: String, from: String, to: String) async throws -> [PrepBatch] {
        typealias Op = Operations.get_sol_households_sol__lcub_householdId_rcub__sol_prep_batches
        let output = try await _client.get_sol_households_sol__lcub_householdId_rcub__sol_prep_batches(
            path: .init(householdId: householdID),
            query: .init(from: from, to: to)
        )
        switch output {
        case let .ok(r): return try r.body.json.batches.map(\.appModel)
        case .unauthorized: throw APIError.unauthorized
        case .badRequest: throw APIError.server(statusCode: 400)
        case .notFound: throw APIError.notFound
        case let .undocumented(statusCode, _): throw APIError.server(statusCode: statusCode)
        }
    }

    func createPrepBatch(
        householdID: String,
        recipeId: String?,
        cookDate: String,
        totalPortions: Int,
        assignments: [(date: String, mealType: MealType)]
    ) async throws -> PrepBatch {
        typealias AssignPayload = Components.Schemas.CreatePrepBatch.assignmentsPayloadPayload
        let payload = Components.Schemas.CreatePrepBatch(
            recipeId: recipeId,
            cookDate: cookDate,
            totalPortions: totalPortions,
            assignments: assignments.map { AssignPayload(date: $0.date, mealType: .init(rawValue: $0.mealType.rawValue)!) }
        )
        let output = try await _client.post_sol_households_sol__lcub_householdId_rcub__sol_prep_batches(
            path: .init(householdId: householdID),
            body: .json(payload)
        )
        switch output {
        case let .created(r): return try r.body.json.appModel
        case .unauthorized: throw APIError.unauthorized
        case .badRequest: throw APIError.server(statusCode: 400)
        case .notFound: throw APIError.notFound
        case let .undocumented(statusCode, _): throw APIError.server(statusCode: statusCode)
        }
    }

    func deletePrepBatch(householdID: String, batchID: String) async throws {
        let output = try await _client.delete_sol_households_sol__lcub_householdId_rcub__sol_prep_batches_sol__lcub_batchId_rcub_(
            path: .init(householdId: householdID, batchId: batchID)
        )
        switch output {
        case .ok: return
        case .unauthorized: throw APIError.unauthorized
        case .notFound: throw APIError.notFound
        case let .undocumented(statusCode, _): throw APIError.server(statusCode: statusCode)
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
        let output = try await _client.updateShoppingListState(
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
    let getToken: @Sendable () async -> String?

    @concurrent func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @concurrent @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        guard let token = await getToken() else { throw APIError.unauthorized }
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

private extension RecipeDraft {
    var apiIngredients: [Components.Schemas.RecipeIngredient] {
        ingredients.filter { !$0.item.isEmpty }.map {
            .init(item: $0.item, amount: $0.amount.isEmpty ? nil : $0.amount, unit: $0.unit.isEmpty ? nil : $0.unit)
        }
    }
    var apiSteps: [Components.Schemas.RecipeStep] { steps.filter { !$0.isEmpty }.map { .init(text: $0) } }

    var createPayload: Components.Schemas.CreateRecipe {
        .init(title: title, description: description.isEmpty ? nil : description,
              servings: servings, ingredients: apiIngredients, steps: apiSteps,
              prepTimeMinutes: prepTimeMinutes, cookTimeMinutes: cookTimeMinutes,
              sourceUrl: sourceUrl, source: sourceUrl != nil ? .url_import : .user_created)
    }
    var updatePayload: Components.Schemas.UpdateRecipe {
        .init(title: title, description: description.isEmpty ? nil : description,
              servings: servings, ingredients: apiIngredients, steps: apiSteps,
              prepTimeMinutes: prepTimeMinutes, cookTimeMinutes: cookTimeMinutes,
              sourceUrl: sourceUrl)
    }
}

private extension RecipeDraft {
    init(fillIn r: Components.Schemas.RecipeFillInResult, originalTitle: String) throws {
        self.init(
            title: r.title.isEmpty ? originalTitle : r.title,
            description: r.notes ?? "",
            servings: 4,
            prepTimeMinutes: r.prepTimeMinutes,
            ingredients: r.ingredients.map { DraftIngredient(item: $0.name, amount: formatAmount($0.amount), unit: $0.unit) },
            steps: r.steps
        )
    }
    init(imported r: Components.Schemas.ImportedRecipe) throws {
        self.init(
            title: r.title,
            servings: 4,
            prepTimeMinutes: r.prepTimeMinutes,
            ingredients: r.ingredients.map { DraftIngredient(item: $0.name, amount: $0.amount.map { formatAmount($0) } ?? "", unit: $0.unit ?? "") },
            sourceUrl: r.sourceUrl
        )
    }
}

private func formatAmount(_ v: Double) -> String {
    v.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", v) : String(format: "%.1f", v)
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
            isLocked: isLocked,
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

private extension Components.Schemas.PrepBatch {
    var appModel: PrepBatch {
        PrepBatch(
            id: id,
            householdId: householdId,
            recipeId: recipeId,
            cookDate: cookDate,
            totalPortions: totalPortions,
            assignments: assignments.map(\.appModel)
        )
    }
}

private extension Components.Schemas.PrepBatchAssignment {
    var appModel: PrepBatchAssignment {
        PrepBatchAssignment(
            id: id,
            batchId: batchId,
            date: date,
            mealType: MealType(rawValue: mealType.rawValue) ?? .dinner
        )
    }
}

private extension Components.Schemas.HouseholdMember {
    var appModel: HouseholdMember {
        HouseholdMember(userId: userId, role: role == .owner ? .owner : .member)
    }
}

private extension Components.Schemas.HouseholdProfile {
    var appModel: HouseholdProfile {
        HouseholdProfile(
            householdId: householdId,
            adults: adults,
            children: children,
            priorities: priorities.compactMap { HouseholdPriority(rawValue: $0.rawValue) },
            avoidIngredients: avoidIngredients,
            selectedDays: selectedDays.compactMap { Weekday(rawValue: $0.day.rawValue) }
        )
    }
}

private extension Components.Schemas.HouseholdInvite {
    var appModel: HouseholdInvite {
        HouseholdInvite(id: id, token: token, email: email, status: status.rawValue, expiresAt: expiresAt)
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

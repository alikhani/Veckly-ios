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

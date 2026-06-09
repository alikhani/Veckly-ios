import Foundation

struct VecklyAPIClient {
    let baseURL: URL
    let accessToken: () -> String?

    func bootstrapHousehold() async throws -> Household {
        try await send(path: "/households/me/bootstrap", method: "POST")
    }

    func listHouseholds() async throws -> [Household] {
        let response: MyHouseholdsResponse = try await send(path: "/households/me", method: "GET")
        return response.households
    }

    func weekSummary(householdID: String, weekStartDate: String) async throws -> WeekSummary {
        try await send(path: "/households/\(householdID)/week-plans/\(weekStartDate)/summary", method: "GET")
    }

    func shoppingListSummary(householdID: String, weekStartDate: String) async throws -> ShoppingListSummary {
        try await send(path: "/households/\(householdID)/shopping-lists/\(weekStartDate)/summary", method: "GET")
    }

    private func send<Response: Decodable>(path: String, method: String) async throws -> Response {
        guard let token = accessToken() else { throw APIError.unauthorized }
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        switch httpResponse.statusCode {
        case 200..<300:
            return try JSONDecoder.veckly.decode(Response.self, from: data)
        case 401:
            throw APIError.unauthorized
        case 404:
            throw APIError.notFound
        default:
            throw APIError.server(statusCode: httpResponse.statusCode)
        }
    }
}

enum APIError: Error, Equatable {
    case unauthorized
    case notFound
    case invalidResponse
    case server(statusCode: Int)
}

extension JSONDecoder {
    static var veckly: JSONDecoder {
        let decoder = JSONDecoder()
        return decoder
    }
}

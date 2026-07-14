import Foundation
import Observation

enum ProductEventName: String, CaseIterable, Sendable {
    case onboardingCompleted = "onboarding_completed"
    case firstWeekGenerated = "first_week_generated"
    case weekCompleted = "week_completed"
    case shoppingOpenedAfterWeekCompleted = "shopping_opened_after_week_completed"
    case shoppingShared = "shopping_shared"
    case partnerInviteClicked = "partner_invite_clicked"
    case shoppingMainListCompleted = "shopping_main_list_completed"
    case retroCompleted = "retro_completed"
}

enum ProductEventPropertyValue: Equatable, Sendable, Encodable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case double(Double)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        }
    }
}

typealias ProductEventProperties = [String: ProductEventPropertyValue]

protocol ProductEventStoreAPIClient {
    func createProductEvent(
        householdID: String,
        eventName: ProductEventName,
        weekStartDate: String?,
        properties: ProductEventProperties
    ) async throws
}

extension VecklyAPIClient: ProductEventStoreAPIClient {}

@MainActor
@Observable
final class ProductEventStore {
    private let apiClient: any ProductEventStoreAPIClient

    init(apiClient: any ProductEventStoreAPIClient) {
        self.apiClient = apiClient
    }

    /// Product measurement must never block the planning flow. Failures are
    /// intentionally swallowed; Supabase is the source of truth when events land.
    func record(
        _ eventName: ProductEventName,
        householdID: String,
        weekStartDate: String? = nil,
        properties: ProductEventProperties = [:]
    ) async {
        try? await apiClient.createProductEvent(
            householdID: householdID,
            eventName: eventName,
            weekStartDate: weekStartDate,
            properties: properties
        )
    }
}

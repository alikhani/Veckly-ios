import Foundation
import Testing
@testable import Veckly

@MainActor
struct ProductEventStoreTests {
    @Test func recordSendsTypedProductEvent() async {
        let apiClient = CapturingProductEventAPIClient()
        let store = ProductEventStore(apiClient: apiClient)

        await store.record(
            .weekCompleted,
            householdID: "household-1",
            weekStartDate: "2026-07-13",
            properties: [
                "plannedDinners": .int(5),
                "source": .string("session_end"),
                "fromCTA": .bool(true)
            ]
        )

        #expect(apiClient.events.count == 1)
        #expect(apiClient.events.first?.householdID == "household-1")
        #expect(apiClient.events.first?.eventName == .weekCompleted)
        #expect(apiClient.events.first?.weekStartDate == "2026-07-13")
        #expect(apiClient.events.first?.properties["plannedDinners"] == .int(5))
        #expect(apiClient.events.first?.properties["source"] == .string("session_end"))
        #expect(apiClient.events.first?.properties["fromCTA"] == .bool(true))
    }

    @Test func recordSwallowsAPIFailures() async {
        let apiClient = CapturingProductEventAPIClient(error: APIError.server(statusCode: 500))
        let store = ProductEventStore(apiClient: apiClient)

        await store.record(.shoppingShared, householdID: "household-1")

        #expect(apiClient.events.count == 1)
    }
}

private final class CapturingProductEventAPIClient: ProductEventStoreAPIClient {
    struct Event {
        let householdID: String
        let eventName: ProductEventName
        let weekStartDate: String?
        let properties: ProductEventProperties
    }

    private(set) var events: [Event] = []
    private let error: Error?

    init(error: Error? = nil) {
        self.error = error
    }

    func createProductEvent(
        householdID: String,
        eventName: ProductEventName,
        weekStartDate: String?,
        properties: ProductEventProperties
    ) async throws {
        events.append(Event(
            householdID: householdID,
            eventName: eventName,
            weekStartDate: weekStartDate,
            properties: properties
        ))
        if let error {
            throw error
        }
    }
}

import Foundation
import Testing
@testable import Veckly

@MainActor
struct HouseholdMealSignalStoreTests {
    @Test func loadsSignalsOnSuccess() async {
        let client = StubHouseholdMealSignalAPIClient(loadResult: .success(["pasta": .worksForFamily]))
        let store = HouseholdMealSignalStore(apiClient: client)

        await store.loadSignals(householdID: "household-1")

        #expect(store.signal(for: "pasta") == .worksForFamily)
    }

    @Test func fallsBackToEmptySignalsOnLoadFailure() async {
        let client = StubHouseholdMealSignalAPIClient(loadResult: .failure(APIError.server(statusCode: 500)))
        let store = HouseholdMealSignalStore(apiClient: client)

        await store.loadSignals(householdID: "household-1")

        #expect(store.signal(for: "pasta") == nil)
    }

    @Test func optimisticallySetsSignalAndKeepsItOnSuccess() async {
        let client = StubHouseholdMealSignalAPIClient()
        let store = HouseholdMealSignalStore(apiClient: client)

        await store.setSignal(householdID: "household-1", recipeID: "pasta", signal: .worksForFamily)

        #expect(store.signal(for: "pasta") == .worksForFamily)
        #expect(client.setCalls == [SetCall(householdID: "household-1", mealID: "pasta", signal: .worksForFamily)])
    }

    @Test func rollsBackSetSignalOnFailure() async {
        let client = StubHouseholdMealSignalAPIClient(setError: APIError.server(statusCode: 500))
        let store = HouseholdMealSignalStore(apiClient: client)
        await store.loadSignals(householdID: "household-1")

        await store.setSignal(householdID: "household-1", recipeID: "pasta", signal: .notForUs)

        #expect(store.signal(for: "pasta") == nil)
    }

    @Test func removesSignalAndRollsBackOnFailure() async {
        let client = StubHouseholdMealSignalAPIClient(loadResult: .success(["pasta": .worksForFamily]), removeError: APIError.server(statusCode: 500))
        let store = HouseholdMealSignalStore(apiClient: client)
        await store.loadSignals(householdID: "household-1")

        await store.setSignal(householdID: "household-1", recipeID: "pasta", signal: nil)

        #expect(store.signal(for: "pasta") == .worksForFamily)
    }
}

private struct SetCall: Equatable {
    let householdID: String
    let mealID: String
    let signal: HouseholdMealSignal
}

private final class StubHouseholdMealSignalAPIClient: HouseholdMealSignalStoreAPIClient {
    let loadResult: Result<[String: HouseholdMealSignal], Error>
    let setError: Error?
    let removeError: Error?
    private(set) var setCalls: [SetCall] = []

    init(
        loadResult: Result<[String: HouseholdMealSignal], Error> = .success([:]),
        setError: Error? = nil,
        removeError: Error? = nil
    ) {
        self.loadResult = loadResult
        self.setError = setError
        self.removeError = removeError
    }

    func householdMealSignals(householdID: String) async throws -> [String: HouseholdMealSignal] {
        try loadResult.get()
    }

    func removeHouseholdMealSignal(householdID: String, mealID: String) async throws {
        if let removeError { throw removeError }
    }

    func setHouseholdMealSignal(householdID: String, mealID: String, signal: HouseholdMealSignal) async throws {
        if let setError { throw setError }
        setCalls.append(SetCall(householdID: householdID, mealID: mealID, signal: signal))
    }
}

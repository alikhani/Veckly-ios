import Foundation
import Observation

enum HouseholdMealSignal: String, Codable, Equatable {
    case worksForFamily = "works_for_family"
    case notForUs = "not_for_us"
}

protocol HouseholdMealSignalStoreAPIClient {
    func householdMealSignals(householdID: String) async throws -> [String: HouseholdMealSignal]
    func removeHouseholdMealSignal(householdID: String, mealID: String) async throws
    func setHouseholdMealSignal(householdID: String, mealID: String, signal: HouseholdMealSignal) async throws
}

@MainActor
@Observable
final class HouseholdMealSignalStore {
    private let apiClient: any HouseholdMealSignalStoreAPIClient
    // recipeID -> shared household signal
    private var signals: [String: HouseholdMealSignal] = [:]

    init(apiClient: any HouseholdMealSignalStoreAPIClient) {
        self.apiClient = apiClient
    }

    func signal(for recipeID: String) -> HouseholdMealSignal? {
        signals[recipeID]
    }

    func loadSignals(householdID: String) async {
        do {
            signals = try await apiClient.householdMealSignals(householdID: householdID)
        } catch {
            // Quiet fallback: this is helpful shared memory, not a blocker for
            // opening the week or choosing dinner.
            signals = [:]
        }
    }

    func setSignal(householdID: String, recipeID: String, signal: HouseholdMealSignal?) async {
        let previous = signals[recipeID]
        signals[recipeID] = signal

        do {
            if let signal {
                try await apiClient.setHouseholdMealSignal(householdID: householdID, mealID: recipeID, signal: signal)
            } else {
                try await apiClient.removeHouseholdMealSignal(householdID: householdID, mealID: recipeID)
            }
        } catch {
            signals[recipeID] = previous
        }
    }

    func reset() {
        signals = [:]
    }
}

extension VecklyAPIClient: HouseholdMealSignalStoreAPIClient {}

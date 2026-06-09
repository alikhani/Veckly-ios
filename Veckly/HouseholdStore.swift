import Foundation
import Observation

@MainActor
@Observable
final class HouseholdStore {
    private let apiClient: VecklyAPIClient

    private(set) var households: [Household] = []
    private(set) var activeHousehold: Household?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    init(apiClient: VecklyAPIClient) {
        self.apiClient = apiClient
    }

    func bootstrapAndLoadHouseholds() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let bootstrapped = try await apiClient.bootstrapHousehold()
            let list = try await apiClient.listHouseholds()
            households = list.isEmpty ? [bootstrapped] : list
            activeHousehold = households.first(where: { $0.id == bootstrapped.id }) ?? households.first
        } catch {
            errorMessage = "We could not load your household."
        }
    }

    func reset() {
        households = []
        activeHousehold = nil
        errorMessage = nil
        isLoading = false
    }

    func seedForUITests() {
        let household = Household(id: "11111111-1111-1111-1111-111111111111", name: "Test household", role: .owner)
        households = [household]
        activeHousehold = household
    }
}

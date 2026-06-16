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

    private(set) var members: [HouseholdMember] = []
    private(set) var profile: HouseholdProfile?
    private(set) var invites: [HouseholdInvite] = []
    private(set) var detailsLastFetchedAt: Date?

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

    func loadHouseholdDetails(householdID: String) async {
        guard detailsLastFetchedAt == nil || Date().timeIntervalSince(detailsLastFetchedAt!) > 300 || members.isEmpty else { return }
        async let membersResult = apiClient.listMembers(householdID: householdID)
        async let profileResult = apiClient.getProfile(householdID: householdID)
        members = (try? await membersResult) ?? []
        profile = try? await profileResult
        detailsLastFetchedAt = Date()
    }

    func loadInvites(householdID: String) async {
        invites = (try? await apiClient.listInvites(householdID: householdID)) ?? []
    }

    func saveProfile(
        householdID: String,
        adults: Int, children: Int,
        priorities: [HouseholdPriority],
        avoidIngredients: [String],
        selectedDays: [Weekday]
    ) async throws {
        profile = try await apiClient.saveProfile(
            householdID: householdID,
            adults: adults, children: children,
            priorities: priorities,
            avoidIngredients: avoidIngredients,
            selectedDays: selectedDays
        )
    }

    func createInvite(householdID: String) async throws -> HouseholdInvite {
        let invite = try await apiClient.createInvite(householdID: householdID)
        invites.insert(invite, at: 0)
        return invite
    }

    func revokeInvite(householdID: String, inviteID: String) async throws {
        try await apiClient.revokeInvite(householdID: householdID, inviteID: inviteID)
        invites.removeAll { $0.id == inviteID }
    }

    func lookupInvite(token: String) async throws -> InviteLanding {
        try await apiClient.lookupInvite(token: token)
    }

    func acceptInvite(token: String) async throws {
        try await apiClient.acceptInvite(token: token)
        // Reload households so the new one appears
        let list = try await apiClient.listHouseholds()
        if !list.isEmpty { households = list }
    }

    func reset() {
        households = []
        activeHousehold = nil
        errorMessage = nil
        isLoading = false
        members = []
        profile = nil
        invites = []
        detailsLastFetchedAt = nil
    }

    func seedForUITests() {
        let household = Household(id: "11111111-1111-1111-1111-111111111111", name: "Test household", role: .owner)
        households = [household]
        activeHousehold = household
    }
}

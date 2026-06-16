import Foundation
import Testing
@testable import Veckly

@MainActor
struct HouseholdStoreTests {
    @Test func householdDetailsAreCachedPerHousehold() async {
        let apiClient = FakeHouseholdStoreAPIClient()
        let store = HouseholdStore(apiClient: apiClient)

        await store.loadHouseholdDetails(householdID: TestHouseholds.first.id)

        #expect(store.detailsHouseholdID == TestHouseholds.first.id)
        #expect(store.members == [HouseholdMember(userId: TestHouseholds.userA, role: .owner)])
        #expect(store.cachedProfile(for: TestHouseholds.first.id)?.householdId == TestHouseholds.first.id)

        await store.loadHouseholdDetails(householdID: TestHouseholds.second.id)

        #expect(store.detailsHouseholdID == TestHouseholds.second.id)
        #expect(store.members == [HouseholdMember(userId: TestHouseholds.userB, role: .member)])
        #expect(store.cachedProfile(for: TestHouseholds.first.id) == nil)
        #expect(store.cachedProfile(for: TestHouseholds.second.id)?.householdId == TestHouseholds.second.id)
    }

    @Test func acceptingInviteSelectsJoinedHouseholdAndClearsDetails() async throws {
        let apiClient = FakeHouseholdStoreAPIClient()
        let store = HouseholdStore(apiClient: apiClient)
        store.setActiveHousehold(TestHouseholds.first)

        await store.loadHouseholdDetails(householdID: TestHouseholds.first.id)

        let joinedHouseholdID = try await store.acceptInvite(token: "invite-token")

        #expect(joinedHouseholdID == TestHouseholds.second.id)
        #expect(store.activeHousehold == TestHouseholds.second)
        #expect(store.households == [TestHouseholds.first, TestHouseholds.second])
        #expect(store.members.isEmpty)
        #expect(store.profile == nil)
        #expect(store.detailsHouseholdID == nil)
    }

    @Test func changingActiveHouseholdClearsHouseholdScopedState() async {
        let apiClient = FakeHouseholdStoreAPIClient()
        let store = HouseholdStore(apiClient: apiClient)

        store.setActiveHousehold(TestHouseholds.first)
        await store.loadHouseholdDetails(householdID: TestHouseholds.first.id)
        await store.loadInvites(householdID: TestHouseholds.first.id)

        store.setActiveHousehold(TestHouseholds.second)

        #expect(store.members.isEmpty)
        #expect(store.profile == nil)
        #expect(store.invites.isEmpty)
        #expect(store.detailsHouseholdID == nil)
        #expect(store.invitesHouseholdID == nil)
    }
}

private enum TestHouseholds {
    static let userA = "11111111-1111-1111-1111-111111111111"
    static let userB = "22222222-2222-2222-2222-222222222222"
    static let first = Household(id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", name: "First household", role: .owner)
    static let second = Household(id: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", name: "Second household", role: .member)
}

private final class FakeHouseholdStoreAPIClient: HouseholdStoreAPIClient {
    func bootstrapHousehold() async throws -> Household {
        TestHouseholds.first
    }

    func listHouseholds() async throws -> [Household] {
        [TestHouseholds.first, TestHouseholds.second]
    }

    func listMembers(householdID: String) async throws -> [HouseholdMember] {
        if householdID == TestHouseholds.first.id {
            return [HouseholdMember(userId: TestHouseholds.userA, role: .owner)]
        }
        return [HouseholdMember(userId: TestHouseholds.userB, role: .member)]
    }

    func getProfile(householdID: String) async throws -> HouseholdProfile? {
        HouseholdProfile(
            householdId: householdID,
            adults: householdID == TestHouseholds.first.id ? 2 : 1,
            children: 0,
            priorities: [.quick],
            avoidIngredients: [],
            selectedDays: [.monday, .tuesday]
        )
    }

    func saveProfile(
        householdID: String,
        adults: Int,
        children: Int,
        priorities: [HouseholdPriority],
        avoidIngredients: [String],
        selectedDays: [Weekday]
    ) async throws -> HouseholdProfile {
        HouseholdProfile(
            householdId: householdID,
            adults: adults,
            children: children,
            priorities: priorities,
            avoidIngredients: avoidIngredients,
            selectedDays: selectedDays
        )
    }

    func createInvite(householdID: String) async throws -> HouseholdInvite {
        HouseholdInvite(
            id: "cccccccc-cccc-cccc-cccc-cccccccccccc",
            token: "invite-token",
            email: nil,
            status: "pending",
            expiresAt: "2026-06-30T00:00:00.000Z"
        )
    }

    func listInvites(householdID: String) async throws -> [HouseholdInvite] {
        [try await createInvite(householdID: householdID)]
    }

    func revokeInvite(householdID: String, inviteID: String) async throws {}

    func lookupInvite(token: String) async throws -> InviteLanding {
        InviteLanding(householdName: "Second household", status: "pending")
    }

    func acceptInvite(token: String) async throws -> String {
        TestHouseholds.second.id
    }
}

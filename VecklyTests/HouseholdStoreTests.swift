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
        let selectionStore = FakeHouseholdSelectionStore()
        let store = HouseholdStore(apiClient: apiClient, selectionStore: selectionStore)
        store.setActiveHousehold(TestHouseholds.first)

        await store.loadHouseholdDetails(householdID: TestHouseholds.first.id)

        let joinedHouseholdID = try await store.acceptInvite(token: "invite-token")

        #expect(joinedHouseholdID == TestHouseholds.second.id)
        #expect(store.activeHousehold == TestHouseholds.second)
        #expect(store.households == [TestHouseholds.first, TestHouseholds.second])
        #expect(store.members.isEmpty)
        #expect(store.profile == nil)
        #expect(store.detailsHouseholdID == nil)
        #expect(selectionStore.selectedHouseholdIDValue == TestHouseholds.second.id)
    }

    @Test func bootstrapPrefersPersistedHouseholdSelection() async {
        let apiClient = FakeHouseholdStoreAPIClient()
        let selectionStore = FakeHouseholdSelectionStore(selectedHouseholdIDValue: TestHouseholds.second.id)
        let store = HouseholdStore(apiClient: apiClient, selectionStore: selectionStore)

        await store.bootstrapAndLoadHouseholds()

        #expect(store.households == [TestHouseholds.first, TestHouseholds.second])
        #expect(store.activeHousehold == TestHouseholds.second)
    }

    @Test func leavingActiveHouseholdSelectsAnotherHousehold() async throws {
        let apiClient = FakeHouseholdStoreAPIClient()
        let selectionStore = FakeHouseholdSelectionStore()
        let store = HouseholdStore(apiClient: apiClient, selectionStore: selectionStore)
        store.setActiveHousehold(TestHouseholds.first)
        await store.loadHouseholdDetails(householdID: TestHouseholds.first.id)

        try await store.leaveHousehold(householdID: TestHouseholds.first.id, userID: TestHouseholds.userA)

        #expect(store.households == [TestHouseholds.second])
        #expect(store.activeHousehold == TestHouseholds.second)
        #expect(selectionStore.selectedHouseholdIDValue == TestHouseholds.second.id)
    }

    @Test func deletingOnlyHouseholdBootstrapsReplacementHousehold() async throws {
        let apiClient = FakeHouseholdStoreAPIClient(households: [TestHouseholds.first], bootstrappedHousehold: TestHouseholds.bootstrapped)
        let selectionStore = FakeHouseholdSelectionStore()
        let store = HouseholdStore(apiClient: apiClient, selectionStore: selectionStore)
        store.setActiveHousehold(TestHouseholds.first)

        try await store.deleteHousehold(householdID: TestHouseholds.first.id)

        #expect(store.households == [TestHouseholds.bootstrapped])
        #expect(store.activeHousehold == TestHouseholds.bootstrapped)
        #expect(selectionStore.selectedHouseholdIDValue == TestHouseholds.bootstrapped.id)
    }

    @Test func loadHouseholdDetailsIgnoresReentrantCallWhileInFlight() async {
        let apiClient = SlowFakeHouseholdStoreAPIClient()
        let store = HouseholdStore(apiClient: apiClient)

        let firstCall = Task { await store.loadHouseholdDetails(householdID: TestHouseholds.first.id) }
        await apiClient.waitUntilFetchStarted()
        #expect(store.isLoadingDetails == true)

        // A second call arriving while the first is still in flight must not
        // start a second fetch (the race the guard in HouseholdStore prevents).
        await store.loadHouseholdDetails(householdID: TestHouseholds.first.id)
        #expect(await apiClient.fetchCount == 1)

        await apiClient.resumeFetch()
        await firstCall.value
        #expect(store.isLoadingDetails == false)
        #expect(store.detailsHouseholdID == TestHouseholds.first.id)
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

private actor SlowFakeHouseholdStoreAPIClient: HouseholdStoreAPIClient {
    private(set) var fetchCount = 0
    private var hasStarted = false
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var resumeContinuation: CheckedContinuation<Void, Never>?

    func waitUntilFetchStarted() async {
        if hasStarted { return }
        await withCheckedContinuation { startedContinuation = $0 }
    }

    func resumeFetch() {
        resumeContinuation?.resume()
        resumeContinuation = nil
    }

    func listMembers(householdID: String) async throws -> [HouseholdMember] {
        fetchCount += 1
        hasStarted = true
        startedContinuation?.resume()
        startedContinuation = nil
        await withCheckedContinuation { resumeContinuation = $0 }
        return [HouseholdMember(userId: TestHouseholds.userA, role: .owner)]
    }

    func getProfile(householdID: String) async throws -> HouseholdProfile? { nil }
    func bootstrapHousehold() async throws -> Household { TestHouseholds.first }
    func listHouseholds() async throws -> [Household] { [TestHouseholds.first] }

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
        HouseholdInvite(id: "invite", token: "token", email: nil, status: "pending", expiresAt: "2026-06-30T00:00:00.000Z")
    }

    func listInvites(householdID: String) async throws -> [HouseholdInvite] { [] }
    func revokeInvite(householdID: String, inviteID: String) async throws {}
    func lookupInvite(token: String) async throws -> InviteLanding {
        InviteLanding(householdName: "First household", status: "pending")
    }
    func acceptInvite(token: String) async throws -> String { TestHouseholds.first.id }
    func renameHousehold(householdID: String, name: String) async throws {}
    func removeMember(householdID: String, userID: String) async throws {}
    func deleteHousehold(householdID: String) async throws {}
}

private enum TestHouseholds {
    static let userA = "11111111-1111-1111-1111-111111111111"
    static let userB = "22222222-2222-2222-2222-222222222222"
    static let first = Household(id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", name: "First household", role: .owner)
    static let second = Household(id: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", name: "Second household", role: .member)
    static let bootstrapped = Household(id: "cccccccc-cccc-cccc-cccc-cccccccccccc", name: "My household", role: .owner)
}

private final class FakeHouseholdStoreAPIClient: HouseholdStoreAPIClient {
    private var households: [Household]
    private let bootstrappedHousehold: Household

    init(
        households: [Household] = [TestHouseholds.first, TestHouseholds.second],
        bootstrappedHousehold: Household = TestHouseholds.first
    ) {
        self.households = households
        self.bootstrappedHousehold = bootstrappedHousehold
    }

    func bootstrapHousehold() async throws -> Household {
        if !households.contains(bootstrappedHousehold) {
            households = [bootstrappedHousehold]
        }
        return bootstrappedHousehold
    }

    func listHouseholds() async throws -> [Household] {
        households
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
        if !households.contains(TestHouseholds.second) {
            households.append(TestHouseholds.second)
        }
        return TestHouseholds.second.id
    }

    func renameHousehold(householdID: String, name: String) async throws {}

    func removeMember(householdID: String, userID: String) async throws {
        if userID == TestHouseholds.userA {
            households.removeAll { $0.id == householdID }
        }
    }

    func deleteHousehold(householdID: String) async throws {
        households.removeAll { $0.id == householdID }
    }
}

private final class FakeHouseholdSelectionStore: HouseholdSelectionPersisting {
    var selectedHouseholdIDValue: String?

    init(selectedHouseholdIDValue: String? = nil) {
        self.selectedHouseholdIDValue = selectedHouseholdIDValue
    }

    func selectedHouseholdID() -> String? {
        selectedHouseholdIDValue
    }

    func setSelectedHouseholdID(_ householdID: String) {
        selectedHouseholdIDValue = householdID
    }

    func clearSelectedHouseholdID() {
        selectedHouseholdIDValue = nil
    }
}

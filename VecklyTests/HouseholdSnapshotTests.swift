import Foundation
import Testing
@testable import Veckly

/// The active household (id, name, role) is remembered per user so a cold
/// start can show cached content without waiting for the household list.
@MainActor
struct HouseholdSnapshotTests {
    private let household = Household(id: "11111111-1111-1111-1111-111111111111", name: "Familjen", role: .owner)
    private let other = Household(id: "22222222-2222-2222-2222-222222222222", name: "Andra", role: .member)

    private func makeStore(
        api: SnapshotHouseholdAPI = SnapshotHouseholdAPI(),
        snapshots: InMemoryHouseholdSnapshots = InMemoryHouseholdSnapshots(),
        userID: String? = "user-1"
    ) -> HouseholdStore {
        HouseholdStore(
            apiClient: api,
            selectionStore: SnapshotSelectionStore(),
            snapshotStore: snapshots,
            currentUserID: { userID }
        )
    }

    @Test func settingTheActiveHouseholdRemembersItForTheUser() {
        let snapshots = InMemoryHouseholdSnapshots()
        let store = makeStore(snapshots: snapshots)

        store.setActiveHousehold(household)

        #expect(snapshots.load(userID: "user-1") == household)
    }

    @Test func restoringShowsTheRememberedHouseholdWithoutTheNetwork() {
        let snapshots = InMemoryHouseholdSnapshots()
        snapshots.save(household, userID: "user-1")
        let api = SnapshotHouseholdAPI()
        let store = makeStore(api: api, snapshots: snapshots)

        let restored = store.restoreFromSnapshot()

        #expect(restored == household)
        #expect(store.activeHousehold == household)
        #expect(api.callCount == 0)
        #expect(!store.isLoading)
    }

    @Test func anotherUsersSnapshotIsNeverRestored() {
        let snapshots = InMemoryHouseholdSnapshots()
        snapshots.save(household, userID: "someone-else")
        let store = makeStore(snapshots: snapshots)

        #expect(store.restoreFromSnapshot() == nil)
        #expect(store.activeHousehold == nil)
    }

    @Test func withoutAUserNothingIsRememberedOrRestored() {
        let snapshots = InMemoryHouseholdSnapshots()
        snapshots.save(household, userID: "user-1")
        let store = makeStore(snapshots: snapshots, userID: nil)

        #expect(store.restoreFromSnapshot() == nil)
        store.setActiveHousehold(other)
        #expect(snapshots.load(userID: "user-1") == household)
    }

    @Test func resettingForgetsTheSnapshot() {
        let snapshots = InMemoryHouseholdSnapshots()
        let store = makeStore(snapshots: snapshots)
        store.setActiveHousehold(household)

        store.reset()

        #expect(snapshots.load(userID: "user-1") == nil)
    }

    @Test func renamingUpdatesTheSnapshot() async throws {
        let snapshots = InMemoryHouseholdSnapshots()
        let store = makeStore(snapshots: snapshots)
        store.setActiveHousehold(household)

        try await store.renameHousehold(householdID: household.id, name: "Nytt namn")

        #expect(snapshots.load(userID: "user-1")?.name == "Nytt namn")
    }

    @Test func theServerListConfirmsTheRestoredHousehold() async {
        let snapshots = InMemoryHouseholdSnapshots()
        snapshots.save(household, userID: "user-1")
        let api = SnapshotHouseholdAPI()
        api.households = [household, other]
        let store = makeStore(api: api, snapshots: snapshots)
        store.restoreFromSnapshot()

        await store.bootstrapAndLoadHouseholds()

        #expect(store.activeHousehold?.id == household.id)
        #expect(store.households.count == 2)
    }

    @Test func aRestoredHouseholdTheServerNoLongerListsIsReplaced() async {
        let snapshots = InMemoryHouseholdSnapshots()
        snapshots.save(household, userID: "user-1")
        let api = SnapshotHouseholdAPI()
        api.households = [other]
        let store = makeStore(api: api, snapshots: snapshots)
        store.restoreFromSnapshot()

        await store.bootstrapAndLoadHouseholds()

        #expect(store.activeHousehold?.id == other.id)
        #expect(snapshots.load(userID: "user-1") == other)
    }

    @Test func aFailedBootstrapKeepsTheRestoredHousehold() async {
        let snapshots = InMemoryHouseholdSnapshots()
        snapshots.save(household, userID: "user-1")
        let api = SnapshotHouseholdAPI()
        api.failure = URLError(.cannotConnectToHost)
        let store = makeStore(api: api, snapshots: snapshots)
        store.restoreFromSnapshot()

        await store.bootstrapAndLoadHouseholds()

        #expect(store.activeHousehold == household)
        #expect(snapshots.load(userID: "user-1") == household)
    }

    @Test func theDiskSnapshotRoundTripsAndIsPerUser() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("HouseholdSnapshotTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = HouseholdSnapshotDiskStore(baseDirectory: directory)

        disk.save(household, userID: "user-1")

        #expect(disk.load(userID: "user-1") == household)
        #expect(disk.load(userID: "user-2") == nil)
        disk.clear()
        #expect(disk.load(userID: "user-1") == nil)
    }
}

private final class InMemoryHouseholdSnapshots: HouseholdSnapshotPersisting {
    private var stored: (userID: String, household: Household)?
    func load(userID: String) -> Household? { stored?.userID == userID ? stored?.household : nil }
    func save(_ household: Household, userID: String) { stored = (userID, household) }
    func clear() { stored = nil }
}

private final class SnapshotSelectionStore: HouseholdSelectionPersisting {
    var id: String?
    func selectedHouseholdID() -> String? { id }
    func setSelectedHouseholdID(_ householdID: String) { id = householdID }
    func clearSelectedHouseholdID() { id = nil }
}

private final class SnapshotHouseholdAPI: HouseholdStoreAPIClient {
    var households: [Household] = []
    var failure: Error?
    private(set) var callCount = 0

    private func check() throws {
        callCount += 1
        if let failure { throw failure }
    }

    func bootstrapHousehold() async throws -> Household {
        try check()
        return households[0]
    }
    func listHouseholds() async throws -> [Household] { try check(); return households }
    func listMembers(householdID: String) async throws -> [HouseholdMember] { [] }
    func getProfile(householdID: String) async throws -> HouseholdProfile? { nil }
    func saveProfile(householdID: String, adults: Int, children: Int, priorities: [HouseholdPriority], avoidIngredients: [String], selectedDays: [HouseholdDaySelection]) async throws -> HouseholdProfile { throw APIError.notFound }
    func createInvite(householdID: String) async throws -> HouseholdInvite { throw APIError.notFound }
    func listInvites(householdID: String) async throws -> [HouseholdInvite] { [] }
    func revokeInvite(householdID: String, inviteID: String) async throws {}
    func lookupInvite(token: String) async throws -> InviteLanding { throw APIError.notFound }
    func acceptInvite(token: String) async throws -> String { throw APIError.notFound }
    func renameHousehold(householdID: String, name: String) async throws {}
    func removeMember(householdID: String, userID: String) async throws {}
    func deleteHousehold(householdID: String) async throws {}
}

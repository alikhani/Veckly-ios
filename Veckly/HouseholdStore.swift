import Foundation
import Observation

@MainActor
@Observable
final class HouseholdStore {
    private let apiClient: any HouseholdStoreAPIClient
    private let selectionStore: any HouseholdSelectionPersisting

    private(set) var households: [Household] = []
    private(set) var activeHousehold: Household?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private(set) var members: [HouseholdMember] = []
    private(set) var profile: HouseholdProfile?
    private(set) var invites: [HouseholdInvite] = []
    private(set) var detailsLastFetchedAt: Date?
    private(set) var detailsHouseholdID: String?
    private(set) var invitesHouseholdID: String?
    private(set) var isLoadingDetails = false
    private(set) var isLoadingInvites = false
    private(set) var detailsErrorMessage: String?
    private(set) var invitesErrorMessage: String?

    init(
        apiClient: any HouseholdStoreAPIClient,
        selectionStore: any HouseholdSelectionPersisting = UserDefaultsHouseholdSelectionStore()
    ) {
        self.apiClient = apiClient
        self.selectionStore = selectionStore
    }

    func bootstrapAndLoadHouseholds() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let bootstrapped = try await apiClient.bootstrapHousehold()
            let list = try await apiClient.listHouseholds()
            households = list.isEmpty ? [bootstrapped] : list
            let preferredHouseholdID = selectionStore.selectedHouseholdID()
            let preferredHousehold = households.first(where: { $0.id == preferredHouseholdID })
            let bootstrappedHousehold = households.first(where: { $0.id == bootstrapped.id })
            setActiveHousehold(preferredHousehold ?? bootstrappedHousehold ?? households.first)
        } catch {
            errorMessage = L10n.string("error.household.load")
        }
    }

    func loadHouseholdDetails(householdID: String, force: Bool = false) async {
        let cacheIsFresh = !force
            && detailsHouseholdID == householdID
            && detailsLastFetchedAt.map { Date().timeIntervalSince($0) <= 300 } == true
            && !members.isEmpty
        guard !cacheIsFresh else { return }
        guard !isLoadingDetails else { return }

        if detailsHouseholdID != householdID {
            resetDetails()
        }

        isLoadingDetails = true
        detailsErrorMessage = nil
        defer { isLoadingDetails = false }

        do {
            async let membersResult = apiClient.listMembers(householdID: householdID)
            async let profileResult = apiClient.getProfile(householdID: householdID)
            let newMembers = try await membersResult
            let newProfile = try await profileResult
            members = newMembers
            profile = newProfile
            detailsHouseholdID = householdID
            detailsLastFetchedAt = Date()
        } catch {
            detailsErrorMessage = L10n.string("error.household.details")
        }
    }

    func loadInvites(householdID: String) async {
        if invitesHouseholdID != householdID {
            invites = []
            invitesHouseholdID = householdID
        }

        isLoadingInvites = true
        invitesErrorMessage = nil
        defer { isLoadingInvites = false }

        do {
            invites = try await apiClient.listInvites(householdID: householdID)
        } catch {
            invitesErrorMessage = L10n.string("error.household.invites")
        }
    }

    func saveProfile(
        householdID: String,
        adults: Int, children: Int,
        priorities: [HouseholdPriority],
        avoidIngredients: [String],
        selectedDays: [Weekday]
    ) async throws {
        let savedProfile = try await apiClient.saveProfile(
            householdID: householdID,
            adults: adults, children: children,
            priorities: priorities,
            avoidIngredients: avoidIngredients,
            selectedDays: selectedDays
        )
        profile = savedProfile
        detailsHouseholdID = householdID
        detailsLastFetchedAt = Date()
    }

    func renameHousehold(householdID: String, name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try await apiClient.renameHousehold(householdID: householdID, name: trimmed)
        if let idx = households.firstIndex(where: { $0.id == householdID }) {
            households[idx] = Household(id: householdID, name: trimmed, role: households[idx].role)
        }
        if activeHousehold?.id == householdID {
            activeHousehold = Household(id: householdID, name: trimmed, role: activeHousehold!.role)
        }
    }

    func removeMember(householdID: String, userID: String) async throws {
        try await apiClient.removeMember(householdID: householdID, userID: userID)
        if detailsHouseholdID == householdID {
            members.removeAll { $0.userId == userID }
        }
    }

    func leaveHousehold(householdID: String, userID: String) async throws {
        try await apiClient.removeMember(householdID: householdID, userID: userID)
        try await reloadHouseholds(preferredActiveHouseholdID: nil)
    }

    func deleteHousehold(householdID: String) async throws {
        try await apiClient.deleteHousehold(householdID: householdID)
        try await reloadHouseholds(preferredActiveHouseholdID: nil)
    }

    func createInvite(householdID: String) async throws -> HouseholdInvite {
        let invite = try await apiClient.createInvite(householdID: householdID)
        invitesHouseholdID = householdID
        invites.insert(invite, at: 0)
        return invite
    }

    func revokeInvite(householdID: String, inviteID: String) async throws {
        try await apiClient.revokeInvite(householdID: householdID, inviteID: inviteID)
        if invitesHouseholdID == householdID {
            invites.removeAll { $0.id == inviteID }
        }
    }

    func lookupInvite(token: String) async throws -> InviteLanding {
        try await apiClient.lookupInvite(token: token)
    }

    func acceptInvite(token: String) async throws -> String {
        let joinedHouseholdID = try await apiClient.acceptInvite(token: token)
        try await reloadHouseholds(preferredActiveHouseholdID: joinedHouseholdID)
        return joinedHouseholdID
    }

    func cachedProfile(for householdID: String) -> HouseholdProfile? {
        guard detailsHouseholdID == householdID, profile?.householdId == householdID else { return nil }
        return profile
    }

    func setActiveHousehold(_ household: Household?) {
        guard activeHousehold?.id != household?.id else {
            activeHousehold = household
            persistActiveHouseholdID(household?.id)
            return
        }
        activeHousehold = household
        persistActiveHouseholdID(household?.id)
        resetDetails()
        resetInvites()
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
        detailsHouseholdID = nil
        invitesHouseholdID = nil
        isLoadingDetails = false
        isLoadingInvites = false
        detailsErrorMessage = nil
        invitesErrorMessage = nil
        selectionStore.clearSelectedHouseholdID()
    }

    func seedForUITests() {
        let household = Household(id: "11111111-1111-1111-1111-111111111111", name: "Test household", role: .owner)
        households = [household]
        activeHousehold = household
        members = [HouseholdMember(userId: "11111111-1111-1111-1111-111111111111", role: .owner, givenName: nil, familyName: nil)]
        profile = HouseholdProfile(
            householdId: household.id,
            adults: 2,
            children: 1,
            priorities: [.quick, .childFriendly],
            avoidIngredients: [],
            selectedDays: [.monday, .tuesday, .wednesday, .thursday, .friday]
        )
        detailsHouseholdID = household.id
        detailsLastFetchedAt = Date()
    }

    private func resetDetails() {
        members = []
        profile = nil
        detailsLastFetchedAt = nil
        detailsHouseholdID = nil
        detailsErrorMessage = nil
    }

    private func resetInvites() {
        invites = []
        invitesHouseholdID = nil
        invitesErrorMessage = nil
    }

    private func persistActiveHouseholdID(_ householdID: String?) {
        guard let householdID else {
            selectionStore.clearSelectedHouseholdID()
            return
        }
        selectionStore.setSelectedHouseholdID(householdID)
    }

    private func reloadHouseholds(preferredActiveHouseholdID: String?) async throws {
        var list = try await apiClient.listHouseholds()

        if list.isEmpty {
            let bootstrapped = try await apiClient.bootstrapHousehold()
            list = try await apiClient.listHouseholds()
            if list.isEmpty {
                list = [bootstrapped]
            }
        }

        households = list

        let nextActiveHousehold = preferredActiveHouseholdID.flatMap { preferredID in
            list.first(where: { $0.id == preferredID })
        } ?? activeHousehold.flatMap { current in
            list.first(where: { $0.id == current.id })
        } ?? list.first

        setActiveHousehold(nextActiveHousehold)
    }
}

protocol HouseholdSelectionPersisting {
    func selectedHouseholdID() -> String?
    func setSelectedHouseholdID(_ householdID: String)
    func clearSelectedHouseholdID()
}

struct UserDefaultsHouseholdSelectionStore: HouseholdSelectionPersisting {
    private static let storageKey = "veckly.active-household-id"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func selectedHouseholdID() -> String? {
        userDefaults.string(forKey: Self.storageKey)
    }

    func setSelectedHouseholdID(_ householdID: String) {
        userDefaults.set(householdID, forKey: Self.storageKey)
    }

    func clearSelectedHouseholdID() {
        userDefaults.removeObject(forKey: Self.storageKey)
    }
}

protocol HouseholdStoreAPIClient {
    func bootstrapHousehold() async throws -> Household
    func listHouseholds() async throws -> [Household]
    func listMembers(householdID: String) async throws -> [HouseholdMember]
    func getProfile(householdID: String) async throws -> HouseholdProfile?
    func saveProfile(
        householdID: String,
        adults: Int,
        children: Int,
        priorities: [HouseholdPriority],
        avoidIngredients: [String],
        selectedDays: [Weekday]
    ) async throws -> HouseholdProfile
    func createInvite(householdID: String) async throws -> HouseholdInvite
    func listInvites(householdID: String) async throws -> [HouseholdInvite]
    func revokeInvite(householdID: String, inviteID: String) async throws
    func lookupInvite(token: String) async throws -> InviteLanding
    func acceptInvite(token: String) async throws -> String
    func renameHousehold(householdID: String, name: String) async throws
    func removeMember(householdID: String, userID: String) async throws
    func deleteHousehold(householdID: String) async throws
}

extension VecklyAPIClient: HouseholdStoreAPIClient {}

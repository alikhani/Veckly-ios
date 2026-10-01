import Foundation
import Observation

enum HouseholdLoadState: Equatable {
    case initialLoading
    case refreshing
    case ready
    case stale
    case empty
    case failed
}

enum HouseholdDetailsLoadState: Equatable {
    case initialLoading
    case refreshing
    case ready
    case stale
    case failed
}

@MainActor
@Observable
final class HouseholdStore {
    private let apiClient: any HouseholdStoreAPIClient
    private let selectionStore: any HouseholdSelectionPersisting

    private(set) var households: [Household] = []
    private(set) var activeHousehold: Household?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var hasLoadedOnce = false

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
    private(set) var weekPulse: WeekPulse?
    private(set) var isLoadingWeekPulse = false
    private(set) var weekPulseErrorMessage: String?

    init(
        apiClient: any HouseholdStoreAPIClient,
        selectionStore: any HouseholdSelectionPersisting = UserDefaultsHouseholdSelectionStore()
    ) {
        self.apiClient = apiClient
        self.selectionStore = selectionStore
    }

    var loadState: HouseholdLoadState {
        if isLoading { return households.isEmpty ? .initialLoading : .refreshing }
        if errorMessage != nil { return households.isEmpty ? .failed : .stale }
        if households.isEmpty { return hasLoadedOnce ? .empty : .initialLoading }
        return .ready
    }

    func detailsLoadState(for householdID: String) -> HouseholdDetailsLoadState {
        let hasDetails = detailsHouseholdID == householdID
        if isLoadingDetails { return hasDetails ? .refreshing : .initialLoading }
        if detailsErrorMessage != nil { return hasDetails ? .stale : .failed }
        return hasDetails ? .ready : .initialLoading
    }

    @discardableResult
    func bootstrapAndLoadHouseholds() async -> Bool {
        guard !isLoading else { return false }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let bootstrapped = try await apiClient.bootstrapHousehold()
            let list = try await apiClient.listHouseholds()
            households = uniqueHouseholds(list.isEmpty ? [bootstrapped] : list)
            let preferredHouseholdID = selectionStore.selectedHouseholdID()
            let preferredHousehold = households.first(where: { $0.id == preferredHouseholdID })
            let bootstrappedHousehold = households.first(where: { $0.id == bootstrapped.id })
            setActiveHousehold(preferredHousehold ?? bootstrappedHousehold ?? households.first)
            hasLoadedOnce = true
            return true
        } catch {
            hasLoadedOnce = true
            errorMessage = L10n.string("error.household.load")
            return false
        }
    }

    @discardableResult
    func loadHouseholdDetails(householdID: String, force: Bool = false) async -> Bool {
        let cacheIsFresh = !force
            && detailsHouseholdID == householdID
            && detailsLastFetchedAt.map { Date().timeIntervalSince($0) <= 300 } == true
            && !members.isEmpty
        guard !cacheIsFresh else { return true }
        guard !isLoadingDetails else { return false }

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
            return true
        } catch {
            detailsErrorMessage = L10n.string("error.household.details")
            return false
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

    @discardableResult
    func loadWeekPulse(householdID: String, weekStartDate: String) async -> Bool {
        guard !isLoadingWeekPulse else { return false }
        isLoadingWeekPulse = true
        weekPulseErrorMessage = nil
        defer { isLoadingWeekPulse = false }
        do {
            weekPulse = try await apiClient.weekPulse(householdID: householdID, weekStartDate: weekStartDate)
            return true
        } catch {
            weekPulseErrorMessage = L10n.string("pulse.loadError")
            return false
        }
    }

    func saveWeekPulse(householdID: String, weekStartDate: String, draft: WeekPulseDraft) async throws {
        weekPulse = try await apiClient.saveWeekPulse(householdID: householdID, weekStartDate: weekStartDate, draft: draft)
        weekPulseErrorMessage = nil
    }

    func saveProfile(
        householdID: String,
        adults: Int, children: Int,
        priorities: [HouseholdPriority],
        avoidIngredients: [String],
        selectedDays: [HouseholdDaySelection]
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
        if let current = activeHousehold, current.id == householdID {
            activeHousehold = Household(id: householdID, name: trimmed, role: current.role)
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
        hasLoadedOnce = false
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
        weekPulse = nil
        isLoadingWeekPulse = false
        weekPulseErrorMessage = nil
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
            selectedDays: [.monday, .tuesday, .wednesday, .thursday, .friday].map { HouseholdDaySelection(day: $0) }
        )
        detailsHouseholdID = household.id
        detailsLastFetchedAt = Date()
        hasLoadedOnce = true
    }

    private func uniqueHouseholds(_ list: [Household]) -> [Household] {
        var seen = Set<String>()
        return list.filter { seen.insert($0.id).inserted }
    }

    private func resetDetails() {
        members = []
        profile = nil
        detailsLastFetchedAt = nil
        detailsHouseholdID = nil
        detailsErrorMessage = nil
        weekPulse = nil
        weekPulseErrorMessage = nil
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

        households = uniqueHouseholds(list)

        let nextActiveHousehold = preferredActiveHouseholdID.flatMap { preferredID in
            list.first(where: { $0.id == preferredID })
        } ?? activeHousehold.flatMap { current in
            list.first(where: { $0.id == current.id })
        } ?? list.first

        setActiveHousehold(nextActiveHousehold)
        hasLoadedOnce = true
        errorMessage = nil
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
        selectedDays: [HouseholdDaySelection]
    ) async throws -> HouseholdProfile
    func createInvite(householdID: String) async throws -> HouseholdInvite
    func listInvites(householdID: String) async throws -> [HouseholdInvite]
    func revokeInvite(householdID: String, inviteID: String) async throws
    func lookupInvite(token: String) async throws -> InviteLanding
    func acceptInvite(token: String) async throws -> String
    func renameHousehold(householdID: String, name: String) async throws
    func removeMember(householdID: String, userID: String) async throws
    func deleteHousehold(householdID: String) async throws
    func weekPulse(householdID: String, weekStartDate: String) async throws -> WeekPulse
    func saveWeekPulse(householdID: String, weekStartDate: String, draft: WeekPulseDraft) async throws -> WeekPulse
}

extension HouseholdStoreAPIClient {
    func weekPulse(householdID: String, weekStartDate: String) async throws -> WeekPulse {
        WeekPulse(householdID: householdID, weekStartDate: weekStartDate, responseCount: 0, memberCount: 1, members: [])
    }

    func saveWeekPulse(householdID: String, weekStartDate: String, draft: WeekPulseDraft) async throws -> WeekPulse {
        try await weekPulse(householdID: householdID, weekStartDate: weekStartDate)
    }
}

extension VecklyAPIClient: HouseholdStoreAPIClient {}

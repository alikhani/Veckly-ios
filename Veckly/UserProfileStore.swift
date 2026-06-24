import Foundation
import Observation

@MainActor
@Observable
final class UserProfileStore {
    private let apiClient: any UserProfileStoreAPIClient

    private(set) var givenName: String?
    private(set) var familyName: String?
    private(set) var isLoading = false
    private(set) var mutationError: String?

    func clearMutationError() { mutationError = nil }

    init(apiClient: any UserProfileStoreAPIClient) {
        self.apiClient = apiClient
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let profile = try await apiClient.getMyProfile()
            givenName = profile?.givenName
            familyName = profile?.familyName
        } catch {
            // Best-effort — the edit screen falls back to empty fields, and
            // the members list falls back to the generic label either way.
        }
    }

    func save(givenName: String, familyName: String?) async throws {
        mutationError = nil
        do {
            let profile = try await apiClient.setMyName(givenName: givenName, familyName: familyName)
            self.givenName = profile.givenName
            self.familyName = profile.familyName
        } catch {
            mutationError = L10n.string("error.profile.save")
            throw error
        }
    }

    func reset() {
        givenName = nil
        familyName = nil
        isLoading = false
        mutationError = nil
    }
}

protocol UserProfileStoreAPIClient {
    func getMyProfile() async throws -> UserProfile?
    func setMyName(givenName: String, familyName: String?) async throws -> UserProfile
}

extension VecklyAPIClient: UserProfileStoreAPIClient {}

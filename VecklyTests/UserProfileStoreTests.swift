import Foundation
import Testing
@testable import Veckly

@MainActor
struct UserProfileStoreTests {
    @Test func loadIfNeededPopulatesTheNameOnFirstCall() async {
        let client = StubUserProfileAPIClient(profile: UserProfile(userId: "user-1", givenName: "Nima", familyName: nil))
        let store = UserProfileStore(apiClient: client)

        await store.loadIfNeeded()

        #expect(store.givenName == "Nima")
        #expect(client.getMyProfileCount == 1)
    }

    @Test func loadIfNeededDoesNotRefetchOnceLoaded() async {
        let client = StubUserProfileAPIClient(profile: UserProfile(userId: "user-1", givenName: "Nima", familyName: nil))
        let store = UserProfileStore(apiClient: client)

        await store.loadIfNeeded()
        await store.loadIfNeeded()

        #expect(client.getMyProfileCount == 1)
    }

    /// The whole reason `load()` stays separate from `loadIfNeeded()`:
    /// `EditDisplayNameView` needs a guaranteed-fresh value every time it
    /// opens, not whatever was cached by an earlier background prefetch.
    @Test func loadAlwaysRefetchesRegardlessOfLoadIfNeededHavingRunAlready() async {
        let client = StubUserProfileAPIClient(profile: UserProfile(userId: "user-1", givenName: "Nima", familyName: nil))
        let store = UserProfileStore(apiClient: client)

        await store.loadIfNeeded()
        client.profile = UserProfile(userId: "user-1", givenName: "Updated", familyName: nil)
        await store.load()

        #expect(store.givenName == "Updated")
        #expect(client.getMyProfileCount == 2)
    }

    @Test func resetAllowsLoadIfNeededToFetchAgain() async {
        let client = StubUserProfileAPIClient(profile: UserProfile(userId: "user-1", givenName: "Nima", familyName: nil))
        let store = UserProfileStore(apiClient: client)

        await store.loadIfNeeded()
        store.reset()
        await store.loadIfNeeded()

        #expect(client.getMyProfileCount == 2)
    }
}

private final class StubUserProfileAPIClient: UserProfileStoreAPIClient {
    var profile: UserProfile?
    private(set) var getMyProfileCount = 0

    init(profile: UserProfile?) {
        self.profile = profile
    }

    func getMyProfile() async throws -> UserProfile? {
        getMyProfileCount += 1
        return profile
    }

    func setMyName(givenName: String, familyName: String?) async throws -> UserProfile {
        UserProfile(userId: "user-1", givenName: givenName, familyName: familyName)
    }
}

import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    let environment: AppEnvironment
    let authSessionStore: AuthSessionStore
    let apiClient: VecklyAPIClient
    let householdStore: HouseholdStore
    let weekStore: WeekStore
    let shoppingListStore: ShoppingListStore
    private let usesSeededCoreReader: Bool

    init(environment: AppEnvironment) {
        self.environment = environment
        self.usesSeededCoreReader = ProcessInfo.processInfo.environment["VECKLY_UI_TEST_MODE"] == "core-reader"
        let authSessionStore = AuthSessionStore(environment: environment)
        let apiClient = VecklyAPIClient(baseURL: environment.apiBaseURL) {
            authSessionStore.accessToken
        }

        self.authSessionStore = authSessionStore
        self.apiClient = apiClient
        self.householdStore = HouseholdStore(apiClient: apiClient)
        self.weekStore = WeekStore(apiClient: apiClient)
        self.shoppingListStore = ShoppingListStore(apiClient: apiClient)

        if usesSeededCoreReader {
            authSessionStore.seedForUITests()
            householdStore.seedForUITests()
            weekStore.seedForUITests()
            shoppingListStore.seedForUITests()
        }
    }

    func restoreSession() async {
        await authSessionStore.restoreSession()
        if usesSeededCoreReader { return }
        guard authSessionStore.isSignedIn else { return }
        await loadCoreReader()
    }

    func completeSignInWithApple(identityToken: String, nonce: String?) async {
        await authSessionStore.signInWithApple(identityToken: identityToken, nonce: nonce)
        guard authSessionStore.isSignedIn else { return }
        await loadCoreReader()
    }

    func signInWithEmail(email: String, password: String) async {
        await authSessionStore.signInWithEmail(email: email, password: password)
        guard authSessionStore.isSignedIn else { return }
        await loadCoreReader()
    }

    func signUpWithEmail(email: String, password: String) async {
        await authSessionStore.signUpWithEmail(email: email, password: password)
        guard authSessionStore.isSignedIn else { return }
        await loadCoreReader()
    }

    func loadCoreReader() async {
        await householdStore.bootstrapAndLoadHouseholds()
        guard let household = householdStore.activeHousehold else { return }
        await weekStore.loadCurrentWeek(household: household)
        await shoppingListStore.loadCurrentWeek(household: household, weekStartDate: weekStore.weekStartDate)
    }

    func signOut() {
        authSessionStore.signOut()
        householdStore.reset()
        weekStore.reset()
        shoppingListStore.reset()
    }

    // Call when any API response returns 401. Tries to refresh the token and
    // reload data; signs out if refresh fails (dead or missing refresh token).
    func handleUnauthorized() async {
        let refreshed = await authSessionStore.refreshSession()
        if refreshed {
            await loadCoreReader()
        } else {
            signOut()
        }
    }
}

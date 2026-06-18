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
    let recipeStore: RecipeStore
    let prepBatchStore: PrepBatchStore
    let feedbackStore: FeedbackStore
    private let usesSeededCoreReader: Bool

    init(environment: AppEnvironment) {
        self.environment = environment
        self.usesSeededCoreReader = ProcessInfo.processInfo.environment["VECKLY_UI_TEST_MODE"] == "core-reader"
        let authSessionStore = AuthSessionStore(environment: environment)
        let apiClient = VecklyAPIClient(baseURL: environment.apiBaseURL) {
            await authSessionStore.currentValidToken()
        }

        self.authSessionStore = authSessionStore
        self.apiClient = apiClient
        self.householdStore = HouseholdStore(apiClient: apiClient)
        self.weekStore = WeekStore(apiClient: apiClient)
        self.shoppingListStore = ShoppingListStore(apiClient: apiClient)
        self.recipeStore = RecipeStore(apiClient: apiClient)
        self.prepBatchStore = PrepBatchStore(apiClient: apiClient)
        self.feedbackStore = FeedbackStore(apiClient: apiClient)

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

    var needsOnboarding: Bool {
        guard authSessionStore.isSignedIn,
              !householdStore.isLoading,
              let household = householdStore.activeHousehold else { return false }
        return householdStore.cachedProfile(for: household.id) == nil
    }

    func loadCoreReader() async {
        await householdStore.bootstrapAndLoadHouseholds()
        if let household = householdStore.activeHousehold {
            await householdStore.loadHouseholdDetails(householdID: household.id)
        }
        await loadActiveHouseholdReaderData(resetFeatureStores: false)
    }

    func loadActiveHouseholdReaderData(resetFeatureStores: Bool = true) async {
        guard let household = householdStore.activeHousehold else { return }
        if resetFeatureStores {
            weekStore.reset()
            shoppingListStore.reset()
            recipeStore.reset()
            prepBatchStore.reset()
            feedbackStore.reset()
        }
        let weekStartDate = WeekCalendar.currentWeekStartDate()
        async let week: Void = weekStore.loadCurrentWeek(household: household)
        async let shopping: Void = shoppingListStore.loadCurrentWeek(household: household, weekStartDate: weekStartDate)
        async let feedback: Void = feedbackStore.loadFeedback(householdID: household.id)
        _ = await (week, shopping, feedback)
    }

    func signOut() {
        authSessionStore.signOut()
        resetAllStores()
    }

    func deleteAccount() async throws {
        try await authSessionStore.deleteAccount()
        resetAllStores()
    }

    private func resetAllStores() {
        householdStore.reset()
        weekStore.reset()
        shoppingListStore.reset()
        recipeStore.reset()
        prepBatchStore.reset()
        feedbackStore.reset()
    }

    /// Loads recipes for the household then seeds FeedbackStore from the
    /// userVote field on each recipe — so the vote UI is consistent whether
    /// the user opens the Recipes tab before or after FeedbackStore is loaded.
    func loadRecipesAndSeedFeedback(householdID: String) async {
        await recipeStore.loadRecipes(householdID: householdID)
        for recipe in recipeStore.recipes {
            if let voteString = recipe.userVote, let vote = MealVote(rawValue: voteString) {
                feedbackStore.seedVote(for: recipe.id, vote: vote)
            }
        }
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

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
    let userProfileStore: UserProfileStore
    private let usesSeededCoreReader: Bool

    init(environment: AppEnvironment) {
        self.environment = environment
        self.usesSeededCoreReader = ProcessInfo.processInfo.environment["VECKLY_UI_TEST_MODE"] == "core-reader"
        let authSessionStore = AuthSessionStore(environment: environment)
        let apiClient = VecklyAPIClient(
            baseURL: environment.apiBaseURL,
            accessToken: { await authSessionStore.currentValidToken() },
            refreshToken: { await authSessionStore.refreshSession() }
        )

        self.authSessionStore = authSessionStore
        self.apiClient = apiClient
        self.householdStore = HouseholdStore(apiClient: apiClient)
        self.weekStore = WeekStore(apiClient: apiClient)
        self.shoppingListStore = ShoppingListStore(apiClient: apiClient)
        self.recipeStore = RecipeStore(apiClient: apiClient)
        self.prepBatchStore = PrepBatchStore(apiClient: apiClient)
        self.feedbackStore = FeedbackStore(apiClient: apiClient)
        self.userProfileStore = UserProfileStore(apiClient: apiClient)

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

    func completeSignInWithApple(identityToken: String, nonce: String?, givenName: String?, familyName: String?) async {
        await authSessionStore.signInWithApple(identityToken: identityToken, nonce: nonce)
        guard authSessionStore.isSignedIn else { return }
        // Best-effort — Apple only ever supplies a name on the account's very
        // first authorization, so this is the one chance to capture it. A
        // failure here shouldn't block sign-in; the user can still set their
        // name later from Settings.
        if let givenName {
            try? await userProfileStore.save(givenName: givenName, familyName: familyName)
        }
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

    // `detailsHouseholdID == household.id` matters as much as `!isLoadingDetails`:
    // right after bootstrap finishes, the active household is set but details haven't
    // started loading yet, so `cachedProfile` is nil for a household we simply haven't
    // checked — without this guard that reads as "needs onboarding" and the onboarding
    // cover flashes in before the real profile arrives.
    nonisolated static func needsOnboarding(
        isSignedIn: Bool,
        isLoadingHouseholds: Bool,
        isLoadingDetails: Bool,
        activeHouseholdID: String?,
        detailsHouseholdID: String?,
        hasProfile: Bool
    ) -> Bool {
        guard isSignedIn,
              !isLoadingHouseholds,
              !isLoadingDetails,
              let activeHouseholdID,
              detailsHouseholdID == activeHouseholdID else { return false }
        return !hasProfile
    }

    var needsOnboarding: Bool {
        Self.needsOnboarding(
            isSignedIn: authSessionStore.isSignedIn,
            isLoadingHouseholds: householdStore.isLoading,
            isLoadingDetails: householdStore.isLoadingDetails,
            activeHouseholdID: householdStore.activeHousehold?.id,
            detailsHouseholdID: householdStore.detailsHouseholdID,
            hasProfile: householdStore.activeHousehold.map { householdStore.cachedProfile(for: $0.id) != nil } ?? false
        )
    }

    func loadCoreReader() async {
        await householdStore.bootstrapAndLoadHouseholds()
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
        // Keep household-scoped profile/member context in sync with week/shopping
        // data when the active household changes after a switch/join/leave/delete.
        await householdStore.loadHouseholdDetails(householdID: household.id)
        let weekStartDate = WeekCalendar.currentWeekStartDate()
        async let week: Void = weekStore.loadCurrentWeek(household: household)
        async let shopping: Void = shoppingListStore.loadCurrentWeek(household: household, weekStartDate: weekStartDate)
        async let prep: Void = prepBatchStore.load(householdID: household.id, weekStartDate: weekStartDate)
        async let feedback: Void = feedbackStore.loadFeedback(householdID: household.id)
        async let recipes: Void = recipeStore.loadRecipes(householdID: household.id)
        _ = await (week, shopping, prep, feedback, recipes)
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
        userProfileStore.reset()
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

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
    let householdMealSignalStore: HouseholdMealSignalStore
    let recipeRecommendationStore: RecipeRecommendationStore
    let familyCookbookStore: FamilyCookbookStore
    let householdSavedRecipesStore: HouseholdSavedRecipesStore
    let userProfileStore: UserProfileStore
    let productEventStore: ProductEventStore
    let sundayReminderScheduler = SundayReminderScheduler()
    /// Not `private` — a handful of call sites outside `AppRefreshCoordinator`
    /// still need it directly: UI-test seeding at init (below),
    /// `recordProductEvent`, and `refreshSundayReminderIfNeeded`. Every
    /// network refresh decision itself (the thing that used to be four
    /// scattered `guard !usesSeededCoreReader` checks across `RootView` and
    /// `WeekTabView`) now goes through `refreshCoordinator`, which reads this
    /// same flag once at construction time as its single source of truth.
    let usesSeededCoreReader: Bool
    let refreshCoordinator: AppRefreshCoordinator

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
        self.householdMealSignalStore = HouseholdMealSignalStore(apiClient: apiClient)
        self.recipeRecommendationStore = RecipeRecommendationStore(apiClient: apiClient)
        self.familyCookbookStore = FamilyCookbookStore(apiClient: apiClient)
        self.householdSavedRecipesStore = HouseholdSavedRecipesStore(apiClient: apiClient)
        self.userProfileStore = UserProfileStore(apiClient: apiClient)
        self.productEventStore = ProductEventStore(apiClient: apiClient)
        self.refreshCoordinator = AppRefreshCoordinator(
            usesSeededCoreReader: usesSeededCoreReader,
            householdStore: householdStore,
            weekStore: weekStore,
            shoppingListStore: shoppingListStore,
            prepBatchStore: prepBatchStore,
            feedbackStore: feedbackStore,
            householdMealSignalStore: householdMealSignalStore,
            recipeStore: recipeStore
        )

        if usesSeededCoreReader {
            authSessionStore.seedForUITests()
            householdStore.seedForUITests()
            let scenarioRawValue = ProcessInfo.processInfo.environment["VECKLY_UI_TEST_WEEK_SCENARIO"]
            let scenario = scenarioRawValue.flatMap(WeekStore.UITestWeekScenario.init(rawValue:)) ?? .legacyPartial
            weekStore.seedForUITests(scenario: scenario)
            shoppingListStore.seedForUITests()
        }
    }

    func restoreSession() async {
        await authSessionStore.restoreSession()
        if usesSeededCoreReader { return }
        guard authSessionStore.isSignedIn else { return }
        await loadCoreReader()
    }

    /// App-wide (not tied to the Week tab being visible) so the reminder can
    /// actually reach someone who isn't looking at the week plan — see
    /// `SundayReminderScheduler` for the weekend-only/once-per-day/lazy-
    /// permission design. Skipped under UI-test seeding to avoid a real
    /// notification-permission prompt during automated runs.
    func refreshSundayReminderIfNeeded() async {
        guard !usesSeededCoreReader, let household = householdStore.activeHousehold else { return }
        let nextWeekStart = WeekCalendar.addWeeks(to: WeekCalendar.currentWeekStartDate(), offset: 1)
        await sundayReminderScheduler.refreshIfNeeded {
            let hasContent = await weekStore.peekHasContent(household: household, weekStartDate: nextWeekStart)
            return !hasContent
        }
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

    func loadCoreReader(trigger: AppRefreshCoordinator.Trigger = .coldLaunch) async {
        await refreshCoordinator.refreshCoreReader(trigger: trigger)
    }

    /// Resets household-scoped stores (when the active household itself
    /// changed) and refreshes the new active household's data.
    /// `refreshCoordinator.refreshActiveHouseholdData` already covers what
    /// used to be a separate explicit `loadHouseholdDetails` call here plus
    /// the week/shopping/prep/feedback/signals/recipes `async let` block —
    /// see its doc comment for why household details are part of that same
    /// bundle rather than fetched sequentially first.
    func loadActiveHouseholdReaderData(resetFeatureStores: Bool = true) async {
        guard let household = householdStore.activeHousehold else { return }
        if resetFeatureStores {
            weekStore.reset()
            shoppingListStore.reset()
            recipeStore.reset()
            prepBatchStore.reset()
            feedbackStore.reset()
            householdMealSignalStore.reset()
            recipeRecommendationStore.reset()
            familyCookbookStore.reset()
            householdSavedRecipesStore.reset()
        }
        await refreshCoordinator.refreshActiveHouseholdData(household: household, trigger: .householdChanged)
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
        householdMealSignalStore.reset()
        recipeRecommendationStore.reset()
        familyCookbookStore.reset()
        householdSavedRecipesStore.reset()
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

    func recordProductEvent(
        _ eventName: ProductEventName,
        weekStartDate: String? = nil,
        properties: ProductEventProperties = [:]
    ) {
        guard !usesSeededCoreReader, let householdID = householdStore.activeHousehold?.id else { return }
        Task {
            await productEventStore.record(
                eventName,
                householdID: householdID,
                weekStartDate: weekStartDate,
                properties: properties
            )
        }
    }
}

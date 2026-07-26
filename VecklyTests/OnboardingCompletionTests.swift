import Foundation
import Testing
@testable import Veckly

@MainActor
struct OnboardingCompletionTests {
    @Test func successfulCompletionCreatesGoToDishThenSavesProfile() async {
        let recipeAPI = FakeOnboardingRecipeAPIClient()
        let householdAPI = FakeOnboardingHouseholdAPIClient()
        let recipeStore = RecipeStore(apiClient: recipeAPI, cacheStore: NoOpRecipeCache())
        let householdStore = HouseholdStore(apiClient: householdAPI)

        let outcome = await OnboardingCompletion.run(
            recipeStore: recipeStore,
            householdStore: householdStore,
            householdID: TestOnboardingHousehold.id,
            adults: 2,
            children: 1,
            priorities: [.quick],
            avoidIngredients: ["nuts"],
            selectedDays: [.monday, .wednesday].map { HouseholdDaySelection(day: $0) },
            goToDishTitle: "  Taco Tuesday  "
        )

        #expect(outcome == .success(goToDishSaved: true))
        #expect(recipeAPI.createdDraftTitles == ["Filled: Taco Tuesday"])
        #expect(householdStore.profile?.adults == 2)
        #expect(householdStore.profile?.children == 1)
        #expect(householdStore.profile?.priorities == [.quick])
        #expect(householdStore.profile?.avoidIngredients == ["nuts"])
        #expect(householdStore.profile?.selectedDays.map(\.day) == [.monday, .wednesday])
    }

    @Test func daySignalsSetInOnboardingSurviveTheRoundTripToTheSavedProfile() async {
        // Onboarding only sends plain day identity today (no dedicated
        // day-rhythm question, per Fas 1's decision — see
        // PLAN-ios-familjeupplevelse-2026-07.md). This test guards the
        // adjacent contract: if a day *does* carry non-default signals
        // (e.g. set later in Household preferences and passed through the
        // same save path), they must not be dropped or reordered.
        let recipeAPI = FakeOnboardingRecipeAPIClient()
        let householdAPI = FakeOnboardingHouseholdAPIClient()
        let recipeStore = RecipeStore(apiClient: recipeAPI, cacheStore: NoOpRecipeCache())
        let householdStore = HouseholdStore(apiClient: householdAPI)

        let fridayWithSignals = HouseholdDaySelection(
            day: .friday,
            servingsOverride: 6,
            occasion: .guests,
            effortLevel: .busy,
            leftoversIntent: true,
            lateEvening: true,
            cookingTolerance: .relaxed
        )

        let outcome = await OnboardingCompletion.run(
            recipeStore: recipeStore,
            householdStore: householdStore,
            householdID: TestOnboardingHousehold.id,
            adults: 2,
            children: 0,
            priorities: [],
            avoidIngredients: [],
            selectedDays: [HouseholdDaySelection(day: .monday), fridayWithSignals],
            goToDishTitle: ""
        )

        #expect(outcome == .success(goToDishSaved: false))
        #expect(householdStore.profile?.selectedDays.first(where: { $0.day == .friday }) == fridayWithSignals)
    }

    @Test func emptyGoToDishTitleSkipsRecipeCreationButStillSavesProfile() async {
        let recipeAPI = FakeOnboardingRecipeAPIClient()
        let householdAPI = FakeOnboardingHouseholdAPIClient()
        let recipeStore = RecipeStore(apiClient: recipeAPI, cacheStore: NoOpRecipeCache())
        let householdStore = HouseholdStore(apiClient: householdAPI)

        let outcome = await OnboardingCompletion.run(
            recipeStore: recipeStore,
            householdStore: householdStore,
            householdID: TestOnboardingHousehold.id,
            adults: 1,
            children: 0,
            priorities: [],
            avoidIngredients: [],
            selectedDays: [HouseholdDaySelection(day: .monday)],
            goToDishTitle: "   "
        )

        #expect(outcome == .success(goToDishSaved: false))
        #expect(recipeAPI.createdDraftTitles.isEmpty)
        #expect(householdStore.profile != nil)
    }

    @Test func goToDishCreateFailureStopsBeforeProfileIsSaved() async {
        let recipeAPI = FakeOnboardingRecipeAPIClient()
        recipeAPI.shouldFailCreate = true
        let householdAPI = FakeOnboardingHouseholdAPIClient()
        let recipeStore = RecipeStore(apiClient: recipeAPI, cacheStore: NoOpRecipeCache())
        let householdStore = HouseholdStore(apiClient: householdAPI)

        let outcome = await OnboardingCompletion.run(
            recipeStore: recipeStore,
            householdStore: householdStore,
            householdID: TestOnboardingHousehold.id,
            adults: 2,
            children: 0,
            priorities: [.quick],
            avoidIngredients: [],
            selectedDays: [HouseholdDaySelection(day: .monday)],
            goToDishTitle: "Taco Tuesday"
        )

        #expect(outcome == .goToDishSaveFailed)
        // The household profile must stay nil: RootView's onboarding cover is
        // driven only by profile presence, so saving it here would dismiss
        // onboarding before the user ever sees the retry error.
        #expect(householdStore.profile == nil)
        #expect(householdAPI.saveProfileCallCount == 0)
    }

    @Test func aiFillInFailureFallsBackToTitleOnlyDraft() async {
        let recipeAPI = FakeOnboardingRecipeAPIClient()
        recipeAPI.shouldFailFillIn = true
        let householdAPI = FakeOnboardingHouseholdAPIClient()
        let recipeStore = RecipeStore(apiClient: recipeAPI, cacheStore: NoOpRecipeCache())
        let householdStore = HouseholdStore(apiClient: householdAPI)

        let outcome = await OnboardingCompletion.run(
            recipeStore: recipeStore,
            householdStore: householdStore,
            householdID: TestOnboardingHousehold.id,
            adults: 2,
            children: 0,
            priorities: [],
            avoidIngredients: [],
            selectedDays: [HouseholdDaySelection(day: .monday)],
            goToDishTitle: "Taco Tuesday"
        )

        #expect(outcome == .success(goToDishSaved: true))
        #expect(recipeAPI.createdDraftTitles == ["Taco Tuesday"])
    }

    @Test func profileSaveFailureIsReportedSeparately() async {
        let recipeAPI = FakeOnboardingRecipeAPIClient()
        let householdAPI = FakeOnboardingHouseholdAPIClient()
        householdAPI.shouldFailSaveProfile = true
        let recipeStore = RecipeStore(apiClient: recipeAPI, cacheStore: NoOpRecipeCache())
        let householdStore = HouseholdStore(apiClient: householdAPI)

        let outcome = await OnboardingCompletion.run(
            recipeStore: recipeStore,
            householdStore: householdStore,
            householdID: TestOnboardingHousehold.id,
            adults: 2,
            children: 0,
            priorities: [],
            avoidIngredients: [],
            selectedDays: [HouseholdDaySelection(day: .monday)],
            goToDishTitle: ""
        )

        #expect(outcome == .profileSaveFailed)
        #expect(householdStore.profile == nil)
    }
}

private enum TestOnboardingHousehold {
    static let id = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
}

private enum TestOnboardingError: Error {
    case failed
}

private final class NoOpRecipeCache: RecipeStoreCachePersisting {
    func loadRecipes(householdID: String) -> PersistedRecipeCache? { nil }
    func saveRecipes(_ cache: PersistedRecipeCache) {}
    func deleteRecipes(householdID: String) {}
}

private final class FakeOnboardingRecipeAPIClient: RecipeStoreAPIClient {
    var shouldFailFillIn = false
    var shouldFailCreate = false
    private(set) var createdDraftTitles: [String] = []

    func listHouseholdRecipes(householdID: String, includePublic: Bool) async throws -> [FullRecipe] { [] }

    func recipe(householdID: String, recipeID: String) async throws -> FullRecipe {
        throw TestOnboardingError.failed
    }

    func createRecipe(householdID: String, draft: RecipeDraft) async throws -> FullRecipe {
        if shouldFailCreate { throw TestOnboardingError.failed }
        createdDraftTitles.append(draft.title)
        return FullRecipe(
            id: "33333333-3333-3333-3333-333333333333",
            title: draft.title,
            description: draft.description,
            servings: draft.servings,
            prepTimeMinutes: draft.prepTimeMinutes,
            cookTimeMinutes: draft.cookTimeMinutes,
            tags: draft.tags,
            ingredients: [],
            steps: [],
            userVote: nil
        )
    }

    func updateRecipe(householdID: String, recipeID: String, draft: RecipeDraft) async throws -> FullRecipe {
        throw TestOnboardingError.failed
    }

    func archiveRecipe(householdID: String, recipeID: String) async throws -> FullRecipe {
        throw TestOnboardingError.failed
    }

    func repairIngredientCategories(householdID: String) async throws -> RecipeCategoryRepairResult {
        RecipeCategoryRepairResult(recipesUpdated: 0, ingredientsUpdated: 0)
    }

    func fillInRecipe(title: String, existingIngredients: [DraftIngredient], existingSteps: [String]) async throws -> RecipeDraft {
        if shouldFailFillIn { throw TestOnboardingError.failed }
        return RecipeDraft(title: "Filled: \(title)")
    }

    func importRecipeFromURL(_ urlString: String) async throws -> RecipeDraft {
        RecipeDraft(title: "Imported", sourceUrl: urlString)
    }

    func importRecipeFromText(_ text: String, sourceURL: String?) async throws -> RecipeDraft {
        RecipeDraft(title: "Imported from text", sourceUrl: sourceURL)
    }
}

private final class FakeOnboardingHouseholdAPIClient: HouseholdStoreAPIClient {
    var shouldFailSaveProfile = false
    private(set) var saveProfileCallCount = 0

    func bootstrapHousehold() async throws -> Household {
        Household(id: TestOnboardingHousehold.id, name: "Household", role: .owner)
    }

    func listHouseholds() async throws -> [Household] {
        [Household(id: TestOnboardingHousehold.id, name: "Household", role: .owner)]
    }

    func listMembers(householdID: String) async throws -> [HouseholdMember] { [] }

    func getProfile(householdID: String) async throws -> HouseholdProfile? { nil }

    func saveProfile(
        householdID: String,
        adults: Int,
        children: Int,
        priorities: [HouseholdPriority],
        avoidIngredients: [String],
        selectedDays: [HouseholdDaySelection]
    ) async throws -> HouseholdProfile {
        saveProfileCallCount += 1
        if shouldFailSaveProfile { throw TestOnboardingError.failed }
        return HouseholdProfile(
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
        InviteLanding(householdName: "Household", status: "pending")
    }

    func acceptInvite(token: String) async throws -> String { TestOnboardingHousehold.id }

    func renameHousehold(householdID: String, name: String) async throws {}

    func removeMember(householdID: String, userID: String) async throws {}

    func deleteHousehold(householdID: String) async throws {}
}

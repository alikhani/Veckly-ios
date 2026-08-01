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
        #expect(recipeAPI.fillInTitles == ["Taco Tuesday"])
        #expect(recipeAPI.createdDraftTitles == ["Filled: Taco Tuesday"])
        #expect(householdAPI.saveProfileCallCount == 1)
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

    @Test func skippedGoToDishCreatesNoRecipeButStillSavesProfile() async {
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
        #expect(recipeAPI.fillInTitles.isEmpty)
        #expect(recipeAPI.createdDraftTitles.isEmpty)
        #expect(householdStore.profile != nil)
        #expect(householdAPI.saveProfileCallCount == 1)
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

    @Test func daySelectionPayloadSurvivesEncodeDecodeRoundTripWithAllFieldsSet() throws {
        // Regression coverage: the fake API client in this file only echoes
        // back its arguments, so it can't catch the real client's mapping
        // from `HouseholdDaySelection` to the generated OpenAPI payload
        // silently dropping a field (or the whole day, via a nil rawValue
        // lookup). This exercises the actual mapping function plus a real
        // JSONEncoder/JSONDecoder round trip through the generated type.
        let original = HouseholdDaySelection(
            day: .friday,
            servingsOverride: 6,
            occasion: .guests,
            effortLevel: .busy,
            leftoversIntent: true,
            lateEvening: true,
            cookingTolerance: .relaxed
        )

        let payload = try #require(VecklyAPIClient.daySelectionPayload(for: original))
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(VecklyAPIClient.DaySelectionPayload.self, from: data)

        #expect(decoded == payload)
        #expect(decoded.day == .friday)
        #expect(decoded.servingsOverride == 6)
        #expect(decoded.occasion == .guests)
        #expect(decoded.effortLevel == .busy)
        #expect(decoded.leftoversIntent == true)
        #expect(decoded.lateEvening == true)
        #expect(decoded.cookingTolerance == .relaxed)
    }

    @Test func upsertProfilePayloadSurvivesEncodeDecodeRoundTripWithEveryFieldSet() throws {
        // Regression coverage for the outer payload, not just a single day:
        // catches `saveProfile` silently dropping `selectedDays` (or any
        // other field) from the `UpsertHouseholdProfile` initializer, which
        // the day-only round-trip test above cannot see.
        let selectedDays = [
            HouseholdDaySelection(day: .monday),
            HouseholdDaySelection(
                day: .friday,
                servingsOverride: 6,
                occasion: .guests,
                effortLevel: .busy,
                leftoversIntent: true,
                lateEvening: true,
                cookingTolerance: .relaxed
            ),
        ]

        let payload = VecklyAPIClient.upsertProfilePayload(
            adults: 2,
            children: 1,
            priorities: [.quick, .childFriendly],
            avoidIngredients: ["nuts", ""],
            selectedDays: selectedDays
        )
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(Components.Schemas.UpsertHouseholdProfile.self, from: data)

        #expect(decoded == payload)
        #expect(decoded.adults == 2)
        #expect(decoded.children == 1)
        #expect(decoded.priorities == [.quick, .child_hyphen_friendly])
        #expect(decoded.avoidIngredients == ["nuts"])
        #expect(decoded.selectedDays.map(\.day) == [.monday, .friday])
        #expect(decoded.selectedDays.last?.servingsOverride == 6)
        #expect(decoded.selectedDays.last?.occasion == .guests)
        #expect(decoded.selectedDays.last?.cookingTolerance == .relaxed)
    }

    @Test func daySelectionPayloadOmitsFalseFlagsAndDefaultsMatchingTheOnboardingSendPath() throws {
        // Onboarding sends plain day identity (see the day-signals test
        // above) — this pins that the default `HouseholdDaySelection` still
        // maps and round-trips cleanly, with the boolean flags sent as `nil`
        // rather than `false` (matching `saveProfile`'s `? true : nil`).
        let original = HouseholdDaySelection(day: .monday)

        let payload = try #require(VecklyAPIClient.daySelectionPayload(for: original))
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(VecklyAPIClient.DaySelectionPayload.self, from: data)

        #expect(decoded == payload)
        #expect(decoded.day == .monday)
        #expect(decoded.servingsOverride == nil)
        #expect(decoded.leftoversIntent == nil)
        #expect(decoded.lateEvening == nil)
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
    private(set) var fillInTitles: [String] = []
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

    func fillInRecipe(householdID: String, title: String, existingIngredients: [DraftIngredient], existingSteps: [String]) async throws -> RecipeDraft {
        fillInTitles.append(title)
        if shouldFailFillIn { throw TestOnboardingError.failed }
        return RecipeDraft(title: "Filled: \(title)")
    }

    func importRecipeFromURL(householdID: String, _ urlString: String) async throws -> RecipeDraft {
        RecipeDraft(title: "Imported", sourceUrl: urlString)
    }

    func importRecipeFromText(householdID: String, _ text: String, sourceURL: String?) async throws -> RecipeDraft {
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

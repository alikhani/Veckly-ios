import Foundation

enum OnboardingCompletionOutcome: Equatable {
    case success(goToDishSaved: Bool)
    case goToDishSaveFailed
    case profileSaveFailed
}

/// Extracted from `OnboardingFlowView` so the go-to-dish/profile ordering and
/// failure handling can be covered by tests without driving the SwiftUI view.
///
/// Order matters: the go-to-dish recipe is created *before* the household
/// profile is saved. `RootView`'s onboarding cover is driven purely by
/// profile presence (`AppModel.needsOnboarding`), so saving the profile first
/// would dismiss onboarding — and tear down this screen — before a
/// go-to-dish failure could ever be shown.
@MainActor
enum OnboardingCompletion {
    static func run(
        recipeStore: RecipeStore,
        householdStore: HouseholdStore,
        householdID: String,
        adults: Int,
        children: Int,
        priorities: [HouseholdPriority],
        avoidIngredients: [String],
        selectedDays: [HouseholdDaySelection],
        goToDishTitle: String
    ) async -> OnboardingCompletionOutcome {
        let trimmedTitle = goToDishTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        var goToDishSaved = false

        if !trimmedTitle.isEmpty {
            var draft = RecipeDraft(title: trimmedTitle)
            if let filled = try? await recipeStore.fillIn(draft: draft) {
                draft = filled
            }
            guard (try? await recipeStore.createRecipe(householdID: householdID, draft: draft)) != nil else {
                return .goToDishSaveFailed
            }
            goToDishSaved = true
        }

        do {
            try await householdStore.saveProfile(
                householdID: householdID,
                adults: adults,
                children: children,
                priorities: priorities,
                avoidIngredients: avoidIngredients,
                selectedDays: selectedDays
            )
        } catch {
            return .profileSaveFailed
        }

        return .success(goToDishSaved: goToDishSaved)
    }
}

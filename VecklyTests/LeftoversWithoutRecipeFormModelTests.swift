import Testing
@testable import Veckly

@MainActor
struct LeftoversWithoutRecipeFormModelTests {
    @Test func defaultPortionsUsesHouseholdSize() {
        let profile = HouseholdProfile(
            householdId: "household-1",
            adults: 2,
            children: 3,
            priorities: [],
            avoidIngredients: [],
            selectedDays: []
        )

        #expect(LeftoversWithoutRecipeFormModel.defaultPortions(profile: profile) == 5)
    }

    @Test func defaultPortionsClampsMissingOrEmptyHouseholdToOne() {
        let emptyProfile = HouseholdProfile(
            householdId: "household-1",
            adults: 0,
            children: 0,
            priorities: [],
            avoidIngredients: [],
            selectedDays: []
        )

        #expect(LeftoversWithoutRecipeFormModel.defaultPortions(profile: nil) == 1)
        #expect(LeftoversWithoutRecipeFormModel.defaultPortions(profile: emptyProfile) == 1)
    }

    @Test func successfulSavePassesSelectedPortionsAndReportsSuccess() async {
        let model = LeftoversWithoutRecipeFormModel(totalPortions: 4)
        model.totalPortions = 7
        var submittedPortions: Int?

        let succeeded = await model.save { portions in
            submittedPortions = portions
        }

        #expect(succeeded)
        #expect(submittedPortions == 7)
        #expect(!model.saveFailed)
        #expect(!model.isSaving)
    }

    @Test func failedSaveReportsFailureAndAllowsRetry() async {
        let model = LeftoversWithoutRecipeFormModel(totalPortions: 4)
        var attemptCount = 0

        let firstSucceeded = await model.save { _ in
            attemptCount += 1
            throw TestSubmissionError.failed
        }
        let retrySucceeded = await model.save { _ in
            attemptCount += 1
        }

        #expect(!firstSucceeded)
        #expect(retrySucceeded)
        #expect(attemptCount == 2)
        #expect(!model.saveFailed)
    }

    @Test func saveIgnoresASecondSubmissionWhileTheFirstIsRunning() async {
        let model = LeftoversWithoutRecipeFormModel(totalPortions: 4)
        var operationCount = 0
        let firstSave = Task {
            await model.save { _ in
                operationCount += 1
                try await Task.sleep(for: .milliseconds(50))
            }
        }
        while !model.isSaving {
            await Task.yield()
        }

        let secondSucceeded = await model.save { _ in
            operationCount += 1
        }
        let firstSucceeded = await firstSave.value

        #expect(firstSucceeded)
        #expect(!secondSucceeded)
        #expect(operationCount == 1)
    }
}

private enum TestSubmissionError: Error {
    case failed
}

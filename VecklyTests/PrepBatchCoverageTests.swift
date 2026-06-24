import Foundation
import Testing
@testable import Veckly

struct PrepBatchCoverageTests {
    private let pasta = FullRecipe(
        id: "11111111-1111-1111-1111-111111111111",
        title: "Pasta",
        description: "",
        servings: 4,
        prepTimeMinutes: nil,
        cookTimeMinutes: nil,
        tags: [],
        ingredients: [],
        steps: [],
        userVote: nil
    )

    private func batch(id: String = "batch-1", recipeId: String?, cookDate: String, assignedDates: [String]) -> PrepBatch {
        PrepBatch(
            id: id,
            householdId: "11111111-1111-1111-1111-111111111111",
            recipeId: recipeId,
            cookDate: cookDate,
            totalPortions: 8,
            assignments: assignedDates.map {
                PrepBatchAssignment(id: "\(id)-\($0)", batchId: id, date: $0, mealType: .dinner)
            }
        )
    }

    @Test func returnsCoverageWhenADateMatchesAnAssignment() {
        let result = prepBatchCoverage(
            for: "2026-06-09",
            batches: [batch(recipeId: pasta.id, cookDate: "2026-06-08", assignedDates: ["2026-06-08", "2026-06-09"])],
            recipes: [pasta]
        )

        #expect(result == PrepBatchCoverage(batchID: "batch-1", recipeTitle: "Pasta", cookDate: "2026-06-08", totalPortions: 8, mealType: .dinner))
    }

    @Test func returnsNilWhenNoAssignmentMatchesTheDate() {
        let result = prepBatchCoverage(
            for: "2026-06-10",
            batches: [batch(recipeId: pasta.id, cookDate: "2026-06-08", assignedDates: ["2026-06-08", "2026-06-09"])],
            recipes: [pasta]
        )

        #expect(result == nil)
    }

    @Test func picksTheMatchingBatchAmongSeveral() {
        let other = batch(id: "batch-2", recipeId: nil, cookDate: "2026-06-01", assignedDates: ["2026-06-02"])
        let target = batch(id: "batch-1", recipeId: pasta.id, cookDate: "2026-06-08", assignedDates: ["2026-06-09"])

        let result = prepBatchCoverage(for: "2026-06-09", batches: [other, target], recipes: [pasta])

        #expect(result?.recipeTitle == "Pasta")
        #expect(result?.cookDate == "2026-06-08")
        #expect(result?.batchID == "batch-1")
        #expect(result?.mealType == .dinner)
    }

    @Test func fallsBackToGenericTitleWhenRecipeIsNotFound() {
        let result = prepBatchCoverage(
            for: "2026-06-09",
            batches: [batch(recipeId: "unknown-recipe-id", cookDate: "2026-06-08", assignedDates: ["2026-06-09"])],
            recipes: [pasta]
        )

        #expect(result?.recipeTitle == L10n.string("prep.fallbackTitle"))
    }
}

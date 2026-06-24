import Foundation
import Observation

@MainActor
@Observable
final class PrepBatchStore {
    private let apiClient: any PrepBatchStoreAPIClient

    private(set) var batches: [PrepBatch] = []
    private(set) var lastFetchedAt: Date?
    private(set) var isLoading = false
    private(set) var householdID: String?
    private(set) var weekStartDate: String?
    var errorMessage: String?
    /// Set by `create`/`removeAssignment` on failure — surfaced via the week
    /// view's banner so actions triggered from a dismissed sheet (no alert of
    /// their own) don't fail silently. Distinct from `errorMessage`, which is
    /// `load`'s own (older) error surface.
    private(set) var mutationError: String?

    func clearMutationError() { mutationError = nil }

    init(apiClient: any PrepBatchStoreAPIClient) {
        self.apiClient = apiClient
    }

    func load(householdID: String, weekStartDate: String) async {
        let scopeChanged = self.householdID != householdID || self.weekStartDate != weekStartDate
        if scopeChanged {
            batches = []
            lastFetchedAt = nil
            errorMessage = nil
            self.householdID = householdID
            self.weekStartDate = weekStartDate
        }

        guard lastFetchedAt == nil || Date().timeIntervalSince(lastFetchedAt!) > 300 else { return }
        isLoading = batches.isEmpty
        errorMessage = nil
        defer { isLoading = false }
        let to = endDate(from: weekStartDate)
        do {
            batches = try await apiClient.listPrepBatches(householdID: householdID, from: weekStartDate, to: to)
            lastFetchedAt = Date()
            self.householdID = householdID
            self.weekStartDate = weekStartDate
        } catch {
            errorMessage = L10n.string("error.prep.load")
        }
    }

    func create(
        householdID: String,
        weekStartDate: String,
        recipeId: String?,
        cookDate: String,
        totalPortions: Int,
        assignments: [(date: String, mealType: MealType)]
    ) async throws {
        mutationError = nil
        do {
            let batch = try await apiClient.createPrepBatch(
                householdID: householdID,
                recipeId: recipeId,
                cookDate: cookDate,
                totalPortions: totalPortions,
                assignments: assignments
            )
            batches.append(batch)
            batches.sort { $0.cookDate < $1.cookDate }
        } catch {
            mutationError = L10n.string("error.prep.create")
            throw error
        }
    }

    func delete(householdID: String, batchID: String) async throws {
        try await apiClient.deletePrepBatch(householdID: householdID, batchID: batchID)
        batches.removeAll { $0.id == batchID }
    }

    /// Un-assigns a single covered day from a batch — the batch and its other
    /// assignments are untouched. Mirrors the backend's own cleanup: if that
    /// was the last assignment, the whole batch is gone (no covered days left
    /// means no UI surface left to find it from).
    func removeAssignment(householdID: String, batchID: String, date: String, mealType: MealType) async throws {
        mutationError = nil
        do {
            try await apiClient.removeAssignment(householdID: householdID, batchID: batchID, date: date, mealType: mealType)
        } catch {
            mutationError = L10n.string("error.prep.removeAssignment")
            throw error
        }
        guard let index = batches.firstIndex(where: { $0.id == batchID }) else { return }
        let remainingAssignments = batches[index].assignments.filter { !($0.date == date && $0.mealType == mealType) }
        if remainingAssignments.isEmpty {
            batches.remove(at: index)
        } else {
            batches[index] = PrepBatch(
                id: batches[index].id,
                householdId: batches[index].householdId,
                recipeId: batches[index].recipeId,
                cookDate: batches[index].cookDate,
                totalPortions: batches[index].totalPortions,
                assignments: remainingAssignments
            )
        }
    }

    func reset() {
        batches = []
        errorMessage = nil
        mutationError = nil
        isLoading = false
        lastFetchedAt = nil
        householdID = nil
        weekStartDate = nil
    }

    private func endDate(from start: String) -> String {
        guard let date = weekDateFormatter.date(from: start) else { return start }
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(secondsFromGMT: 0)!
        let end = utcCal.date(byAdding: .day, value: 6, to: date) ?? date
        return weekDateFormatter.string(from: end)
    }
}

protocol PrepBatchStoreAPIClient {
    func listPrepBatches(householdID: String, from: String, to: String) async throws -> [PrepBatch]
    func createPrepBatch(
        householdID: String,
        recipeId: String?,
        cookDate: String,
        totalPortions: Int,
        assignments: [(date: String, mealType: MealType)]
    ) async throws -> PrepBatch
    func deletePrepBatch(householdID: String, batchID: String) async throws
    func removeAssignment(householdID: String, batchID: String, date: String, mealType: MealType) async throws
}

extension VecklyAPIClient: PrepBatchStoreAPIClient {}

private let weekDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.locale = Locale(identifier: "en_US_POSIX")
    return f
}()

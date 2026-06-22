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
        let batch = try await apiClient.createPrepBatch(
            householdID: householdID,
            recipeId: recipeId,
            cookDate: cookDate,
            totalPortions: totalPortions,
            assignments: assignments
        )
        batches.append(batch)
        batches.sort { $0.cookDate < $1.cookDate }
    }

    func delete(householdID: String, batchID: String) async throws {
        try await apiClient.deletePrepBatch(householdID: householdID, batchID: batchID)
        batches.removeAll { $0.id == batchID }
    }

    func reset() {
        batches = []
        errorMessage = nil
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
}

extension VecklyAPIClient: PrepBatchStoreAPIClient {}

private let weekDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.locale = Locale(identifier: "en_US_POSIX")
    return f
}()

import Foundation
import Observation

@MainActor
@Observable
final class PrepBatchStore {
    private let apiClient: VecklyAPIClient

    private(set) var batches: [PrepBatch] = []
    private(set) var lastFetchedAt: Date?
    private(set) var isLoading = false
    var errorMessage: String?

    init(apiClient: VecklyAPIClient) {
        self.apiClient = apiClient
    }

    func load(householdID: String, weekStartDate: String) async {
        guard lastFetchedAt == nil || Date().timeIntervalSince(lastFetchedAt!) > 300 else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let to = endDate(from: weekStartDate)
        do {
            batches = try await apiClient.listPrepBatches(householdID: householdID, from: weekStartDate, to: to)
            lastFetchedAt = Date()
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
    }

    private func endDate(from start: String) -> String {
        guard let date = weekDateFormatter.date(from: start) else { return start }
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(secondsFromGMT: 0)!
        let end = utcCal.date(byAdding: .day, value: 6, to: date) ?? date
        return weekDateFormatter.string(from: end)
    }
}

private let weekDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.locale = Locale(identifier: "en_US_POSIX")
    return f
}()

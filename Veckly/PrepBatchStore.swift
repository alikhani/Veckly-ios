import Foundation
import Observation

@MainActor
@Observable
final class PrepBatchStore {
    private let apiClient: any PrepBatchStoreAPIClient
    private let cacheStore: any PrepBatchStoreCachePersisting

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

    init(apiClient: any PrepBatchStoreAPIClient, cacheStore: any PrepBatchStoreCachePersisting = PrepBatchStoreDiskCache()) {
        self.apiClient = apiClient
        self.cacheStore = cacheStore
    }

    func load(householdID: String, weekStartDate: String) async {
        let scopeChanged = self.householdID != householdID || self.weekStartDate != weekStartDate
        if scopeChanged {
            batches = []
            lastFetchedAt = nil
            errorMessage = nil
            self.householdID = householdID
            self.weekStartDate = weekStartDate
            restorePersistedCacheIfNeeded(householdID: householdID, weekStartDate: weekStartDate)
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
            persistCurrentCache(householdID: householdID, weekStartDate: weekStartDate)
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
            persistCurrentCache(householdID: householdID, weekStartDate: weekStartDate)
        } catch {
            mutationError = L10n.string("error.prep.create")
            throw error
        }
    }

    func delete(householdID: String, batchID: String) async throws {
        try await apiClient.deletePrepBatch(householdID: householdID, batchID: batchID)
        batches.removeAll { $0.id == batchID }
        persistCurrentCacheIfScoped(householdID: householdID)
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
                customRecipeId: batches[index].customRecipeId,
                cookDate: batches[index].cookDate,
                totalPortions: batches[index].totalPortions,
                assignments: remainingAssignments
            )
        }
        persistCurrentCacheIfScoped(householdID: householdID)
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
        WeekCalendar.addDays(to: start, offset: 6)
    }

    private func restorePersistedCacheIfNeeded(householdID: String, weekStartDate: String) {
        guard batches.isEmpty else { return }
        guard let cached = cacheStore.loadBatches(householdID: householdID, weekStartDate: weekStartDate) else { return }
        batches = cached.batches.map(\.prepBatch)
        lastFetchedAt = cached.fetchedAt
    }

    private func persistCurrentCache(householdID: String, weekStartDate: String) {
        guard !batches.isEmpty else {
            cacheStore.deleteBatches(householdID: householdID, weekStartDate: weekStartDate)
            return
        }
        cacheStore.saveBatches(
            PersistedPrepBatchCache(
                householdID: householdID,
                weekStartDate: weekStartDate,
                fetchedAt: lastFetchedAt ?? Date(),
                batches: batches.map(PersistedPrepBatch.init)
            )
        )
    }

    /// Used by mutations that don't have a `weekStartDate` parameter of their
    /// own — re-persists under the store's currently loaded scope, if any.
    private func persistCurrentCacheIfScoped(householdID: String) {
        guard let weekStartDate, self.householdID == householdID else { return }
        persistCurrentCache(householdID: householdID, weekStartDate: weekStartDate)
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

struct PersistedPrepBatchCache: Codable {
    let householdID: String
    let weekStartDate: String
    let fetchedAt: Date
    let batches: [PersistedPrepBatch]
}

struct PersistedPrepBatch: Codable {
    let id: String
    let householdId: String
    let recipeId: String?
    let customRecipeId: String?
    let cookDate: String
    let totalPortions: Int
    let assignments: [PersistedPrepBatchAssignment]
}

struct PersistedPrepBatchAssignment: Codable {
    let id: String
    let batchId: String
    let date: String
    let mealType: MealType
}

extension PersistedPrepBatch {
    init(_ batch: PrepBatch) {
        self.init(
            id: batch.id,
            householdId: batch.householdId,
            recipeId: batch.recipeId,
            customRecipeId: batch.customRecipeId,
            cookDate: batch.cookDate,
            totalPortions: batch.totalPortions,
            assignments: batch.assignments.map(PersistedPrepBatchAssignment.init)
        )
    }

    var prepBatch: PrepBatch {
        PrepBatch(
            id: id,
            householdId: householdId,
            recipeId: recipeId,
            customRecipeId: customRecipeId,
            cookDate: cookDate,
            totalPortions: totalPortions,
            assignments: assignments.map(\.prepBatchAssignment)
        )
    }
}

extension PersistedPrepBatchAssignment {
    init(_ assignment: PrepBatchAssignment) {
        self.init(id: assignment.id, batchId: assignment.batchId, date: assignment.date, mealType: assignment.mealType)
    }

    var prepBatchAssignment: PrepBatchAssignment {
        PrepBatchAssignment(id: id, batchId: batchId, date: date, mealType: mealType)
    }
}

protocol PrepBatchStoreCachePersisting {
    func loadBatches(householdID: String, weekStartDate: String) -> PersistedPrepBatchCache?
    func saveBatches(_ cache: PersistedPrepBatchCache)
    func deleteBatches(householdID: String, weekStartDate: String)
}

struct PrepBatchStoreDiskCache: PrepBatchStoreCachePersisting {
    private let fileManager: FileManager = .default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func loadBatches(householdID: String, weekStartDate: String) -> PersistedPrepBatchCache? {
        let url = cacheURL(householdID: householdID, weekStartDate: weekStartDate)
        guard let data = try? Data(contentsOf: url),
              let cache = try? decoder.decode(PersistedPrepBatchCache.self, from: data) else {
            return nil
        }
        return cache.householdID == householdID && cache.weekStartDate == weekStartDate ? cache : nil
    }

    func saveBatches(_ cache: PersistedPrepBatchCache) {
        let url = cacheURL(householdID: cache.householdID, weekStartDate: cache.weekStartDate)
        let directory = url.deletingLastPathComponent()
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? encoder.encode(cache) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    func deleteBatches(householdID: String, weekStartDate: String) {
        try? fileManager.removeItem(at: cacheURL(householdID: householdID, weekStartDate: weekStartDate))
    }

    private func cacheURL(householdID: String, weekStartDate: String) -> URL {
        let baseDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return baseDirectory
            .appendingPathComponent("Veckly", isDirectory: true)
            .appendingPathComponent("prep-batches-\(householdID)-\(weekStartDate).json")
    }
}

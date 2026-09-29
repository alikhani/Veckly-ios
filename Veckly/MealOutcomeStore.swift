import Foundation
import Observation

protocol MealOutcomeStoreAPIClient {
    func mealOutcomes(householdID: String, weekStartDate: String) async throws -> [MealOutcomeRecord]
    func upsertMealOutcome(_ draft: MealOutcomeDraft) async throws -> MealOutcomeRecord
}

protocol MealOutcomePendingPersisting {
    func load() -> [MealOutcomeDraft]
    func save(_ drafts: [MealOutcomeDraft])
    func delete()
}

struct MealOutcomePendingDiskStore: MealOutcomePendingPersisting {
    private let cache = JSONDiskCache<[MealOutcomeDraft]>(fileName: "pending-meal-outcomes.json")

    func load() -> [MealOutcomeDraft] { cache.load() ?? [] }
    func save(_ drafts: [MealOutcomeDraft]) { cache.save(drafts) }
    func delete() { cache.delete() }
}

@MainActor
@Observable
final class MealOutcomeStore {
    private let apiClient: any MealOutcomeStoreAPIClient
    private let pendingStore: any MealOutcomePendingPersisting
    private let retryDelayNanoseconds: UInt64
    private let didSyncOutcome: (String) -> Void

    private var outcomesByDate: [String: MealOutcomeRecord] = [:]
    private var pendingByID: [String: MealOutcomeDraft]
    private var activeHouseholdID: String?
    private var activeWeekStartDate: String?
    private var retryTask: Task<Void, Never>?
    private var isFlushing = false

    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var mutationError: String?

    init(
        apiClient: any MealOutcomeStoreAPIClient,
        pendingStore: any MealOutcomePendingPersisting = MealOutcomePendingDiskStore(),
        retryDelayNanoseconds: UInt64 = 2_000_000_000,
        didSyncOutcome: @escaping (String) -> Void = { _ in }
    ) {
        self.apiClient = apiClient
        self.pendingStore = pendingStore
        self.retryDelayNanoseconds = retryDelayNanoseconds
        self.didSyncOutcome = didSyncOutcome
        let pending = pendingStore.load().map { $0.normalized() }
        self.pendingByID = Dictionary(uniqueKeysWithValues: pending.map { ($0.id, $0) })
    }

    var hasPendingSync: Bool {
        pendingForActiveContext.contains { _ in true }
    }

    func outcome(for date: String) -> MealOutcomeRecord? {
        outcomesByDate[date]
    }

    func isPending(date: String) -> Bool {
        guard let activeHouseholdID, let activeWeekStartDate else { return false }
        return pendingByID[pendingID(householdID: activeHouseholdID, weekStartDate: activeWeekStartDate, date: date)] != nil
    }

    func load(householdID: String, weekStartDate: String) async {
        let contextChanged = !isActive(householdID: householdID, weekStartDate: weekStartDate)
        activeHouseholdID = householdID
        activeWeekStartDate = weekStartDate
        if contextChanged {
            outcomesByDate = [:]
            mutationError = nil
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let records = try await apiClient.mealOutcomes(householdID: householdID, weekStartDate: weekStartDate)
            guard isActive(householdID: householdID, weekStartDate: weekStartDate) else { return }
            outcomesByDate = Dictionary(uniqueKeysWithValues: records.map { ($0.date, $0) })
        } catch is CancellationError {
            return
        } catch let urlError as URLError where urlError.code == .cancelled {
            return
        } catch {
            guard isActive(householdID: householdID, weekStartDate: weekStartDate) else { return }
            errorMessage = L10n.string("error.mealOutcome.load")
        }

        reapplyPendingForActiveContext()
        await flushPendingForActiveContext()
    }

    func retryLoad() async {
        guard let activeHouseholdID, let activeWeekStartDate else { return }
        await load(householdID: activeHouseholdID, weekStartDate: activeWeekStartDate)
    }

    func setOutcome(_ draft: MealOutcomeDraft) async {
        let draft = draft.normalized()
        guard isActive(householdID: draft.householdID, weekStartDate: draft.weekStartDate) else { return }

        outcomesByDate[draft.date] = MealOutcomeRecord(draft: draft)
        pendingByID[draft.id] = draft
        persistPending()
        mutationError = nil
        await flushPendingForActiveContext()
    }

    func retryPending() async {
        mutationError = nil
        await flushPendingForActiveContext()
    }

    func clearMutationError() {
        mutationError = nil
    }

    /// Clears the currently displayed household/week while preserving pending
    /// writes for their original context. They are retried the next time that
    /// household and week become active.
    func reset() {
        retryTask?.cancel()
        retryTask = nil
        outcomesByDate = [:]
        activeHouseholdID = nil
        activeWeekStartDate = nil
        isLoading = false
        errorMessage = nil
        mutationError = nil
    }

    /// Used only when the authenticated account is removed from this device.
    func discardAllPending() {
        reset()
        pendingByID = [:]
        pendingStore.delete()
    }

    private var pendingForActiveContext: [MealOutcomeDraft] {
        guard let activeHouseholdID, let activeWeekStartDate else { return [] }
        return pendingByID.values
            .filter { $0.householdID == activeHouseholdID && $0.weekStartDate == activeWeekStartDate }
            .sorted { $0.date < $1.date }
    }

    private func flushPendingForActiveContext() async {
        guard !isFlushing else { return }
        isFlushing = true
        retryTask?.cancel()
        retryTask = nil
        defer { isFlushing = false }

        while let outgoing = pendingForActiveContext.first {
            do {
                let saved = try await apiClient.upsertMealOutcome(outgoing)
                let current = pendingByID[outgoing.id]
                if current == outgoing {
                    pendingByID[outgoing.id] = nil
                    persistPending()
                    if isActive(householdID: outgoing.householdID, weekStartDate: outgoing.weekStartDate) {
                        outcomesByDate[outgoing.date] = saved
                    }
                    didSyncOutcome(outgoing.householdID)
                }
                mutationError = nil
            } catch is CancellationError {
                return
            } catch let urlError as URLError where urlError.code == .cancelled {
                return
            } catch {
                mutationError = L10n.string("error.mealOutcome.pendingSync")
                scheduleRetry()
                return
            }
        }
    }

    private func scheduleRetry() {
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: retryDelayNanoseconds)
            guard !Task.isCancelled else { return }
            await self.flushPendingForActiveContext()
        }
    }

    private func reapplyPendingForActiveContext() {
        for draft in pendingForActiveContext {
            outcomesByDate[draft.date] = MealOutcomeRecord(draft: draft)
        }
    }

    private func persistPending() {
        pendingStore.save(pendingByID.values.sorted { $0.id < $1.id })
    }

    private func pendingID(householdID: String, weekStartDate: String, date: String) -> String {
        "\(householdID):\(weekStartDate):\(date)"
    }

    private func isActive(householdID: String, weekStartDate: String) -> Bool {
        activeHouseholdID == householdID && activeWeekStartDate == weekStartDate
    }
}

extension VecklyAPIClient: MealOutcomeStoreAPIClient {}

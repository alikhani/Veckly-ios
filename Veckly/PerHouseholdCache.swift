import Foundation

/// Load-once-per-household, in-memory, session-scoped — de-dupes concurrent
/// callers into a single attempt. Captures the pattern `FamilyCookbookStore`
/// and `RecipeRecommendationStore` each hand-rolled independently (a
/// `[String: Value]` cache plus a `Set<String>` of in-flight household IDs).
/// No TTL: matches both stores' existing "quiet, session-long" behavior — a
/// fresh app launch (or an explicit `reset()`) is what clears it.
///
/// Domain-specific "not ready to load yet" preconditions (e.g. "don't even
/// attempt this until there are candidate recipes") belong in the caller,
/// checked *before* calling `loadIfNeeded` — this type only knows about
/// caching and de-duping, nothing about why a load might not make sense yet.
@MainActor
final class PerHouseholdCache<Value> {
    private var valuesByHousehold: [String: Value] = [:]
    private var loadingHouseholdIDs: Set<String> = []

    func value(for householdID: String) -> Value? {
        valuesByHousehold[householdID]
    }

    func loadIfNeeded(householdID: String, load: () async -> Value) async {
        guard valuesByHousehold[householdID] == nil, !loadingHouseholdIDs.contains(householdID) else { return }
        loadingHouseholdIDs.insert(householdID)
        defer { loadingHouseholdIDs.remove(householdID) }
        valuesByHousehold[householdID] = await load()
    }

    func reset() {
        valuesByHousehold = [:]
        loadingHouseholdIDs = []
    }
}

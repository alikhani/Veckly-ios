import Foundation
import Testing
@testable import Veckly

@MainActor
struct PerHouseholdCacheTests {
    @Test func loadIfNeededPopulatesTheCache() async {
        let cache = PerHouseholdCache<Int>()

        await cache.loadIfNeeded(householdID: "household-1") { 42 }

        #expect(cache.value(for: "household-1") == 42)
    }

    @Test func onlyCallsLoadOnceForTheSameHousehold() async {
        let cache = PerHouseholdCache<Int>()
        var callCount = 0

        await cache.loadIfNeeded(householdID: "household-1") { callCount += 1; return callCount }
        await cache.loadIfNeeded(householdID: "household-1") { callCount += 1; return callCount }

        #expect(callCount == 1)
        #expect(cache.value(for: "household-1") == 1)
    }

    @Test func differentHouseholdsAreCachedIndependently() async {
        let cache = PerHouseholdCache<String>()

        await cache.loadIfNeeded(householdID: "household-1") { "first" }
        await cache.loadIfNeeded(householdID: "household-2") { "second" }

        #expect(cache.value(for: "household-1") == "first")
        #expect(cache.value(for: "household-2") == "second")
    }

    @Test func concurrentCallersForTheSameHouseholdShareOneLoad() async {
        let cache = PerHouseholdCache<Int>()
        let counter = Counter()

        async let first: Void = cache.loadIfNeeded(householdID: "household-1") {
            await counter.increment()
        }
        async let second: Void = cache.loadIfNeeded(householdID: "household-1") {
            await counter.increment()
        }
        _ = await (first, second)

        let callCount = await counter.count
        #expect(callCount == 1)
    }

    @Test func resetAllowsAFreshLoad() async {
        let cache = PerHouseholdCache<Int>()

        await cache.loadIfNeeded(householdID: "household-1") { 1 }
        cache.reset()
        await cache.loadIfNeeded(householdID: "household-1") { 2 }

        #expect(cache.value(for: "household-1") == 2)
    }
}

private actor Counter {
    private(set) var count = 0
    func increment() -> Int {
        count += 1
        return count
    }
}

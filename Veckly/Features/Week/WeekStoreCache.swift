import Foundation

protocol WeekStoreCachePersisting {
    func loadWeek(scope: CacheScope, weekStartDate: String) -> WeekSummary?
    func saveWeek(_ summary: WeekSummary, scope: CacheScope)
    func removeWeek(scope: CacheScope, weekStartDate: String)
    func deleteAll()
}

/// Disk persistence for the latest `WeekSummary` of each household's recent
/// weeks (see `HouseholdWeekDiskCache`). A summary that doesn't belong to the
/// week and household it is filed under is a miss.
struct WeekStoreDiskCache: WeekStoreCachePersisting {
    private let cache: HouseholdWeekDiskCache<WeekSummary>

    init(baseDirectory: URL? = nil) {
        cache = HouseholdWeekDiskCache(folder: "week-summaries", baseDirectory: baseDirectory)
    }

    func loadWeek(scope: CacheScope, weekStartDate: String) -> WeekSummary? {
        guard let summary = cache.load(scope: scope, weekStartDate: weekStartDate),
              summary.weekStartDate == weekStartDate,
              summary.household.id == scope.householdID else { return nil }
        return summary
    }

    func saveWeek(_ summary: WeekSummary, scope: CacheScope) {
        cache.save(summary, scope: scope, weekStartDate: summary.weekStartDate)
    }

    func removeWeek(scope: CacheScope, weekStartDate: String) {
        cache.remove(scope: scope, weekStartDate: weekStartDate)
    }

    func deleteAll() {
        cache.deleteAll()
    }
}

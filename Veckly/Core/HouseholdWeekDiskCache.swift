import Foundation

/// Who a cached payload belongs to. A payload is only ever read back by the
/// same user, household and app language that wrote it: the summaries hold
/// household data and localized text (categories, explanations), so anything
/// else is a miss.
struct CacheScope: Equatable, Codable {
    let userID: String
    let householdID: String
    let language: String

    /// The language the app currently renders its own strings in — the same
    /// choice that decides the `Accept-Language` the API localizes with.
    static var currentLanguage: String {
        let locale = AppLocalePreference.effectiveLocale
        return locale.language.languageCode?.identifier ?? locale.identifier
    }
}

private struct HouseholdWeekCacheFile<Payload: Codable>: Codable {
    var schemaVersion: Int
    var userID: String
    var householdID: String
    var language: String
    var weeks: [String: Payload]
}

/// One file per household holding the payloads of its most recent weeks
/// (`weekStartDate` -> payload), built on `JSONDiskCache`. Everything that
/// fails validation or decoding is a cache miss, never an error.
struct HouseholdWeekDiskCache<Payload: Codable> {
    static var maxWeeks: Int { 4 }

    private let folder: String
    private let schemaVersion: Int
    private let baseDirectory: URL?

    init(folder: String, schemaVersion: Int = 1, baseDirectory: URL? = nil) {
        self.folder = folder
        self.schemaVersion = schemaVersion
        self.baseDirectory = baseDirectory
    }

    func load(scope: CacheScope, weekStartDate: String) -> Payload? {
        guard let file = validFile(for: scope) else { return nil }
        return file.weeks[weekStartDate]
    }

    func save(_ payload: Payload, scope: CacheScope, weekStartDate: String) {
        var file = validFile(for: scope) ?? emptyFile(for: scope)
        file.weeks[weekStartDate] = payload
        // `weekStartDate` is an ISO date, so lexicographic order is date order.
        for stale in file.weeks.keys.sorted().dropLast(Self.maxWeeks) {
            file.weeks.removeValue(forKey: stale)
        }
        diskCache(for: scope.householdID).save(file)
    }

    func remove(scope: CacheScope, weekStartDate: String) {
        guard var file = validFile(for: scope), file.weeks[weekStartDate] != nil else { return }
        file.weeks.removeValue(forKey: weekStartDate)
        diskCache(for: scope.householdID).save(file)
    }

    func deleteAll() {
        JSONDiskCache<HouseholdWeekCacheFile<Payload>>.deleteFolder(folder, baseDirectory: baseDirectory)
    }

    private func validFile(for scope: CacheScope) -> HouseholdWeekCacheFile<Payload>? {
        guard let file = diskCache(for: scope.householdID).load(),
              file.schemaVersion == schemaVersion,
              file.userID == scope.userID,
              file.householdID == scope.householdID,
              file.language == scope.language else { return nil }
        return file
    }

    private func emptyFile(for scope: CacheScope) -> HouseholdWeekCacheFile<Payload> {
        HouseholdWeekCacheFile(
            schemaVersion: schemaVersion,
            userID: scope.userID,
            householdID: scope.householdID,
            language: scope.language,
            weeks: [:]
        )
    }

    private func diskCache(for householdID: String) -> JSONDiskCache<HouseholdWeekCacheFile<Payload>> {
        JSONDiskCache(fileName: "\(folder)/\(householdID).json", baseDirectory: baseDirectory)
    }
}

import Foundation
import Testing
@testable import Veckly

struct HouseholdWeekDiskCacheTests {
    private struct Payload: Codable, Equatable {
        let label: String
    }

    private let scope = CacheScope(userID: "user-1", householdID: "household-1", language: "sv")

    private func makeCache(_ directory: URL, schemaVersion: Int = 1) -> HouseholdWeekDiskCache<Payload> {
        HouseholdWeekDiskCache(folder: "test-weeks", schemaVersion: schemaVersion, baseDirectory: directory)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("HouseholdWeekDiskCacheTests-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func savedWeekCanBeLoadedForTheSameScope() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = makeCache(directory)

        cache.save(Payload(label: "a"), scope: scope, weekStartDate: "2026-10-05")

        #expect(cache.load(scope: scope, weekStartDate: "2026-10-05") == Payload(label: "a"))
        #expect(cache.load(scope: scope, weekStartDate: "2026-10-12") == nil)
    }

    @Test func aDifferentUserMisses() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = makeCache(directory)
        cache.save(Payload(label: "a"), scope: scope, weekStartDate: "2026-10-05")

        let other = CacheScope(userID: "user-2", householdID: scope.householdID, language: scope.language)
        #expect(cache.load(scope: other, weekStartDate: "2026-10-05") == nil)
    }

    @Test func aDifferentLanguageMisses() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = makeCache(directory)
        cache.save(Payload(label: "a"), scope: scope, weekStartDate: "2026-10-05")

        let english = CacheScope(userID: scope.userID, householdID: scope.householdID, language: "en")
        #expect(cache.load(scope: english, weekStartDate: "2026-10-05") == nil)
    }

    @Test func aDifferentHouseholdMisses() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = makeCache(directory)
        cache.save(Payload(label: "a"), scope: scope, weekStartDate: "2026-10-05")

        let other = CacheScope(userID: scope.userID, householdID: "household-2", language: scope.language)
        #expect(cache.load(scope: other, weekStartDate: "2026-10-05") == nil)
    }

    @Test func aDifferentSchemaVersionMisses() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        makeCache(directory, schemaVersion: 1).save(Payload(label: "a"), scope: scope, weekStartDate: "2026-10-05")

        #expect(makeCache(directory, schemaVersion: 2).load(scope: scope, weekStartDate: "2026-10-05") == nil)
    }

    @Test func savingForAnotherScopeReplacesTheFileInsteadOfMixingUsers() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = makeCache(directory)
        cache.save(Payload(label: "old user"), scope: scope, weekStartDate: "2026-10-05")
        let other = CacheScope(userID: "user-2", householdID: scope.householdID, language: scope.language)

        cache.save(Payload(label: "new user"), scope: other, weekStartDate: "2026-10-12")

        #expect(cache.load(scope: scope, weekStartDate: "2026-10-05") == nil)
        #expect(cache.load(scope: other, weekStartDate: "2026-10-05") == nil)
        #expect(cache.load(scope: other, weekStartDate: "2026-10-12") == Payload(label: "new user"))
    }

    @Test func onlyTheFourNewestWeeksAreKept() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = makeCache(directory)
        let weeks = ["2026-09-21", "2026-09-28", "2026-10-05", "2026-10-12", "2026-10-19"]

        for week in weeks {
            cache.save(Payload(label: week), scope: scope, weekStartDate: week)
        }

        #expect(cache.load(scope: scope, weekStartDate: "2026-09-21") == nil)
        for week in weeks.dropFirst() {
            #expect(cache.load(scope: scope, weekStartDate: week) == Payload(label: week))
        }
    }

    @Test func removeDropsOnlyThatWeek() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = makeCache(directory)
        cache.save(Payload(label: "a"), scope: scope, weekStartDate: "2026-10-05")
        cache.save(Payload(label: "b"), scope: scope, weekStartDate: "2026-10-12")

        cache.remove(scope: scope, weekStartDate: "2026-10-05")

        #expect(cache.load(scope: scope, weekStartDate: "2026-10-05") == nil)
        #expect(cache.load(scope: scope, weekStartDate: "2026-10-12") == Payload(label: "b"))
    }

    @Test func deleteAllRemovesEveryHouseholdsFile() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = makeCache(directory)
        let other = CacheScope(userID: scope.userID, householdID: "household-2", language: scope.language)
        cache.save(Payload(label: "a"), scope: scope, weekStartDate: "2026-10-05")
        cache.save(Payload(label: "b"), scope: other, weekStartDate: "2026-10-05")

        cache.deleteAll()

        #expect(cache.load(scope: scope, weekStartDate: "2026-10-05") == nil)
        #expect(cache.load(scope: other, weekStartDate: "2026-10-05") == nil)
    }

    @Test func corruptOrUndecodableFilesMiss() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = makeCache(directory)
        let folder = directory.appendingPathComponent("Veckly/test-weeks", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("\(scope.householdID).json")

        try Data("not json".utf8).write(to: file)
        #expect(cache.load(scope: scope, weekStartDate: "2026-10-05") == nil)

        // Valid envelope, payload of the wrong shape.
        let json = #"{"schemaVersion":1,"userID":"user-1","householdID":"household-1","language":"sv","weeks":{"2026-10-05":{"unexpected":true}}}"#
        try Data(json.utf8).write(to: file)
        #expect(cache.load(scope: scope, weekStartDate: "2026-10-05") == nil)
    }
}

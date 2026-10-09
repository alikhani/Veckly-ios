import Foundation
import Testing
@testable import Veckly

struct JSONDiskCacheTests {
    private struct CachedValue: Codable, Equatable {
        let name: String
        let count: Int
    }

    @Test func savedValueCanBeLoaded() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = JSONDiskCache<CachedValue>(fileName: "value.json", baseDirectory: directory)
        let value = CachedValue(name: "Dinner", count: 3)

        cache.save(value)

        #expect(cache.load() == value)
    }

    @Test func missingOrCorruptDataLoadsAsNil() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = JSONDiskCache<CachedValue>(fileName: "value.json", baseDirectory: directory)

        #expect(cache.load() == nil)

        let cacheDirectory = directory.appendingPathComponent("Veckly", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: cacheDirectory.appendingPathComponent("value.json"))

        #expect(cache.load() == nil)
    }

    @Test func deleteRemovesSavedValue() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = JSONDiskCache<CachedValue>(fileName: "value.json", baseDirectory: directory)
        cache.save(CachedValue(name: "Dinner", count: 3))

        cache.delete()

        #expect(cache.load() == nil)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("JSONDiskCacheTests-\(UUID().uuidString)", isDirectory: true)
    }

    /// Sign-out wipes every cache file in one go. Callers cannot list them: prep
    /// batches are cached per household *and week*, recipes per household.
    @Test func deleteAllRemovesEveryCacheFileIncludingSubfolders() {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("DeleteAll-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let files = ["recipes-h1.json", "recipes-h2.json", "prep-batches-h1-2026-10-05.json", "week-summaries/h1.json"]
        for name in files { JSONDiskCache<[String]>(fileName: name, baseDirectory: base).save(["x"]) }
        let outside = base.appendingPathComponent("not-ours.json")
        try? Data("keep".utf8).write(to: outside)

        JSONDiskCache<[String]>.deleteAll(baseDirectory: base)

        for name in files { #expect(JSONDiskCache<[String]>(fileName: name, baseDirectory: base).load() == nil) }
        #expect(FileManager.default.fileExists(atPath: outside.path))
    }

    @Test func deleteAllIsHarmlessWhenThereIsNothingToDelete() {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("DeleteAllEmpty-\(UUID().uuidString)", isDirectory: true)
        JSONDiskCache<[String]>.deleteAll(baseDirectory: base)
        #expect(!FileManager.default.fileExists(atPath: base.appendingPathComponent("Veckly").path))
    }
}

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
}

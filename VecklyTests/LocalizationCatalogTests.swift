import Foundation
import Testing

struct LocalizationCatalogTests {
    @Test func catalogHasNoStaleEntriesAndContainsEveryManifestKey() throws {
        let projectDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let catalogURL = projectDirectory.appendingPathComponent("Veckly/Localizable.xcstrings")
        let manifestURL = projectDirectory.appendingPathComponent("Veckly/LocalizationExtractionManifest.swift")

        let catalogData = try Data(contentsOf: catalogURL)
        let catalog = try #require(JSONSerialization.jsonObject(with: catalogData) as? [String: Any])
        let strings = try #require(catalog["strings"] as? [String: [String: Any]])
        let staleKeys = strings.compactMap { key, value in
            value["extractionState"] as? String == "stale" ? key : nil
        }

        let manifest = try String(contentsOf: manifestURL, encoding: .utf8)
        let pattern = #"String\(localized: "([^"]+)"\)"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(manifest.startIndex..., in: manifest)
        let manifestKeys = regex.matches(in: manifest, range: range).compactMap { match in
            Range(match.range(at: 1), in: manifest).map { String(manifest[$0]) }
        }

        #expect(staleKeys.isEmpty)
        #expect(Set(manifestKeys).count == manifestKeys.count)
        #expect(Set(manifestKeys).subtracting(strings.keys).isEmpty)
    }
}

import Foundation
import Testing

struct LocalizationCatalogTests {
    @Test func catalogHasNoStaleEntriesAndContainsEveryManifestKey() throws {
        let projectDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let catalogURL = projectDirectory.appendingPathComponent("Veckly/Localizable.xcstrings")

        let catalogData = try Data(contentsOf: catalogURL)
        let catalog = try #require(JSONSerialization.jsonObject(with: catalogData) as? [String: Any])
        let strings = try #require(catalog["strings"] as? [String: [String: Any]])
        let staleKeys = strings.compactMap { key, value in
            value["extractionState"] as? String == "stale" ? key : nil
        }

        let manifestKeys = try Self.manifestKeys(projectDirectory: projectDirectory)

        #expect(staleKeys.isEmpty)
        #expect(Set(manifestKeys).count == manifestKeys.count)
        #expect(Set(manifestKeys).subtracting(strings.keys).isEmpty)
    }

    @Test func everyDynamicLocalizationCallSiteIsRegisteredInTheManifest() throws {
        // The catalog's own `stale` flag only protects keys the manifest
        // already knows about. A new `L10n.string("...")`/`L10n.format("...")`
        // call site elsewhere in the app is invisible to Xcode's static
        // extractor and would silently go stale (and be eligible for
        // deletion in a future cleanup) unless it's also added here. This
        // test closes that gap by scanning production source directly,
        // rather than trusting the manifest to already be complete.
        let projectDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceDirectory = projectDirectory.appendingPathComponent("Veckly")
        let manifestFileName = "LocalizationExtractionManifest.swift"

        let manifestKeys = Set(try Self.manifestKeys(projectDirectory: projectDirectory))

        let callPattern = try NSRegularExpression(pattern: #"L10n\.(?:string|format)\("([^"]+)"#)
        var unregistered: [String: [String]] = [:]

        let enumerator = FileManager.default.enumerator(
            at: sourceDirectory,
            includingPropertiesForKeys: nil
        )
        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "swift", fileURL.lastPathComponent != manifestFileName else { continue }
            guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let range = NSRange(contents.startIndex..., in: contents)
            for match in callPattern.matches(in: contents, range: range) {
                guard let keyRange = Range(match.range(at: 1), in: contents) else { continue }
                let key = String(contents[keyRange])
                guard !manifestKeys.contains(key) else { continue }
                unregistered[key, default: []].append(fileURL.lastPathComponent)
            }
        }

        #expect(unregistered.isEmpty, "Dynamic L10n keys missing from \(manifestFileName): \(unregistered)")
    }

    private static func manifestKeys(projectDirectory: URL) throws -> [String] {
        let manifestURL = projectDirectory.appendingPathComponent("Veckly/LocalizationExtractionManifest.swift")
        let manifest = try String(contentsOf: manifestURL, encoding: .utf8)
        let pattern = #"String\(localized: "([^"]+)"\)"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(manifest.startIndex..., in: manifest)
        return regex.matches(in: manifest, range: range).compactMap { match in
            Range(match.range(at: 1), in: manifest).map { String(manifest[$0]) }
        }
    }
}

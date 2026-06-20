import Foundation
import Testing
@testable import Veckly

@MainActor
struct AppLanguageTests {
    @Test func missingPreferenceUsesSystem() {
        let defaults = makeDefaults()
        let store = AppLanguageStore(userDefaults: defaults)

        #expect(store.selection == .system)
    }

    @Test func selectionPersistsAcrossStoreInstances() {
        let defaults = makeDefaults()
        let first = AppLanguageStore(userDefaults: defaults)

        first.select(.swedish)
        let restored = AppLanguageStore(userDefaults: defaults)

        #expect(restored.selection == .swedish)
    }

    @Test func corruptPreferenceFallsBackToSystem() {
        let defaults = makeDefaults()
        defaults.set("unknown", forKey: AppLocalePreference.storageKey)

        #expect(AppLanguageStore(userDefaults: defaults).selection == .system)
    }

    @Test func explicitLanguagesProduceStableHeaders() {
        #expect(AppLocalePreference.acceptLanguageHeader(for: .swedish) == "sv, en;q=0.8")
        #expect(AppLocalePreference.acceptLanguageHeader(for: .english) == "en")
    }

    @Test func systemHeaderUsesPreferredLanguageAndEnglishFallback() {
        let header = AppLocalePreference.acceptLanguageHeader(
            for: .system,
            preferredLanguages: ["sv_SE"]
        )

        #expect(header == "sv-SE, sv;q=0.9, en;q=0.8")
    }

    @Test func effectiveLocaleMatchesExplicitSelection() {
        #expect(AppLocalePreference.effectiveLocale(for: .swedish).language.languageCode?.identifier == "sv")
        #expect(AppLocalePreference.effectiveLocale(for: .english).language.languageCode?.identifier == "en")
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "AppLanguageTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

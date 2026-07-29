import Foundation
import Testing
@testable import Veckly

@MainActor
struct AppLanguageTests {
    @Test func dayActionCopyExplainsSkipClearAndLockInEnglish() {
        let locale = Locale(identifier: "en")

        #expect(localized("meal.clear", locale: locale) == "Remove dish")
        #expect(localized("meal.removeExplanation", locale: locale) == "The dish will be removed from this day, which stays open for another dinner.")
        #expect(localized("meal.skipExplanation", locale: locale) == "No dinner will be planned for this day. If a dish is already assigned, it will be kept and return when you plan the day again.")
        #expect(localized("week.lock.explainMessage", locale: locale) == "The dish stays on this day when you replan or regenerate the week.")
    }

    @Test func dayActionCopyExplainsSkipClearAndLockInSwedish() {
        let locale = Locale(identifier: "sv")

        #expect(localized("meal.clear", locale: locale) == "Ta bort rätten")
        #expect(localized("meal.removeExplanation", locale: locale) == "Rätten tas bort från den här dagen, som lämnas öppen för en annan middag.")
        #expect(localized("meal.skipExplanation", locale: locale) == "Ingen middag planeras den här dagen. Om en rätt redan är vald behålls den och kommer tillbaka när du planerar dagen igen.")
        #expect(localized("week.lock.explainMessage", locale: locale) == "Rätten ligger kvar den här dagen när du planerar om eller genererar om veckan.")
    }

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

    private func localized(_ key: String, locale: Locale) -> String {
        let language = locale.language.languageCode?.identifier ?? "en"
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return key
        }
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }
}

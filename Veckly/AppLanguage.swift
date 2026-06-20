import Foundation
import Observation

enum AppLanguage: String, CaseIterable, Codable, Identifiable {
    case system
    case swedish
    case english

    var id: Self { self }
}

@MainActor
@Observable
final class AppLanguageStore {
    private let userDefaults: UserDefaults
    private(set) var selection: AppLanguage

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        selection = AppLocalePreference.storedLanguage(in: userDefaults)
    }

    var effectiveLocale: Locale {
        AppLocalePreference.effectiveLocale(for: selection)
    }

    func select(_ language: AppLanguage) {
        selection = language
        userDefaults.set(language.rawValue, forKey: AppLocalePreference.storageKey)
    }
}

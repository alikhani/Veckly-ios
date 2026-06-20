import Foundation

enum L10n {
    static func string(_ key: String) -> String {
        String(
            localized: String.LocalizationValue(key),
            locale: AppLocalePreference.effectiveLocale
        )
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: AppLocalePreference.effectiveLocale, arguments: arguments)
    }
}

enum AppLocalePreference {
    static let storageKey = "veckly.app-language"

    static var selectedLanguage: AppLanguage {
        storedLanguage(in: .standard)
    }

    static var effectiveLocale: Locale {
        effectiveLocale(for: selectedLanguage)
    }

    static var acceptLanguageHeader: String {
        acceptLanguageHeader(for: selectedLanguage)
    }

    static func storedLanguage(in userDefaults: UserDefaults) -> AppLanguage {
        guard let rawValue = userDefaults.string(forKey: storageKey),
              let language = AppLanguage(rawValue: rawValue) else {
            return .system
        }
        return language
    }

    static func effectiveLocale(
        for language: AppLanguage,
        systemLocale: Locale = .autoupdatingCurrent
    ) -> Locale {
        switch language {
        case .system: systemLocale
        case .swedish: Locale(identifier: "sv")
        case .english: Locale(identifier: "en")
        }
    }

    static func acceptLanguageHeader(
        for language: AppLanguage,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> String {
        switch language {
        case .swedish:
            return "sv, en;q=0.8"
        case .english:
            return "en"
        case .system:
            return systemAcceptLanguageHeader(preferredLanguages: preferredLanguages)
        }
    }

    private static func systemAcceptLanguageHeader(preferredLanguages: [String]) -> String {
        let preferred = preferredLanguages
        guard let first = preferred.first, !first.isEmpty else { return "en" }

        let normalizedFirst = normalized(first)
        let primaryLanguage = Locale(identifier: first).language.languageCode?.identifier
            ?? normalizedFirst.split(separator: "-").first.map(String.init)

        var parts = [normalizedFirst]
        if let primaryLanguage, primaryLanguage != normalizedFirst {
            parts.append("\(primaryLanguage);q=0.9")
        }
        if primaryLanguage != "en" {
            parts.append("en;q=0.8")
        }
        return parts.joined(separator: ", ")
    }

    private static func normalized(_ identifier: String) -> String {
        identifier.replacingOccurrences(of: "_", with: "-")
    }
}

import Foundation

enum L10n {
    static func string(_ key: String) -> String {
        String(localized: String.LocalizationValue(key))
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: .current, arguments: arguments)
    }
}

enum AppLocalePreference {
    static var acceptLanguageHeader: String {
        let preferred = Locale.preferredLanguages
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

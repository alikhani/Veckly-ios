import Foundation

/// Scales a recipe ingredient amount string by a ratio and formats it for display.
///
/// Amounts are stored as plain strings (e.g. "400", "1.5", "½"). We parse what
/// we can; anything that doesn't parse as a number is returned unchanged so the
/// display degrades gracefully rather than silently showing a wrong value.
enum IngredientScaler {

    /// Returns a scale factor for a household relative to a recipe's base servings.
    ///
    /// Returns 1.0 (no scaling) when the household size is 0 or the base servings
    /// are 0, which guards against division-by-zero and the profile-not-loaded case.
    static func scaleFactor(householdSize: Int, recipeServings: Int) -> Double {
        guard householdSize > 0, recipeServings > 0 else { return 1.0 }
        return Double(householdSize) / Double(recipeServings)
    }

    /// Scales an ingredient amount string by `factor` and returns a display string.
    ///
    /// - If `factor` is effectively 1.0, the original string is returned verbatim
    ///   so we never mangle already-correct values.
    /// - If `unit` is "st" (Swedish for pieces), the result is rounded to the
    ///   nearest integer.
    /// - Otherwise, the result is formatted to one decimal place, dropping the
    ///   trailing ".0" when the result is a whole number.
    /// - If `amount` is nil or doesn't parse as a number, `amount` is returned as-is.
    static func scale(amount: String?, unit: String?, by factor: Double) -> String? {
        guard let raw = amount else { return nil }

        // No-op for identity scale — avoids mutating values when no profile is loaded.
        let isIdentity = abs(factor - 1.0) < 1e-9
        if isIdentity { return raw }

        guard let parsed = parseDouble(raw) else { return raw }

        let scaled = parsed * factor
        let isPieces = unit?.trimmingCharacters(in: .whitespaces).lowercased() == "st"
        return isPieces ? "\(Int((scaled).rounded()))" : formatDecimal(scaled)
    }

    // MARK: - Private helpers

    private static func parseDouble(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if let value = Double(trimmed) { return value }
        // Handle simple fractions like "1/2"
        let parts = trimmed.split(separator: "/", maxSplits: 1)
        if parts.count == 2, let num = Double(parts[0]), let den = Double(parts[1]), den != 0 {
            return num / den
        }
        return nil
    }

    private static func formatDecimal(_ value: Double) -> String {
        // One decimal place; drop the ".0" suffix when the value is whole.
        let rounded = (value * 10).rounded() / 10
        if rounded.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(rounded))"
        }
        return String(format: "%.1f", rounded)
    }
}

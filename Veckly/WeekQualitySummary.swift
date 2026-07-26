import Foundation

struct WeekQualitySummary: Equatable {
    struct Insight: Equatable, Identifiable {
        enum Kind: Equatable {
            case openDays(count: Int)
            case quickRhythm(count: Int)
            case heavyWeek(count: Int)
            case prepFriendly(count: Int)
            case lowConfidence(count: Int)
            case goodVariation(count: Int)
            case looksReasonable
        }

        let kind: Kind
        let icon: String

        var id: String {
            switch kind {
            case .openDays: "open-days"
            case .quickRhythm: "quick-rhythm"
            case .heavyWeek: "heavy-week"
            case .prepFriendly: "prep-friendly"
            case .lowConfidence: "low-confidence"
            case .goodVariation: "good-variation"
            case .looksReasonable: "looks-reasonable"
            }
        }
    }

    let insights: [Insight]

    static func make(days: [WeekDayRowViewModel], prepCoveredDates: Set<String> = []) -> WeekQualitySummary {
        let activeDays = days.filter { !$0.isSkipped }
        let plannedDays = activeDays.filter { $0.recipe != nil || prepCoveredDates.contains($0.date) }
        guard !plannedDays.isEmpty else { return WeekQualitySummary(insights: []) }

        let openDayCount = activeDays.filter { $0.recipe == nil && !prepCoveredDates.contains($0.date) }.count
        let quickDinnerCount = plannedDays.filter { day in
            day.recipe.map(RecipeTimingSignals.isQuick) == true
        }.count
        let heavyDinnerCount = plannedDays.filter { day in
            guard let recipe = day.recipe, let total = RecipeTimingSignals.totalMinutes(for: recipe) else { return false }
            return total >= 45
        }.count
        let prepFriendlyCount = plannedDays.filter { day in
            prepCoveredDates.contains(day.date) || day.recipe.map(RecipeTimingSignals.isPrepFriendly) == true
        }.count
        let lowConfidenceCount = plannedDays.filter { $0.confidence == .low }.count
        let varietyCount = Set(plannedDays.compactMap { $0.recipe }.flatMap(variationSignals(for:))).count

        var insights: [Insight] = []
        if openDayCount > 0 {
            insights.append(Insight(kind: .openDays(count: openDayCount), icon: "calendar.badge.exclamationmark"))
        }
        if lowConfidenceCount > 0 {
            insights.append(Insight(kind: .lowConfidence(count: lowConfidenceCount), icon: "arrow.triangle.2.circlepath"))
        }
        if quickDinnerCount >= 3 {
            insights.append(Insight(kind: .quickRhythm(count: quickDinnerCount), icon: "clock"))
        } else if heavyDinnerCount >= 3 {
            insights.append(Insight(kind: .heavyWeek(count: heavyDinnerCount), icon: "flame"))
        }
        if prepFriendlyCount > 0 {
            insights.append(Insight(kind: .prepFriendly(count: prepFriendlyCount), icon: "takeoutbag.and.cup.and.straw"))
        }
        if varietyCount >= 4 {
            insights.append(Insight(kind: .goodVariation(count: varietyCount), icon: "sparkles"))
        }
        if insights.isEmpty, plannedDays.count >= 3 {
            insights.append(Insight(kind: .looksReasonable, icon: "checkmark.seal"))
        }

        return WeekQualitySummary(insights: Array(insights.prefix(3)))
    }

    private static func variationSignals(for recipe: WeekSummaryRecipe) -> [String] {
        let ignoredTags: Set<String> = [
            "quick", "weekday", "weeknight", "family", "favorite", "favourite",
            "easy", "simple", "leftover", "leftovers", "rester", "meal prep", "batch"
        ]
        return recipe.tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && !ignoredTags.contains($0) }
    }
}

enum SessionEndInviteNudgeEligibility {
    static func shouldShow(
        activeHousehold: Household?,
        detailsHouseholdID: String?,
        memberCount: Int
    ) -> Bool {
        guard let activeHousehold, activeHousehold.role == .owner else { return false }
        return detailsHouseholdID == activeHousehold.id && memberCount <= 1
    }
}

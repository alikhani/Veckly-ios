import Foundation

/// The household's planning days are the source of truth for whether a week
/// is "done" (beslut 1) — a day outside `selectedDays` is optional and never
/// counts as a gap. This type centralizes that rule so `WeekTabView`'s
/// open-day counts, quality card, session-end beat, and generate/regenerate
/// CTA all agree on what "relevant" means, instead of each re-deriving it
/// (or, previously, ignoring it via `WeekStore.hasEmptyDays`).
struct WeekPlanningScope: Equatable {
    /// Defensive fallback when the household has no profile yet (e.g. still
    /// onboarding) — matches the server-side default used when seeding a new
    /// household's profile.
    static let defaultWeekdays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]

    let selectedWeekdays: Set<Weekday>

    init(selectedWeekdays: Set<Weekday>) {
        self.selectedWeekdays = selectedWeekdays.isEmpty ? Self.defaultWeekdays : selectedWeekdays
    }

    /// Builds the scope straight from a household's profile. `nil` (profile
    /// not loaded yet) or an empty `selectedDays` both fall back to Mon–Fri.
    init(profile: HouseholdProfile?) {
        self.init(selectedWeekdays: Set((profile?.selectedDays ?? []).map(\.day)))
    }

    /// Whether Saturday and/or Sunday are themselves planning days — when
    /// true, weekend days are regular rows with no collapsed section
    /// (beslut 8).
    var includesWeekend: Bool {
        selectedWeekdays.contains(.saturday) || selectedWeekdays.contains(.sunday)
    }

    func isRelevant(_ day: WeekDayRowViewModel) -> Bool {
        selectedWeekdays.contains(day.weekday)
    }

    /// The subset of `days` that count toward planning completeness — used
    /// as the input to `WeekQualitySummary.make` so its (unchanged) internal
    /// logic only ever sees scope-relevant days.
    func relevantDays(in days: [WeekDayRowViewModel]) -> [WeekDayRowViewModel] {
        days.filter(isRelevant)
    }

    /// A relevant, non-past day is "open" unless it has a recipe, is skipped,
    /// or is covered by prep/leftovers (`coveredDates`, keyed by `day.date`).
    /// Past days are settled history: they must neither keep the current week
    /// incomplete nor be included when the user asks to plan the rest.
    func openDays(in days: [WeekDayRowViewModel], coveredDates: Set<String>) -> [WeekDayRowViewModel] {
        relevantDays(in: days).filter { day in
            !day.isPast && !day.isSkipped && day.recipe == nil && !coveredDates.contains(day.date)
        }
    }

    func isComplete(days: [WeekDayRowViewModel], coveredDates: Set<String>) -> Bool {
        openDays(in: days, coveredDates: coveredDates).isEmpty
    }
}

import Foundation
import Testing
@testable import Veckly

struct WeekBriefDraftTests {
    @Test func pantrySuggestionsOnlyIncludeAvailableItemsAndStayCompact() {
        let suggestions = PantryPlanningItem.suggestions(from: [
            "pantry:brown-rice:g": 250,
            "produce:tomato:": 3,
            "dairy:milk:ml": 0,
            "protein:beans:g": 100,
            "frozen:peas:g": 200,
            "pantry:pasta:g": 500,
            "produce:onion:": 2,
        ])

        #expect(suggestions.count == 5)
        #expect(!suggestions.contains { $0.id == "dairy:milk:ml" })
        #expect(suggestions.contains(PantryPlanningItem(id: "pantry:brown-rice:g", label: "Brown Rice")))
        #expect(suggestions.map(\.label) == suggestions.map(\.label).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }

    @Test func startsFromHouseholdRhythmAndOnlyActivatesSavedDifferences() {
        let profile = HouseholdProfile(
            householdId: "h1",
            adults: 2,
            children: 1,
            priorities: [],
            avoidIngredients: [],
            selectedDays: [
                HouseholdDaySelection(day: .monday, effortLevel: .busy),
                HouseholdDaySelection(day: .tuesday)
            ]
        )
        let overrides = [
            WeekContextOverride(
                date: "2026-10-06",
                servingsOverride: nil,
                occasion: .guests,
                effortLevel: nil,
                leftoversIntent: true,
                lateEvening: nil,
                cookingTolerance: nil
            )
        ]

        let draft = WeekBriefDraft(rows: rows(), profile: profile, overrides: overrides)

        #expect(draft.days.map(\.weekday) == [.monday, .tuesday])
        #expect(draft.days[0].normal.effortLevel == .busy)
        #expect(!draft.days[0].signals.contains(.busy))
        #expect(draft.days[1].signals == [.guests, .extra])
        #expect(draft.summaryLines.count == 1)
        #expect(draft.summaryLines[0].hasPrefix("Tuesday: "))
    }

    @Test func buildsOverrideAndPreservesExistingServingCount() {
        let existing = WeekContextOverride(
            date: "2026-10-05",
            servingsOverride: 6,
            occasion: nil,
            effortLevel: nil,
            leftoversIntent: nil,
            lateEvening: nil,
            cookingTolerance: nil
        )
        var draft = WeekBriefDraft(rows: rows(), profile: profile(), overrides: [existing])

        draft.toggle(.busy, on: "2026-10-05")
        draft.toggle(.late, on: "2026-10-05")

        let result = draft.override(for: draft.days[0])
        #expect(result?.servingsOverride == 6)
        #expect(result?.effortLevel == .busy)
        #expect(result?.lateEvening == true)
        #expect(draft.datesToClear.isEmpty)
    }

    @Test func removingLastSignalClearsSavedOverride() {
        let existing = WeekContextOverride(
            date: "2026-10-05",
            servingsOverride: nil,
            occasion: nil,
            effortLevel: .busy,
            leftoversIntent: nil,
            lateEvening: nil,
            cookingTolerance: nil
        )
        var draft = WeekBriefDraft(rows: rows(), profile: profile(), overrides: [existing])

        draft.toggle(.busy, on: "2026-10-05")

        #expect(draft.override(for: draft.days[0]) == nil)
        #expect(draft.datesToClear == ["2026-10-05"])
    }

    @Test func awayIsAnExplicitSkipChangeRatherThanAContextOverride() {
        var draft = WeekBriefDraft(rows: rows(), profile: profile(), overrides: [])

        draft.toggle(.away, on: "2026-10-06")

        #expect(draft.awayChanges.count == 1)
        #expect(draft.awayChanges.first?.day == .tuesday)
        #expect(draft.awayChanges.first?.skipped == true)
        #expect(draft.override(for: draft.days[1]) == nil)
    }

    private func profile() -> HouseholdProfile {
        HouseholdProfile(
            householdId: "h1",
            adults: 2,
            children: 1,
            priorities: [],
            avoidIngredients: [],
            selectedDays: [.monday, .tuesday].map { HouseholdDaySelection(day: $0) }
        )
    }

    private func rows() -> [WeekDayRowViewModel] {
        [
            row(.monday, date: "2026-10-05", label: "Monday"),
            row(.tuesday, date: "2026-10-06", label: "Tuesday"),
            row(.wednesday, date: "2026-10-07", label: "Wednesday")
        ]
    }

    private func row(_ weekday: Weekday, date: String, label: String) -> WeekDayRowViewModel {
        WeekDayRowViewModel(
            id: date,
            weekday: weekday,
            weekdayLabel: label,
            date: date,
            dateLabel: date,
            mealTitle: "",
            detail: "",
            isToday: false,
            isEmpty: true,
            recipe: nil
        )
    }
}

@MainActor
struct WeekBriefStoreTests {
    @Test func savesOverridesAndAwayBeforeGenerationCanContinue() async {
        let api = FakeWeekBriefAPIClient()
        let store = WeekBriefStore(apiClient: api)
        let rows = [
            WeekDayRowViewModel(
                id: "monday",
                weekday: .monday,
                weekdayLabel: "Monday",
                date: "2026-10-05",
                dateLabel: "5 Oct",
                mealTitle: "",
                detail: "",
                isToday: false,
                isEmpty: true,
                recipe: nil
            )
        ]
        let profile = HouseholdProfile(
            householdId: "h1",
            adults: 2,
            children: 0,
            priorities: [],
            avoidIngredients: [],
            selectedDays: [HouseholdDaySelection(day: .monday)]
        )
        await store.load(householdID: "h1", weekStartDate: "2026-10-05", rows: rows, profile: profile)
        store.updateDraft {
            $0.toggle(.busy, on: "2026-10-05")
            $0.toggle(.away, on: "2026-10-05")
        }

        let saved = await store.save(householdID: "h1", weekStartDate: "2026-10-05", userID: "u1")

        #expect(saved)
        #expect(api.savedOverrides.first?.effortLevel == .busy)
        #expect(api.events == ["skip:monday"])
    }

    @Test func unchangedBriefDoesNotCreateDuplicateEvents() async {
        let existing = WeekContextOverride(
            date: "2026-10-05",
            servingsOverride: nil,
            occasion: nil,
            effortLevel: .busy,
            leftoversIntent: nil,
            lateEvening: nil,
            cookingTolerance: nil
        )
        let api = FakeWeekBriefAPIClient()
        api.overrides = [existing]
        let store = WeekBriefStore(apiClient: api)
        let row = WeekDayRowViewModel(
            id: "monday",
            weekday: .monday,
            weekdayLabel: "Monday",
            date: "2026-10-05",
            dateLabel: "5 Oct",
            mealTitle: "",
            detail: "",
            isToday: false,
            isEmpty: true,
            recipe: nil
        )
        let profile = HouseholdProfile(
            householdId: "h1",
            adults: 2,
            children: 0,
            priorities: [],
            avoidIngredients: [],
            selectedDays: [HouseholdDaySelection(day: .monday)]
        )
        await store.load(householdID: "h1", weekStartDate: "2026-10-05", rows: [row], profile: profile)

        let saved = await store.save(householdID: "h1", weekStartDate: "2026-10-05", userID: "u1")

        #expect(saved)
        #expect(api.savedOverrides.isEmpty)
        #expect(api.clearedDates.isEmpty)
        #expect(api.events.isEmpty)
    }
}

private final class FakeWeekBriefAPIClient: WeekBriefAPIClient {
    var overrides: [WeekContextOverride] = []
    var savedOverrides: [WeekContextOverride] = []
    var clearedDates: [String] = []
    var events: [String] = []

    func weekContextOverrides(householdID: String, weekStartDate: String) async throws -> [WeekContextOverride] {
        overrides
    }

    func upsertWeekContextOverride(householdID: String, weekStartDate: String, override: WeekContextOverride) async throws {
        savedOverrides.append(override)
    }

    func clearWeekContextOverride(householdID: String, weekStartDate: String, date: String) async throws {
        clearedDates.append(date)
    }

    func appendWeekPlanEvent(householdID: String, weekStartDate: String, userID: String, event: WeekPlanEventInput) async throws {
        switch event {
        case .daySkipped(let day): events.append("skip:\(day.rawValue)")
        case .dayUnskipped(let day): events.append("unskip:\(day.rawValue)")
        default: events.append("other")
        }
    }
}

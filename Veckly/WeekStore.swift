import Foundation
import Observation

@MainActor
@Observable
final class WeekStore {
    private let apiClient: VecklyAPIClient

    private(set) var weekStartDate: String = WeekCalendar.currentWeekStartDate()
    private(set) var summary: WeekSummary?
    private(set) var dayRows: [WeekDayRowViewModel] = []
    private(set) var today: WeekDayRowViewModel?
    private(set) var lockedDays: Set<Weekday> = []
    private(set) var skippedDays: Set<Weekday> = []
    private(set) var mealFeedback: [String: MealVote] = [:]
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    init(apiClient: VecklyAPIClient) {
        self.apiClient = apiClient
    }

    func loadCurrentWeek(household: Household) async {
        isLoading = true
        errorMessage = nil
        weekStartDate = WeekCalendar.currentWeekStartDate()
        defer { isLoading = false }

        do {
            let summary = try await apiClient.weekSummary(householdID: household.id, weekStartDate: weekStartDate)
            self.summary = summary
            let mapped = WeekViewModelMapper.map(summary: summary, today: Date())
            dayRows = mapped.days
            today = mapped.today
            mealFeedback = (try? await apiClient.mealFeedback(householdID: household.id)) ?? [:]
        } catch APIError.notFound {
            summary = nil
            dayRows = WeekViewModelMapper.emptyRows(weekStartDate: weekStartDate)
            today = dayRows.first(where: { $0.isToday }) ?? dayRows.first
            mealFeedback = [:]
        } catch {
            errorMessage = "We could not load this week."
        }
    }

    func toggleLock(day: WeekDayRowViewModel, household: Household, userID: String) async {
        let isLocked = lockedDays.contains(day.weekday)
        if isLocked { lockedDays.remove(day.weekday) } else { lockedDays.insert(day.weekday) }

        let event: WeekPlanEventInput = isLocked
            ? .mealUnlocked(day: day.weekday)
            : .mealLocked(day: day.weekday)

        do {
            try await apiClient.appendWeekPlanEvent(
                householdID: household.id,
                weekStartDate: weekStartDate,
                userID: userID,
                event: event
            )
        } catch {
            if isLocked { lockedDays.insert(day.weekday) } else { lockedDays.remove(day.weekday) }
        }
    }

    func toggleSkip(day: WeekDayRowViewModel, household: Household, userID: String) async {
        let isSkipped = skippedDays.contains(day.weekday)
        if isSkipped { skippedDays.remove(day.weekday) } else { skippedDays.insert(day.weekday) }

        let event: WeekPlanEventInput = isSkipped
            ? .dayUnskipped(day: day.weekday)
            : .daySkipped(day: day.weekday)

        do {
            try await apiClient.appendWeekPlanEvent(
                householdID: household.id,
                weekStartDate: weekStartDate,
                userID: userID,
                event: event
            )
        } catch {
            if isSkipped { skippedDays.insert(day.weekday) } else { skippedDays.remove(day.weekday) }
        }
    }

    func fetchFullRecipe(householdID: String, recipeID: String) async throws -> FullRecipe {
        try await apiClient.recipe(householdID: householdID, recipeID: recipeID)
    }

    func submitFeedback(mealID: String, vote: MealVote, household: Household) async {
        guard mealFeedback[mealID] != vote else { return }

        let previous = mealFeedback[mealID]
        mealFeedback[mealID] = vote

        do {
            try await apiClient.submitMealFeedback(householdID: household.id, mealID: mealID, vote: vote)
        } catch {
            mealFeedback[mealID] = previous
            errorMessage = "We could not save your feedback."
        }
    }

    func reset() {
        summary = nil
        dayRows = []
        today = nil
        lockedDays = []
        skippedDays = []
        mealFeedback = [:]
        errorMessage = nil
        isLoading = false
    }

    func seedForUITests() {
        let recipe = WeekSummaryRecipe(
            id: "22222222-2222-2222-2222-222222222222",
            title: "Monday Pasta",
            description: "Fast family pasta",
            servings: 4,
            prepTimeMinutes: 10,
            cookTimeMinutes: 15,
            tags: ["weekday"]
        )
        let days = Weekday.allCases.enumerated().map { index, weekday in
            WeekSummaryDay(
                dayOfWeek: weekday,
                date: WeekCalendar.addDays(to: weekStartDate, offset: index),
                state: index == 0 ? .planned : .empty,
                recipe: index == 0 ? recipe : nil
            )
        }
        let summary = WeekSummary(
            household: SummaryHousehold(id: "11111111-1111-1111-1111-111111111111", name: "Test household"),
            weekStartDate: weekStartDate,
            updatedAt: nil,
            days: days
        )
        self.summary = summary
        let mapped = WeekViewModelMapper.map(summary: summary, today: WeekCalendar.date(from: weekStartDate) ?? Date())
        dayRows = mapped.days
        today = mapped.today ?? mapped.days.first
    }
}

struct WeekDayRowViewModel: Equatable, Identifiable {
    let id: String
    let weekday: Weekday
    let weekdayLabel: String
    let dateLabel: String
    let mealTitle: String
    let detail: String
    let isToday: Bool
    let isEmpty: Bool
    let recipe: WeekSummaryRecipe?
}

struct WeekViewModelMapper {
    static func map(summary: WeekSummary, today: Date, calendar: Calendar = WeekCalendar.calendar) -> (days: [WeekDayRowViewModel], today: WeekDayRowViewModel?) {
        let rows = summary.days.map { day in
            row(from: day, today: today, calendar: calendar)
        }
        return (rows, rows.first(where: { $0.isToday }))
    }

    static func emptyRows(weekStartDate: String) -> [WeekDayRowViewModel] {
        Weekday.allCases.enumerated().map { index, weekday in
            let date = WeekCalendar.addDays(to: weekStartDate, offset: index)
            return WeekDayRowViewModel(
                id: date,
                weekday: weekday,
                weekdayLabel: weekday.displayName,
                dateLabel: WeekCalendar.shortDateLabel(yyyyMmDd: date),
                mealTitle: "No dinner planned",
                detail: "Plan this day from the web app for now.",
                isToday: WeekCalendar.isToday(yyyyMmDd: date),
                isEmpty: true,
                recipe: nil
            )
        }
    }

    private static func row(from day: WeekSummaryDay, today: Date, calendar: Calendar) -> WeekDayRowViewModel {
        let isToday = WeekCalendar.date(from: day.date).map { calendar.isDate($0, inSameDayAs: today) } ?? false
        let recipe = day.recipe
        return WeekDayRowViewModel(
            id: day.id,
            weekday: day.dayOfWeek,
            weekdayLabel: day.dayOfWeek.displayName,
            dateLabel: WeekCalendar.shortDateLabel(yyyyMmDd: day.date),
            mealTitle: recipe?.title ?? "No dinner planned",
            detail: recipe.map { recipeDetail($0) } ?? "Plan this day from the web app for now.",
            isToday: isToday,
            isEmpty: recipe == nil,
            recipe: recipe
        )
    }

    private static func recipeDetail(_ recipe: WeekSummaryRecipe) -> String {
        let time = [recipe.prepTimeMinutes, recipe.cookTimeMinutes]
            .compactMap { $0 }
            .reduce(0, +)
        if time > 0 {
            return "\(recipe.servings) servings · \(time) min"
        }
        return "\(recipe.servings) servings"
    }
}

extension Weekday {
    var displayName: String {
        switch self {
        case .monday:
            return "Monday"
        case .tuesday:
            return "Tuesday"
        case .wednesday:
            return "Wednesday"
        case .thursday:
            return "Thursday"
        case .friday:
            return "Friday"
        case .saturday:
            return "Saturday"
        case .sunday:
            return "Sunday"
        }
    }
}

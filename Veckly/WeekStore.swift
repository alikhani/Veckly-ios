import Foundation
import Observation

@MainActor
@Observable
final class WeekStore {
    private let apiClient: any WeekStoreAPIClient

    private(set) var weekStartDate: String = WeekCalendar.currentWeekStartDate()
    private(set) var summary: WeekSummary?
    private(set) var dayRows: [WeekDayRowViewModel] = []
    private(set) var today: WeekDayRowViewModel?
    var lockedDays: Set<Weekday> {
        Set(dayRows.filter(\.isLocked).map(\.weekday))
    }
    var skippedDays: Set<Weekday> {
        Set(dayRows.filter(\.isSkipped).map(\.weekday))
    }
    var hasPlannedMeals: Bool {
        dayRows.contains { $0.recipe != nil }
    }
    var hasWeekContent: Bool {
        dayRows.contains { $0.recipe != nil || $0.isSkipped }
    }
    var hasEmptyDays: Bool {
        dayRows.contains { $0.recipe == nil && !$0.isSkipped }
    }
    private(set) var isLoading = false
    private(set) var isGenerating = false
    private(set) var errorMessage: String?
    private(set) var lastFetchedAt: Date?

    init(apiClient: any WeekStoreAPIClient) {
        self.apiClient = apiClient
    }

    func loadCurrentWeek(household: Household) async {
        guard lastFetchedAt == nil || Date().timeIntervalSince(lastFetchedAt!) > 60 || summary == nil else { return }
        isLoading = true
        errorMessage = nil
        weekStartDate = WeekCalendar.currentWeekStartDate()
        defer { isLoading = false }

        do {
            let summary = try await apiClient.weekSummary(householdID: household.id, weekStartDate: weekStartDate)
            self.summary = summary
            lastFetchedAt = Date()
            let mapped = WeekViewModelMapper.map(summary: summary, today: Date())
            dayRows = mapped.days
            today = mapped.today
        } catch APIError.notFound {
            summary = nil
            dayRows = WeekViewModelMapper.emptyRows(weekStartDate: weekStartDate)
            today = dayRows.first(where: { $0.isToday }) ?? dayRows.first
        } catch {
            errorMessage = "We could not load this week."
        }
    }

    func toggleLock(day: WeekDayRowViewModel, household: Household, userID: String) async {
        errorMessage = nil
        let current = dayRows.first(where: { $0.weekday == day.weekday }) ?? day
        let isLocked = current.isLocked
        let previous = dayRows.first(where: { $0.weekday == day.weekday })
        let optimisticRow = current.withLocked(!isLocked)

        if let idx = dayRows.firstIndex(where: { $0.weekday == day.weekday }) {
            dayRows[idx] = optimisticRow
        }
        if current.isToday { today = optimisticRow }

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
            lastFetchedAt = Date()
        } catch {
            if let previous, let idx = dayRows.firstIndex(where: { $0.weekday == day.weekday }) {
                dayRows[idx] = previous
            }
            if current.isToday { today = previous }
            errorMessage = isLocked ? "We could not unlock this meal." : "We could not lock this meal."
        }
    }

    func toggleSkip(day: WeekDayRowViewModel, household: Household, userID: String) async {
        errorMessage = nil
        let current = dayRows.first(where: { $0.weekday == day.weekday }) ?? day
        let isSkipped = current.isSkipped
        let previous = dayRows.first(where: { $0.weekday == day.weekday })
        let optimisticRow = current.withSkipped(!isSkipped)

        if let idx = dayRows.firstIndex(where: { $0.weekday == day.weekday }) {
            dayRows[idx] = optimisticRow
        }
        if current.isToday { today = optimisticRow }

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
            lastFetchedAt = Date()
        } catch {
            if let previous, let idx = dayRows.firstIndex(where: { $0.weekday == day.weekday }) {
                dayRows[idx] = previous
            }
            if current.isToday { today = previous }
            errorMessage = isSkipped ? "We could not plan this day." : "We could not skip this day."
        }
    }

    func generateWeek(household: Household, userID: String, regenerate: Bool = false) async {
        isGenerating = true
        defer { isGenerating = false }

        do {
            try await apiClient.generateWeekPlan(householdID: household.id, weekStartDate: weekStartDate, regenerate: regenerate)
            lastFetchedAt = nil
            await loadCurrentWeek(household: household)
        } catch APIError.noRecipesForGeneration {
            errorMessage = "Add some recipes first — then we can plan your week."
        } catch {
            errorMessage = "We could not generate your week."
        }
    }

    func assignMeal(day: WeekDayRowViewModel, recipe: WeekSummaryRecipe, household: Household, userID: String) async {
        errorMessage = nil
        let previous = dayRows.first(where: { $0.weekday == day.weekday })

        let time = [recipe.prepTimeMinutes, recipe.cookTimeMinutes].compactMap { $0 }.reduce(0, +)
        let detail = time > 0 ? "\(recipe.servings) servings · \(time) min" : "\(recipe.servings) servings"
        let optimisticRow = WeekDayRowViewModel(
            id: day.id,
            weekday: day.weekday,
            weekdayLabel: day.weekdayLabel,
            dateLabel: day.dateLabel,
            mealTitle: recipe.title,
            detail: detail,
            isToday: day.isToday,
            isPast: day.isPast,
            isEmpty: false,
            isLocked: day.isLocked,
            isSkipped: false,
            recipe: recipe
        )

        if let idx = dayRows.firstIndex(where: { $0.weekday == day.weekday }) {
            dayRows[idx] = optimisticRow
        }
        if day.isToday { today = optimisticRow }

        do {
            try await apiClient.appendWeekPlanEvent(
                householdID: household.id,
                weekStartDate: weekStartDate,
                userID: userID,
                event: .mealAssigned(day: day.weekday, recipeID: recipe.id)
            )
            lastFetchedAt = Date()
        } catch {
            if let previous, let idx = dayRows.firstIndex(where: { $0.weekday == day.weekday }) {
                dayRows[idx] = previous
            }
            if day.isToday { today = previous }
            errorMessage = "We could not assign the meal."
        }
    }

    func unassignMeal(day: WeekDayRowViewModel, household: Household, userID: String) async {
        errorMessage = nil
        let previous = dayRows.first(where: { $0.weekday == day.weekday })

        let emptyRow = WeekDayRowViewModel(
            id: day.id,
            weekday: day.weekday,
            weekdayLabel: day.weekdayLabel,
            dateLabel: day.dateLabel,
            mealTitle: "",
            detail: "",
            isToday: day.isToday,
            isPast: day.isPast,
            isEmpty: true,
            isLocked: false,
            isSkipped: false,
            recipe: nil
        )

        if let idx = dayRows.firstIndex(where: { $0.weekday == day.weekday }) {
            dayRows[idx] = emptyRow
        }
        if day.isToday { today = emptyRow }

        do {
            try await apiClient.appendWeekPlanEvent(
                householdID: household.id,
                weekStartDate: weekStartDate,
                userID: userID,
                event: .mealUnassigned(day: day.weekday)
            )
            lastFetchedAt = Date()
        } catch {
            if let previous, let idx = dayRows.firstIndex(where: { $0.weekday == day.weekday }) {
                dayRows[idx] = previous
            }
            if day.isToday { today = previous }
            errorMessage = "We could not clear the meal."
        }
    }

    func fetchFullRecipe(householdID: String, recipeID: String) async throws -> FullRecipe {
        try await apiClient.recipe(householdID: householdID, recipeID: recipeID)
    }

    func reset() {
        summary = nil
        dayRows = []
        today = nil
        errorMessage = nil
        isLoading = false
        lastFetchedAt = nil
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
                state: index == 0 ? .planned : index == 2 ? .skipped : .empty,
                isLocked: index == 0,
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

protocol WeekStoreAPIClient {
    func weekSummary(householdID: String, weekStartDate: String) async throws -> WeekSummary
    func appendWeekPlanEvent(
        householdID: String,
        weekStartDate: String,
        userID: String,
        event: WeekPlanEventInput
    ) async throws
    func generateWeekPlan(householdID: String, weekStartDate: String, regenerate: Bool) async throws
    func recipe(householdID: String, recipeID: String) async throws -> FullRecipe
}

extension VecklyAPIClient: WeekStoreAPIClient {}

struct WeekDayRowViewModel: Equatable, Identifiable {
    let id: String
    let weekday: Weekday
    let weekdayLabel: String
    let dateLabel: String
    let mealTitle: String
    let detail: String
    let isToday: Bool
    let isPast: Bool
    let isEmpty: Bool
    let isLocked: Bool
    let isSkipped: Bool
    let recipe: WeekSummaryRecipe?

    init(
        id: String,
        weekday: Weekday,
        weekdayLabel: String,
        dateLabel: String,
        mealTitle: String,
        detail: String,
        isToday: Bool,
        isPast: Bool = false,
        isEmpty: Bool,
        isLocked: Bool = false,
        isSkipped: Bool = false,
        recipe: WeekSummaryRecipe?
    ) {
        self.id = id
        self.weekday = weekday
        self.weekdayLabel = weekdayLabel
        self.dateLabel = dateLabel
        self.mealTitle = mealTitle
        self.detail = detail
        self.isToday = isToday
        self.isPast = isPast
        self.isEmpty = isEmpty
        self.isLocked = isLocked
        self.isSkipped = isSkipped
        self.recipe = recipe
    }

    func withSkipped(_ isSkipped: Bool) -> WeekDayRowViewModel {
        WeekDayRowViewModel(
            id: id,
            weekday: weekday,
            weekdayLabel: weekdayLabel,
            dateLabel: dateLabel,
            mealTitle: isSkipped ? "" : mealTitle,
            detail: isSkipped ? "" : detail,
            isToday: isToday,
            isPast: isPast,
            isEmpty: !isSkipped && recipe == nil,
            isLocked: isSkipped ? false : isLocked,
            isSkipped: isSkipped,
            recipe: isSkipped ? nil : recipe
        )
    }

    func withLocked(_ isLocked: Bool) -> WeekDayRowViewModel {
        WeekDayRowViewModel(
            id: id,
            weekday: weekday,
            weekdayLabel: weekdayLabel,
            dateLabel: dateLabel,
            mealTitle: mealTitle,
            detail: detail,
            isToday: isToday,
            isPast: isPast,
            isEmpty: isEmpty,
            isLocked: isLocked,
            isSkipped: isSkipped,
            recipe: recipe
        )
    }
}

struct WeekViewModelMapper {
    static func map(summary: WeekSummary, today: Date, calendar: Calendar = WeekCalendar.calendar) -> (days: [WeekDayRowViewModel], today: WeekDayRowViewModel?) {
        let localCal = Calendar.current
        let rows = summary.days.map { day in
            row(from: day, today: today, utcCalendar: calendar, localCal: localCal)
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
                mealTitle: "",
                detail: "",
                isToday: WeekCalendar.isToday(yyyyMmDd: date),
                isPast: WeekCalendar.isPast(yyyyMmDd: date),
                isEmpty: true,
                isLocked: false,
                recipe: nil
            )
        }
    }

    private static func row(from day: WeekSummaryDay, today: Date, utcCalendar: Calendar, localCal: Calendar) -> WeekDayRowViewModel {
        let dayDate = WeekCalendar.date(from: day.date)
        // Use the device's local calendar so midnight boundaries follow the
        // user's timezone, not UTC.
        let isToday = dayDate.map { localCal.isDate($0, inSameDayAs: today) } ?? false
        let isPast = dayDate.map { date in
            !localCal.isDate(date, inSameDayAs: today)
                && date < localCal.startOfDay(for: today)
        } ?? false
        let recipe = day.recipe
        let isSkipped = day.state == .skipped
        return WeekDayRowViewModel(
            id: day.id,
            weekday: day.dayOfWeek,
            weekdayLabel: day.dayOfWeek.displayName,
            dateLabel: WeekCalendar.shortDateLabel(yyyyMmDd: day.date),
            mealTitle: recipe?.title ?? "",
            detail: recipe.map { recipeDetail($0) } ?? "",
            isToday: isToday,
            isPast: isPast,
            isEmpty: recipe == nil && !isSkipped,
            isLocked: day.isLocked,
            isSkipped: isSkipped,
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

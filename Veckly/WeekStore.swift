import Foundation
import Observation

@MainActor
@Observable
final class WeekStore {
    private let apiClient: any WeekStoreAPIClient
    private let syncDebounceNanoseconds: UInt64
    private let retryDelayNanoseconds: UInt64

    private(set) var weekStartDate: String = WeekCalendar.currentWeekStartDate()
    private(set) var summary: WeekSummary?
    private(set) var dayRows: [WeekDayRowViewModel] = []
    private(set) var currentWeekDayRows: [WeekDayRowViewModel] = []
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
    private(set) var mutationError: String?
    private(set) var lastFetchedAt: Date?
    private(set) var hasPendingSync = false
    private var pendingSyncContext: WeekPendingSyncContext?
    private var pendingDesiredDayStates: [Weekday: WeekPendingDayState] = [:]
    private var syncedDayStates: [Weekday: WeekPendingDayState] = [:]
    private var flushTask: Task<Void, Never>?
    private var isFlushingPendingChanges = false

    init(
        apiClient: any WeekStoreAPIClient,
        syncDebounceNanoseconds: UInt64 = 400_000_000,
        retryDelayNanoseconds: UInt64 = 2_000_000_000
    ) {
        self.apiClient = apiClient
        self.syncDebounceNanoseconds = syncDebounceNanoseconds
        self.retryDelayNanoseconds = retryDelayNanoseconds
    }

    func clearMutationError() { mutationError = nil }

    func loadCurrentWeek(household: Household) async {
        weekStartDate = WeekCalendar.currentWeekStartDate()
        guard !isLoading else { return }
        let hasFreshCurrentWeek = lastFetchedAt.map { Date().timeIntervalSince($0) <= 300 } == true
            && summary?.weekStartDate == weekStartDate
        guard !hasFreshCurrentWeek else { return }
        isLoading = summary == nil
        errorMessage = nil
        defer { isLoading = false }

        do {
            let summary = try await apiClient.weekSummary(householdID: household.id, weekStartDate: weekStartDate)
            self.summary = summary
            lastFetchedAt = Date()
            let mapped = WeekViewModelMapper.map(summary: summary, today: Date())
            dayRows = mapped.days
            currentWeekDayRows = dayRows
            today = mapped.today
            syncedDayStates = Dictionary(uniqueKeysWithValues: mapped.days.map { ($0.weekday, WeekPendingDayState(row: $0)) })
            reapplyPendingStateIfNeeded(for: weekStartDate)
        } catch APIError.notFound {
            summary = nil
            dayRows = WeekViewModelMapper.emptyRows(weekStartDate: weekStartDate)
            currentWeekDayRows = dayRows
            today = dayRows.first(where: { $0.isToday }) ?? dayRows.first
            syncedDayStates = Dictionary(uniqueKeysWithValues: dayRows.map { ($0.weekday, WeekPendingDayState(row: $0)) })
        } catch {
            errorMessage = L10n.string("error.week.load")
        }
    }

    /// Loads a specific week's summary for browsing (Last/Next week), populating
    /// `summary`/`dayRows`/`today` exactly like `loadCurrentWeek` does — but
    /// without touching `weekStartDate`, which other tabs (Shopping List, Prep)
    /// read as "the active week." Callers (e.g. WeekTabView's browsing UI) own
    /// their own viewed-week state and pass it back in for mutations.
    func loadWeek(household: Household, weekStartDate: String) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let summary = try await apiClient.weekSummary(householdID: household.id, weekStartDate: weekStartDate)
            self.summary = summary
            let mapped = WeekViewModelMapper.map(summary: summary, today: Date())
            dayRows = mapped.days
            today = mapped.today
            syncedDayStates = Dictionary(uniqueKeysWithValues: mapped.days.map { ($0.weekday, WeekPendingDayState(row: $0)) })
            reapplyPendingStateIfNeeded(for: weekStartDate)
        } catch APIError.notFound {
            summary = nil
            dayRows = WeekViewModelMapper.emptyRows(weekStartDate: weekStartDate)
            today = dayRows.first(where: { $0.isToday }) ?? dayRows.first
            syncedDayStates = Dictionary(uniqueKeysWithValues: dayRows.map { ($0.weekday, WeekPendingDayState(row: $0)) })
        } catch {
            errorMessage = L10n.string("error.week.load")
        }
    }

    /// Side-effect-free check used by the weekend nudge to ask "does next week
    /// have anything planned yet?" without disturbing the currently displayed
    /// week's `summary`/`dayRows`/`isLoading` state.
    func peekHasContent(household: Household, weekStartDate: String) async -> Bool {
        do {
            let summary = try await apiClient.weekSummary(householdID: household.id, weekStartDate: weekStartDate)
            return summary.days.contains { $0.recipe != nil || $0.state == .skipped }
        } catch {
            return false
        }
    }

    func toggleLock(day: WeekDayRowViewModel, household: Household, userID: String, viewedWeekStartDate: String? = nil) async {
        let targetWeekStartDate = viewedWeekStartDate ?? weekStartDate
        mutationError = nil
        let current = dayRows.first(where: { $0.weekday == day.weekday }) ?? day
        let optimisticRow = current.withLocked(!current.isLocked)

        await preparePendingSyncContext(
            householdID: household.id,
            userID: userID,
            weekStartDate: targetWeekStartDate
        )
        applyVisibleRow(optimisticRow)
        pendingDesiredDayStates[day.weekday] = WeekPendingDayState(row: optimisticRow)
        hasPendingSync = !pendingDesiredDayStates.isEmpty
        schedulePendingFlush()
    }

    func toggleSkip(day: WeekDayRowViewModel, household: Household, userID: String, viewedWeekStartDate: String? = nil) async {
        let targetWeekStartDate = viewedWeekStartDate ?? weekStartDate
        mutationError = nil
        let current = dayRows.first(where: { $0.weekday == day.weekday }) ?? day
        let optimisticRow = current.withSkipped(!current.isSkipped)

        await preparePendingSyncContext(
            householdID: household.id,
            userID: userID,
            weekStartDate: targetWeekStartDate
        )
        applyVisibleRow(optimisticRow)
        pendingDesiredDayStates[day.weekday] = WeekPendingDayState(row: optimisticRow)
        hasPendingSync = !pendingDesiredDayStates.isEmpty
        schedulePendingFlush()
    }

    func generateWeek(household: Household, userID: String, regenerate: Bool = false, viewedWeekStartDate: String? = nil) async {
        let targetWeekStartDate = viewedWeekStartDate ?? weekStartDate
        isGenerating = true
        defer { isGenerating = false }

        do {
            try await apiClient.generateWeekPlan(householdID: household.id, weekStartDate: targetWeekStartDate, regenerate: regenerate)
            if targetWeekStartDate == weekStartDate {
                lastFetchedAt = nil
                await loadCurrentWeek(household: household)
            } else {
                await loadWeek(household: household, weekStartDate: targetWeekStartDate)
            }
        } catch APIError.noRecipesForGeneration {
            mutationError = L10n.string("error.week.noRecipes")
        } catch {
            mutationError = L10n.string("error.week.generate")
        }
    }

    func assignMeal(day: WeekDayRowViewModel, recipe: WeekSummaryRecipe, household: Household, userID: String, viewedWeekStartDate: String? = nil) async {
        let targetWeekStartDate = viewedWeekStartDate ?? weekStartDate
        mutationError = nil
        let previous = dayRows.first(where: { $0.weekday == day.weekday })

        let time = [recipe.prepTimeMinutes, recipe.cookTimeMinutes].compactMap { $0 }.reduce(0, +)
        let servings = L10n.format("format.servings", recipe.servings)
        let detail = time > 0 ? "\(servings) · \(time) min" : servings
        let optimisticRow = WeekDayRowViewModel(
            id: day.id,
            weekday: day.weekday,
            weekdayLabel: day.weekdayLabel,
            date: day.date,
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
                weekStartDate: targetWeekStartDate,
                userID: userID,
                event: .mealAssigned(day: day.weekday, recipeID: recipe.id)
            )
            if targetWeekStartDate == weekStartDate { lastFetchedAt = Date() }
        } catch {
            if let previous, let idx = dayRows.firstIndex(where: { $0.weekday == day.weekday }) {
                dayRows[idx] = previous
            }
            if day.isToday { today = previous }
            mutationError = L10n.string("error.week.assignMeal")
        }
    }

    func unassignMeal(day: WeekDayRowViewModel, household: Household, userID: String, viewedWeekStartDate: String? = nil) async {
        let targetWeekStartDate = viewedWeekStartDate ?? weekStartDate
        mutationError = nil
        let previous = dayRows.first(where: { $0.weekday == day.weekday })

        let emptyRow = WeekDayRowViewModel(
            id: day.id,
            weekday: day.weekday,
            weekdayLabel: day.weekdayLabel,
            date: day.date,
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
                weekStartDate: targetWeekStartDate,
                userID: userID,
                event: .mealUnassigned(day: day.weekday)
            )
            if targetWeekStartDate == weekStartDate { lastFetchedAt = Date() }
        } catch {
            if let previous, let idx = dayRows.firstIndex(where: { $0.weekday == day.weekday }) {
                dayRows[idx] = previous
            }
            if day.isToday { today = previous }
            mutationError = L10n.string("error.week.clearMeal")
        }
    }

    func fetchFullRecipe(householdID: String, recipeID: String) async throws -> FullRecipe {
        try await apiClient.recipe(householdID: householdID, recipeID: recipeID)
    }

    func reset() {
        flushTask?.cancel()
        flushTask = nil
        summary = nil
        dayRows = []
        currentWeekDayRows = []
        today = nil
        errorMessage = nil
        mutationError = nil
        isLoading = false
        lastFetchedAt = nil
        hasPendingSync = false
        pendingSyncContext = nil
        pendingDesiredDayStates = [:]
        syncedDayStates = [:]
        isFlushingPendingChanges = false
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
        syncedDayStates = Dictionary(uniqueKeysWithValues: mapped.days.map { ($0.weekday, WeekPendingDayState(row: $0)) })
    }

    private func preparePendingSyncContext(
        householdID: String,
        userID: String,
        weekStartDate: String
    ) async {
        if let context = pendingSyncContext,
           (context.householdID != householdID || context.userID != userID || context.weekStartDate != weekStartDate),
           !pendingDesiredDayStates.isEmpty {
            await flushPendingDayChanges()
        }

        if pendingSyncContext?.householdID != householdID
            || pendingSyncContext?.userID != userID
            || pendingSyncContext?.weekStartDate != weekStartDate {
            pendingSyncContext = WeekPendingSyncContext(
                householdID: householdID,
                userID: userID,
                weekStartDate: weekStartDate
            )
        }
    }

    private func schedulePendingFlush(immediate: Bool = false) {
        guard pendingSyncContext != nil, !isFlushingPendingChanges else { return }
        flushTask?.cancel()
        let delay = immediate ? UInt64.zero : syncDebounceNanoseconds
        flushTask = Task { [weak self] in
            guard let self else { return }
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            guard !Task.isCancelled else { return }
            await self.flushPendingDayChanges()
        }
    }

    private func flushPendingDayChanges() async {
        guard let context = pendingSyncContext, !pendingDesiredDayStates.isEmpty, !isFlushingPendingChanges else { return }
        isFlushingPendingChanges = true

        for weekday in Weekday.allCases {
            guard let desired = pendingDesiredDayStates[weekday] else { continue }
            let baseline = syncedDayStates[weekday] ?? desired

            do {
                try await syncDesiredState(desired, baseline: baseline, weekday: weekday, context: context)
                syncedDayStates[weekday] = desired
                pendingDesiredDayStates.removeValue(forKey: weekday)
                if context.weekStartDate == weekStartDate { lastFetchedAt = Date() }
            } catch {
                let latest = try? await apiClient.weekSummary(
                    householdID: context.householdID,
                    weekStartDate: context.weekStartDate
                )
                if let latest {
                    let mapped = WeekViewModelMapper.map(summary: latest, today: Date())
                    syncedDayStates = Dictionary(uniqueKeysWithValues: mapped.days.map { ($0.weekday, WeekPendingDayState(row: $0)) })
                    if summary?.weekStartDate == latest.weekStartDate {
                        summary = latest
                        dayRows = mapped.days
                        today = mapped.today
                        reapplyPendingStateIfNeeded(for: latest.weekStartDate)
                    }

                    if let refreshedBaseline = syncedDayStates[weekday],
                       refreshedBaseline == desired {
                        pendingDesiredDayStates.removeValue(forKey: weekday)
                        continue
                    }
                }

                mutationError = L10n.string("error.week.pendingSync")
                hasPendingSync = !pendingDesiredDayStates.isEmpty
                isFlushingPendingChanges = false
                scheduleRetryFlush()
                return
            }
        }

        hasPendingSync = !pendingDesiredDayStates.isEmpty
        if pendingDesiredDayStates.isEmpty {
            pendingSyncContext = nil
            mutationError = nil
        }
        isFlushingPendingChanges = false
    }

    private func scheduleRetryFlush() {
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: retryDelayNanoseconds)
            guard !Task.isCancelled else { return }
            await self.flushPendingDayChanges()
        }
    }

    private func syncDesiredState(
        _ desired: WeekPendingDayState,
        baseline: WeekPendingDayState,
        weekday: Weekday,
        context: WeekPendingSyncContext
    ) async throws {
        var working = baseline

        if working.isSkipped != desired.isSkipped {
            try await apiClient.appendWeekPlanEvent(
                householdID: context.householdID,
                weekStartDate: context.weekStartDate,
                userID: context.userID,
                event: desired.isSkipped ? .daySkipped(day: weekday) : .dayUnskipped(day: weekday)
            )
            working.isSkipped = desired.isSkipped
            if desired.isSkipped {
                working.isLocked = false
            }
        }

        if working.isLocked != desired.isLocked {
            try await apiClient.appendWeekPlanEvent(
                householdID: context.householdID,
                weekStartDate: context.weekStartDate,
                userID: context.userID,
                event: desired.isLocked ? .mealLocked(day: weekday) : .mealUnlocked(day: weekday)
            )
        }
    }

    private func reapplyPendingStateIfNeeded(for weekStartDate: String) {
        guard pendingSyncContext?.weekStartDate == weekStartDate else { return }
        for (weekday, desired) in pendingDesiredDayStates {
            guard let row = dayRows.first(where: { $0.weekday == weekday }) else { continue }
            applyVisibleRow(desired.apply(to: row))
        }
        hasPendingSync = !pendingDesiredDayStates.isEmpty
    }

    private func applyVisibleRow(_ row: WeekDayRowViewModel) {
        if let idx = dayRows.firstIndex(where: { $0.weekday == row.weekday }) {
            dayRows[idx] = row
        }
        if row.isToday {
            today = row
        } else if today?.weekday == row.weekday {
            today = row
        }
    }
}

private struct WeekPendingSyncContext {
    let householdID: String
    let userID: String
    let weekStartDate: String
}

private struct WeekPendingDayState: Equatable {
    var isLocked: Bool
    var isSkipped: Bool

    init(row: WeekDayRowViewModel) {
        self.isLocked = row.isLocked
        self.isSkipped = row.isSkipped
    }

    func apply(to row: WeekDayRowViewModel) -> WeekDayRowViewModel {
        let skippedAdjusted = row.withSkipped(isSkipped)
        return skippedAdjusted.withLocked(isSkipped ? false : isLocked)
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
    let date: String
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
        date: String,
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
        self.date = date
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
            date: date,
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
            date: date,
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

    /// Used by `MealPickerSheet` to render a just-confirmed-but-not-yet-synced
    /// selection the same way `DayDetailContent` renders an already-planned day.
    func withPlannedRecipe(_ recipe: WeekSummaryRecipe) -> WeekDayRowViewModel {
        WeekDayRowViewModel(
            id: id,
            weekday: weekday,
            weekdayLabel: weekdayLabel,
            date: date,
            dateLabel: dateLabel,
            mealTitle: recipe.title,
            detail: WeekViewModelMapper.recipeDetail(recipe),
            isToday: isToday,
            isPast: isPast,
            isEmpty: false,
            isLocked: isLocked,
            isSkipped: false,
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
                date: date,
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
            date: day.date,
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

    static func recipeDetail(_ recipe: WeekSummaryRecipe) -> String {
        let time = [recipe.prepTimeMinutes, recipe.cookTimeMinutes]
            .compactMap { $0 }
            .reduce(0, +)
        let servings = L10n.format("format.servings", recipe.servings)
        if time > 0 {
            return "\(servings) · \(time) min"
        }
        return servings
    }
}

extension Weekday {
    var displayName: String {
        localizedName(template: "EEEE")
    }

    var shortDisplayName: String {
        localizedName(template: "EEE")
    }

    private func localizedName(template: String) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = AppLocalePreference.effectiveLocale
        let monday = DateComponents(calendar: calendar, year: 2024, month: 1, day: 1).date!
        let date = calendar.date(byAdding: .day, value: ordinal, to: monday)!
        let formatter = DateFormatter()
        formatter.locale = AppLocalePreference.effectiveLocale
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    private var ordinal: Int {
        switch self {
        case .monday: return 0
        case .tuesday: return 1
        case .wednesday: return 2
        case .thursday: return 3
        case .friday: return 4
        case .saturday: return 5
        case .sunday: return 6
        }
    }
}

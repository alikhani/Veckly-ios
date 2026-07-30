import Testing
@testable import Veckly

struct WeekListPresentationTests {
    @Test func currentEmptyAndStartedWeeksKeepTheSameMondayFirstStructure() {
        let emptyDays = weekDays()
        var startedDays = emptyDays
        startedDays[2] = day(.wednesday, recipe: recipe())

        let empty = presentation(days: emptyDays, offset: .current, includesWeekend: true)
        let started = presentation(days: startedDays, offset: .current, includesWeekend: true)

        #expect(empty.mainDays.map(\.weekday) == Weekday.allCases)
        #expect(started.mainDays.map(\.weekday) == Weekday.allCases)
        #expect(empty.mainDays.first?.weekday == .monday)
    }

    @Test func currentPastRowsAreReadOnlyOrStaticWhileNonPastRowsStayEditable() {
        let pastEmpty = day(.monday, isPast: true)
        let pastPlanned = day(.tuesday, recipe: recipe(), isPast: true)
        let todayEmpty = day(.wednesday)
        let futurePlanned = day(.thursday, recipe: recipe())
        let result = presentation(
            days: [pastEmpty, pastPlanned, todayEmpty, futurePlanned],
            offset: .current,
            includesWeekend: true
        )

        #expect(result.interaction(for: pastEmpty) == .none)
        #expect(result.interaction(for: pastPlanned) == .viewRecipe)
        #expect(result.interaction(for: todayEmpty) == .planDay)
        #expect(result.interaction(for: futurePlanned) == .editDay)
    }

    @Test func futureWeekIsFullyEditable() {
        let empty = day(.monday)
        let planned = day(.tuesday, recipe: recipe())
        let result = presentation(days: [empty, planned], offset: .next, includesWeekend: true)

        #expect(result.interaction(for: empty) == .planDay)
        #expect(result.interaction(for: planned) == .editDay)
    }

    @Test func lastWeekIsFullyReadOnly() {
        var days = weekDays().map {
            day($0.weekday, isPast: true)
        }
        days[1] = day(.tuesday, recipe: recipe(), isPast: true)
        let result = presentation(days: days, offset: .last, includesWeekend: true)

        #expect(result.mainDays.map(\.weekday) == Weekday.allCases)
        #expect(result.interaction(for: days[0]) == .none)
        #expect(result.interaction(for: days[1]) == .viewRecipe)
    }

    @Test func weekendCollapseKeepsWeekdaysInMainListAndWeekendInDisclosure() {
        let collapsed = presentation(days: weekDays(), offset: .current, includesWeekend: false)
        let expanded = presentation(days: weekDays(), offset: .current, includesWeekend: true)

        #expect(collapsed.shouldCollapseWeekend)
        #expect(collapsed.mainDays.map(\.weekday) == [.monday, .tuesday, .wednesday, .thursday, .friday])
        #expect(collapsed.weekendDays.map(\.weekday) == [.saturday, .sunday])
        #expect(!expanded.shouldCollapseWeekend)
        #expect(expanded.mainDays.map(\.weekday) == Weekday.allCases)
    }

    private func presentation(
        days: [WeekDayRowViewModel],
        offset: ViewedWeekOffset,
        includesWeekend: Bool
    ) -> WeekListPresentation {
        WeekListPresentation(days: days, viewedWeekOffset: offset, includesWeekend: includesWeekend)
    }

    private func weekDays() -> [WeekDayRowViewModel] {
        Weekday.allCases.map { day($0) }
    }

    private func day(
        _ weekday: Weekday,
        recipe: WeekSummaryRecipe? = nil,
        isPast: Bool = false
    ) -> WeekDayRowViewModel {
        WeekDayRowViewModel(
            id: weekday.rawValue,
            weekday: weekday,
            weekdayLabel: weekday.rawValue,
            date: "2026-07-27",
            dateLabel: "27 Jul",
            mealTitle: recipe?.title ?? "",
            detail: "",
            isToday: false,
            isPast: isPast,
            isEmpty: recipe == nil,
            isLocked: false,
            isSkipped: false,
            recipe: recipe
        )
    }

    private func recipe() -> WeekSummaryRecipe {
        WeekSummaryRecipe(
            id: "recipe",
            title: "Pasta",
            description: "",
            servings: 4,
            prepTimeMinutes: nil,
            cookTimeMinutes: nil,
            tags: []
        )
    }
}

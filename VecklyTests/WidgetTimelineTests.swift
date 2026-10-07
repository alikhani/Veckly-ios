import Foundation
import Testing
@testable import Veckly

/// The widget extension can't be unit-tested directly; its render-time
/// decisions live in the shared `WidgetTimeline`.
struct WidgetTimelineTests {
    private let stockholm: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        return calendar
    }()

    /// Written Sunday 2026-10-11 at 20:00 Stockholm, right after planning next week.
    private var sundayEvening: Date { date("2026-10-11T18:00:00Z") }

    private var sundaySnapshot: WidgetSnapshot {
        WidgetSnapshot(
            updatedAt: sundayEvening,
            meals: [
                meal("2026-10-11", "Sunday soup"),
                meal("2026-10-12", "Monday tacos"),
                meal("2026-10-13", "Tuesday pasta"),
            ],
            shoppingRemainingCount: 4
        )
    }

    @Test func showsTodaysDinnerFirstWhenFresh() {
        #expect(WidgetTimeline.dinnerState(for: sundaySnapshot, at: sundayEvening, calendar: stockholm)
            == .meals(sundaySnapshot.meals))
    }

    @Test func dropsYesterdaysDinnerAfterLocalMidnight() {
        let mondayMorning = date("2026-10-12T05:30:00Z") // 07:30 Stockholm, 11.5 h later

        #expect(WidgetTimeline.dinnerState(for: sundaySnapshot, at: mondayMorning, calendar: stockholm)
            == .meals(Array(sundaySnapshot.meals.dropFirst())))
    }

    @Test func keepsShowingPlannedDinnersLongAfterTwelveHours() {
        let tuesdayEvening = date("2026-10-13T16:00:00Z")

        #expect(WidgetTimeline.dinnerState(for: sundaySnapshot, at: tuesdayEvening, calendar: stockholm)
            == .meals([meal("2026-10-13", "Tuesday pasta")]))
    }

    @Test func asksForAnUpdateOnceEveryKnownDinnerHasPassed() {
        let wednesday = date("2026-10-14T06:00:00Z")

        #expect(WidgetTimeline.dinnerState(for: sundaySnapshot, at: wednesday, calendar: stockholm) == .needsUpdate)
    }

    @Test func nothingPlannedOnlyWhileTheEmptySnapshotIsFresh() {
        let empty = WidgetSnapshot(updatedAt: sundayEvening, meals: [], shoppingRemainingCount: 0)

        #expect(WidgetTimeline.dinnerState(for: empty, at: sundayEvening, calendar: stockholm) == .nothingPlanned)
        #expect(WidgetTimeline.dinnerState(for: empty, at: sundayEvening.addingTimeInterval(13 * 3600), calendar: stockholm) == .needsUpdate)
        #expect(WidgetTimeline.dinnerState(for: nil, at: sundayEvening, calendar: stockholm) == .needsUpdate)
    }

    @Test func timelineHasAnEntryAtEachLocalMidnightThroughTheLastDinner() {
        let dates = WidgetTimeline.entryDates(for: sundaySnapshot, now: sundayEvening, calendar: stockholm)

        #expect(dates == [
            sundayEvening,
            date("2026-10-11T22:00:00Z"), // Monday 00:00 Stockholm
            date("2026-10-12T06:00:00Z"), // stale horizon (shopping count)
            date("2026-10-12T22:00:00Z"), // Tuesday 00:00
            date("2026-10-13T22:00:00Z"), // Wednesday 00:00 — last dinner gone
        ])
    }

    @Test func timelineWithoutMealsStillRollsOverAtTheNextMidnight() {
        let dates = WidgetTimeline.entryDates(for: nil, now: sundayEvening, calendar: stockholm)

        #expect(dates == [sundayEvening, date("2026-10-11T22:00:00Z")])
    }

    @Test func decodesASnapshotWrittenByTheEarlierAppVersion() throws {
        let json = #"{"updatedAt":781000000,"meals":[{"date":"2026-10-12","title":"Tacos","recipeID":"r1"}],"shoppingRemainingCount":2}"#
        let snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(json.utf8))

        #expect(snapshot.meals == [WidgetMealSnapshot(date: "2026-10-12", title: "Tacos", minutes: nil, recipeID: "r1")])
    }

    @Test func wholeWidgetTapOpensTheFirstUpcomingDinner() throws {
        let mondayMorning = date("2026-10-12T05:30:00Z")
        let state = WidgetTimeline.dinnerState(for: sundaySnapshot, at: mondayMorning, calendar: stockholm)

        let url = try #require(state.widgetURL)
        #expect(AppDeepLink(url: url) == .meal(date: "2026-10-12", recipeID: "Monday tacos"))
        #expect(WidgetDinnerState.needsUpdate.widgetURL == nil)
        #expect(WidgetDinnerState.nothingPlanned.widgetURL == nil)
    }

    @Test func shoppingWidgetTapOpensTheShoppingList() {
        #expect(AppDeepLink(url: WidgetSnapshot.shoppingURL) == .shopping)
    }

    private func meal(_ date: String, _ title: String) -> WidgetMealSnapshot {
        WidgetMealSnapshot(date: date, title: title, minutes: 30, recipeID: title)
    }

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }
}

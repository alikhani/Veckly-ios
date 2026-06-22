import Foundation
import Testing
@testable import Veckly

struct WeekCalendarTests {
    @Test func currentWeekStartDateUsesMonday() {
        let date = ISO8601DateFormatter().date(from: "2026-06-11T12:00:00Z")!

        #expect(WeekCalendar.currentWeekStartDate(now: date) == "2026-06-08")
    }

    @Test func addDaysKeepsCalendarDateFormat() {
        #expect(WeekCalendar.addDays(to: "2026-06-08", offset: 6) == "2026-06-14")
    }

    @Test func addWeeksMovesByWholeWeeks() {
        #expect(WeekCalendar.addWeeks(to: "2026-06-08", offset: 1) == "2026-06-15")
        #expect(WeekCalendar.addWeeks(to: "2026-06-08", offset: -1) == "2026-06-01")
        #expect(WeekCalendar.addWeeks(to: "2026-06-08", offset: 0) == "2026-06-08")
    }

    @Test func weekNumberMatchesISO8601Numbering() {
        // A well-known mid-year week with no ambiguity.
        #expect(WeekCalendar.weekNumber(for: "2026-06-08") == 24)
    }

    @Test func weekNumberHandlesYearBoundarySpanningTwoYears() {
        // Dec 29, 2025 (Monday) starts ISO week 1 of 2026, even though the
        // calendar date itself is still in 2025 — this is exactly the case the
        // default Gregorian `weekOfYear` component gets wrong.
        #expect(WeekCalendar.weekNumber(for: "2025-12-29") == 1)
        // Dec 28, 2026 (Monday) is ISO week 53 of 2026 (a 53-week year).
        #expect(WeekCalendar.weekNumber(for: "2026-12-28") == 53)
        // Jan 4, 2027 (Monday) is ISO week 1 of 2027.
        #expect(WeekCalendar.weekNumber(for: "2027-01-04") == 1)
    }

    // `dateRangeLabel` formats with `setLocalizedDateFormatFromTemplate`, which
    // follows the device/test-runner's current locale by design (consistent
    // with the rest of the app's localization approach) — so these assertions
    // check shape (single "–" joiner vs both endpoints spelled out) rather than
    // an exact locale-specific string, to stay correct under any system locale.
    @Test func dateRangeLabelSpansSameMonthUsesEnDashWithoutRepeatingMonth() {
        let label = WeekCalendar.dateRangeLabel(weekStartDate: "2026-06-08")
        #expect(label.contains("–"))
        #expect(!label.contains(" – ")) // same-month range has no surrounding spaces around the dash
        #expect(label.contains(WeekCalendar.shortDateLabel(yyyyMmDd: "2026-06-08")))
    }

    @Test func dateRangeLabelSpansAcrossMonthsShowsBothFullDates() {
        let label = WeekCalendar.dateRangeLabel(weekStartDate: "2026-06-29")
        #expect(label.contains(" – ")) // cross-month range separates two full short dates
        #expect(label.contains(WeekCalendar.shortDateLabel(yyyyMmDd: "2026-06-29")))
        #expect(label.contains(WeekCalendar.shortDateLabel(yyyyMmDd: "2026-07-05")))
    }
}

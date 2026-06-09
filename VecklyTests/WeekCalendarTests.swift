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
}

import Foundation
import Testing
import UserNotifications
@testable import Veckly

@MainActor
struct SundayReminderSchedulerTests {
    // 2026-06-06 is a Saturday, 2026-06-07 a Sunday, 2026-06-08 a Monday (UTC).
    private let saturday = Date(timeIntervalSince1970: 1_780_704_000)
    private let sunday = Date(timeIntervalSince1970: 1_780_790_400)
    private let monday = Date(timeIntervalSince1970: 1_780_876_800)

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "SundayReminderSchedulerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test func doesNothingOnAWeekday() async {
        let client = StubSundayReminderNotifying(authorizationStatus: .authorized)
        let scheduler = SundayReminderScheduler(notificationCenter: client, defaults: makeDefaults(), calendar: utcCalendar(), now: { monday })
        var wasAsked = false

        await scheduler.refreshIfNeeded { wasAsked = true; return true }

        #expect(wasAsked == false)
        #expect(client.addedRequests.isEmpty)
    }

    @Test func schedulesOnAWeekendWhenNextWeekIsEmptyAndAlreadyAuthorized() async {
        let client = StubSundayReminderNotifying(authorizationStatus: .authorized)
        let scheduler = SundayReminderScheduler(notificationCenter: client, defaults: makeDefaults(), calendar: utcCalendar(), now: { saturday })

        await scheduler.refreshIfNeeded { true }

        #expect(client.addedRequests.map(\.identifier) == ["veckly.sundayPlanningReminder"])
    }

    @Test func cancelsAnyPendingReminderWhenNextWeekIsNoLongerEmpty() async {
        let client = StubSundayReminderNotifying(authorizationStatus: .authorized)
        let scheduler = SundayReminderScheduler(notificationCenter: client, defaults: makeDefaults(), calendar: utcCalendar(), now: { sunday })

        await scheduler.refreshIfNeeded { false }

        #expect(client.addedRequests.isEmpty)
        #expect(client.removedIdentifiers == ["veckly.sundayPlanningReminder"])
    }

    @Test func requestsAuthorizationLazilyOnlyWhenThereIsSomethingToScheduleAndSchedulesIfGranted() async {
        let client = StubSundayReminderNotifying(authorizationStatus: .notDetermined, requestAuthorizationResult: .success(true))
        let scheduler = SundayReminderScheduler(notificationCenter: client, defaults: makeDefaults(), calendar: utcCalendar(), now: { saturday })

        await scheduler.refreshIfNeeded { true }

        #expect(client.requestAuthorizationCallCount == 1)
        #expect(client.addedRequests.count == 1)
    }

    @Test func doesNotScheduleWhenPermissionIsDenied() async {
        let client = StubSundayReminderNotifying(authorizationStatus: .denied)
        let scheduler = SundayReminderScheduler(notificationCenter: client, defaults: makeDefaults(), calendar: utcCalendar(), now: { saturday })

        await scheduler.refreshIfNeeded { true }

        #expect(client.requestAuthorizationCallCount == 0)
        #expect(client.addedRequests.isEmpty)
    }

    @Test func doesNotScheduleWhenTheLazyPermissionRequestIsDeclined() async {
        let client = StubSundayReminderNotifying(authorizationStatus: .notDetermined, requestAuthorizationResult: .success(false))
        let scheduler = SundayReminderScheduler(notificationCenter: client, defaults: makeDefaults(), calendar: utcCalendar(), now: { saturday })

        await scheduler.refreshIfNeeded { true }

        #expect(client.addedRequests.isEmpty)
    }

    @Test func onlyChecksOncePerCalendarDayEvenAcrossMultipleAppForegrounds() async {
        let client = StubSundayReminderNotifying(authorizationStatus: .authorized)
        let defaults = makeDefaults()
        let scheduler = SundayReminderScheduler(notificationCenter: client, defaults: defaults, calendar: utcCalendar(), now: { saturday })
        var checkCount = 0

        await scheduler.refreshIfNeeded { checkCount += 1; return true }
        await scheduler.refreshIfNeeded { checkCount += 1; return true }

        #expect(checkCount == 1)
        #expect(client.addedRequests.count == 1)
    }

    @Test func checksAgainOnADifferentCalendarDay() async {
        let client = StubSundayReminderNotifying(authorizationStatus: .authorized)
        let defaults = makeDefaults()
        var currentDate = saturday
        let scheduler = SundayReminderScheduler(notificationCenter: client, defaults: defaults, calendar: utcCalendar(), now: { currentDate })

        await scheduler.refreshIfNeeded { true }
        currentDate = sunday
        await scheduler.refreshIfNeeded { true }

        #expect(client.addedRequests.count == 2)
    }
}

private final class StubSundayReminderNotifying: SundayReminderNotifying {
    private let statusToReturn: UNAuthorizationStatus
    private let requestAuthorizationResult: Result<Bool, Error>
    private(set) var addedRequests: [UNNotificationRequest] = []
    private(set) var removedIdentifiers: [String] = []
    private(set) var requestAuthorizationCallCount = 0

    init(authorizationStatus: UNAuthorizationStatus, requestAuthorizationResult: Result<Bool, Error> = .success(false)) {
        self.statusToReturn = authorizationStatus
        self.requestAuthorizationResult = requestAuthorizationResult
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        statusToReturn
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        requestAuthorizationCallCount += 1
        return try requestAuthorizationResult.get()
    }

    func add(_ request: UNNotificationRequest) async throws {
        addedRequests.append(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedIdentifiers.append(contentsOf: identifiers)
    }
}

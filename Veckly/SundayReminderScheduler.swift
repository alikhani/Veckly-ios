import Foundation
import UserNotifications

private let sundayReminderIdentifier = "veckly.sundayPlanningReminder"
private let lastCheckedDateKey = "veckly.sundayReminder.lastCheckedDate"

protocol SundayReminderNotifying {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
}

extension UNUserNotificationCenter: SundayReminderNotifying {
    func authorizationStatus() async -> UNAuthorizationStatus {
        await notificationSettings().authorizationStatus
    }
}

/// Schedules (or cancels) a single local notification for Sunday morning
/// nudging the household to plan next week — only when next week is
/// still empty. Calm by design (Plan B4):
/// - Checked at most once per calendar day (`lastCheckedDateKey`), not on
///   every app foreground.
/// - Only considered on weekend days — the same window the in-app
///   "weekend nudge" banner in `WeekTabView` already uses, so a permission
///   prompt (if one appears) always has the banner as visible context
///   rather than popping up out of nowhere on a random Tuesday.
/// - Permission is requested lazily, only the first time there's actually
///   something worth notifying about — never upfront at onboarding.
/// - One-shot (`repeats: false`): if the household hasn't planned by the
///   time it fires, it doesn't nag again until next weekend's check
///   reschedules it.
@MainActor
final class SundayReminderScheduler {
    /// Exposed so `AppNotificationDelegate` can recognize a tap on this
    /// specific reminder (vs. some other future notification) without a
    /// second copy of the raw identifier string.
    static let notificationIdentifier = sundayReminderIdentifier

    private let notificationCenter: any SundayReminderNotifying
    private let defaults: UserDefaults
    private let calendar: Calendar
    private let now: () -> Date

    init(
        notificationCenter: any SundayReminderNotifying = UNUserNotificationCenter.current(),
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.notificationCenter = notificationCenter
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
    }

    /// `nextWeekIsEmpty` is a closure (not a plain `Bool`) so the caller's
    /// network peek only runs when the throttle/weekday gate actually let
    /// this proceed — no wasted fetch on a weekday call.
    func refreshIfNeeded(nextWeekIsEmpty: () async -> Bool) async {
        let weekday = calendar.component(.weekday, from: now())
        guard weekday == 1 || weekday == 7 else { return }

        let today = calendar.startOfDay(for: now())
        if let last = defaults.object(forKey: lastCheckedDateKey) as? Date, calendar.isDate(last, inSameDayAs: today) {
            return
        }
        defaults.set(today, forKey: lastCheckedDateKey)

        guard await nextWeekIsEmpty() else {
            notificationCenter.removePendingNotificationRequests(withIdentifiers: [sundayReminderIdentifier])
            return
        }

        guard await isAuthorized() else { return }
        await schedule()
    }

    private func isAuthorized() async -> Bool {
        switch await notificationCenter.authorizationStatus() {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await notificationCenter.requestAuthorization(options: [.alert, .sound])) ?? false
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    private func schedule() async {
        var dateComponents = DateComponents()
        dateComponents.weekday = 1 // Sunday
        dateComponents.hour = 10
        dateComponents.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)

        let content = UNMutableNotificationContent()
        content.title = L10n.string("notification.sundayReminder.title")
        content.body = L10n.string("notification.sundayReminder.body")
        content.sound = .default

        let request = UNNotificationRequest(identifier: sundayReminderIdentifier, content: content, trigger: trigger)
        try? await notificationCenter.add(request)
    }
}

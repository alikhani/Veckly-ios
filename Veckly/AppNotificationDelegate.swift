import Foundation
import UserNotifications

/// The one adapter needed to turn a tap on the Sunday planning reminder (see
/// `SundayReminderScheduler`) into an in-app deep link. SwiftUI's `App`
/// protocol has no notification-response hook of its own, so this small
/// `NSObject` wrapper is registered as `UNUserNotificationCenter`'s delegate
/// from `AppModel.init` and forwards the "open next week" intent back into
/// `AppModel.pendingWeekPlanDeepLink`, which `WeekTabView` consumes once.
///
/// Before this existed, tapping the reminder just foregrounded the app with
/// no routing at all — the week view landed on whatever week was already in
/// memory (the just-completed current week), not the next week the
/// notification was actually about.
@MainActor
final class AppNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    var onSundayReminderTapped: (() -> Void)?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.notification.request.identifier == SundayReminderScheduler.notificationIdentifier else { return }
        onSundayReminderTapped?()
    }

    /// Without this, the reminder firing while the app is already in the
    /// foreground would be silently swallowed instead of shown as a banner.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

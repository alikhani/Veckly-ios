import EventKit
import Foundation

enum ShoppingListReminderExportError: Error, Equatable {
    case accessDenied
    case noReminderCalendar
}

@MainActor
final class ShoppingListReminderExporter {
    private let eventStore: EKEventStore

    init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
    }

    func export(items: [String], listTitle: String, notes: String?) async throws -> Int {
        guard !items.isEmpty else { return 0 }

        let granted = try await eventStore.requestFullAccessToReminders()
        guard granted else { throw ShoppingListReminderExportError.accessDenied }
        guard let calendar = eventStore.defaultCalendarForNewReminders() else {
            throw ShoppingListReminderExportError.noReminderCalendar
        }

        for item in items {
            let reminder = EKReminder(eventStore: eventStore)
            reminder.title = item
            reminder.calendar = calendar
            reminder.notes = [listTitle, notes].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
            try eventStore.save(reminder, commit: false)
        }

        try eventStore.commit()
        return items.count
    }
}

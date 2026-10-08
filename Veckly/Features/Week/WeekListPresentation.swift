import Foundation

enum WeekDayRowInteraction: Equatable {
    case none
    case viewRecipe
    case editDay
    case planDay
}

/// One presentation rule for empty and started weeks alike. Calendar position
/// decides whether a row is mutable; meal content only decides which action a
/// tap performs.
struct WeekListPresentation {
    let days: [WeekDayRowViewModel]
    let viewedWeekOffset: ViewedWeekOffset
    let includesWeekend: Bool

    var shouldCollapseWeekend: Bool {
        !includesWeekend && !weekendDays.isEmpty
    }

    var mainDays: [WeekDayRowViewModel] {
        guard shouldCollapseWeekend else { return days }
        return days.filter { !Self.isWeekend($0) }
    }

    var weekendDays: [WeekDayRowViewModel] {
        days.filter(Self.isWeekend)
    }

    func interaction(for day: WeekDayRowViewModel) -> WeekDayRowInteraction {
        if viewedWeekOffset == .last || (viewedWeekOffset == .current && day.isPast) {
            return day.recipe == nil ? .none : .viewRecipe
        }
        return day.recipe == nil ? .planDay : .editDay
    }

    private static func isWeekend(_ day: WeekDayRowViewModel) -> Bool {
        day.weekday == .saturday || day.weekday == .sunday
    }
}

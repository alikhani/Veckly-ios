import SwiftUI

enum WeekFillAction: Equatable {
    case firstSuggestion
    case openDays(Int)

    init(plannedDinnerCount: Int, openDayCount: Int) {
        self = plannedDinnerCount == 0 ? .firstSuggestion : .openDays(openDayCount)
    }

    var title: String {
        switch self {
        case .firstSuggestion:
            L10n.string("week.fill.firstSuggestion")
        case .openDays(let count):
            L10n.format(count == 1 ? "week.fill.openDays.one" : "week.fill.openDays.other", count)
        }
    }

    var progressTitle: String {
        switch self {
        case .firstSuggestion:
            L10n.string("week.fill.generatingFirst")
        case .openDays:
            L10n.string("week.fill.generatingOpenDays")
        }
    }
}

struct WeekFillCompletionNotice: Equatable {
    let reason: String

    static func make(
        before: [WeekDayRowViewModel],
        after: [WeekDayRowViewModel]
    ) -> WeekFillCompletionNotice? {
        let existingRecipeDays = Set(before.compactMap { day in
            day.recipe == nil ? nil : day.weekday
        })
        guard let explainedDay = after.first(where: { day in
            !existingRecipeDays.contains(day.weekday) && day.recipe != nil && day.reason != nil
        }), let reason = explainedDay.reason else { return nil }

        return WeekFillCompletionNotice(reason: "\(explainedDay.weekdayLabel): \(reason.label)")
    }
}

/// Replaces "Veckokoll" as the primary status surface under the hero
/// (Fas 3): either "X planning days left" with "Plan the rest" as the single
/// primary CTA, or "The week is planned" with "Open the shopping list".
/// `WeekQualityCard`-style insights (heavy week, low confidence) still
/// render separately, only when they carry an actual warning.
struct WeekPlanningStatusCard: View {
    let openDayCount: Int
    let isComplete: Bool
    let fillActionTitle: String
    let fillProgressTitle: String
    let isFilling: Bool
    let onPlanRest: () -> Void
    let onOpenShoppingList: () -> Void

    var body: some View {
        VecklyCard {
            VStack(alignment: .leading, spacing: 10) {
                if isComplete {
                    Label {
                        Text("week.status.complete.title")
                            .font(VecklyDesign.Typography.cardTitle)
                            .foregroundStyle(VecklyDesign.Colors.inkDeep)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(VecklyDesign.Colors.hearthOrangeFill)
                    }

                    // "Gör om veckan" (beslut 6's third CTA copy) moved out
                    // to `WeekTabView`'s toolbar menu (Fas C) — this card's
                    // one action, complete or not, is now always the page's
                    // single primary CTA.
                    Button("week.status.complete.cta", action: onOpenShoppingList)
                        .buttonStyle(VecklyPrimaryButtonStyle())
                        .padding(.top, 4)
                } else {
                    Text(L10n.format(openDayCount == 1 ? "week.status.daysLeft.one" : "week.status.daysLeft.other", openDayCount))
                        .font(VecklyDesign.Typography.cardTitle)
                        .foregroundStyle(VecklyDesign.Colors.inkDeep)

                    Button(action: onPlanRest) {
                        if isFilling {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .tint(.white)
                                Text(fillProgressTitle)
                            }
                        } else {
                            Text(fillActionTitle)
                        }
                    }
                        .buttonStyle(VecklyPrimaryButtonStyle())
                        .padding(.top, 4)
                        .disabled(isFilling)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier(isComplete ? "weekStatusComplete" : "weekStatusOpenDays")
    }
}

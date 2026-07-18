import SwiftUI

/// Replaces "Veckokoll" as the primary status surface under the hero
/// (Fas 3): either "X planning days left" with "Plan the rest" as the single
/// primary CTA, or "The week is planned" with "Open the shopping list".
/// `WeekQualityCard`-style insights (heavy week, low confidence) still
/// render separately, only when they carry an actual warning.
struct WeekPlanningStatusCard: View {
    let openDayCount: Int
    let isComplete: Bool
    let onPlanRest: () -> Void
    let onOpenShoppingList: () -> Void
    /// Full "redo the week" (beslut 6's third CTA copy) previously lived
    /// only in `WeekTabView`'s toolbar — Fas 5 moves the toolbar down to
    /// refresh-only, so the complete-week state needs a home for it here,
    /// as a secondary action below the primary "Open the shopping list".
    let onRegenerate: () -> Void

    var body: some View {
        VecklyCard {
            VStack(alignment: .leading, spacing: 10) {
                if isComplete {
                    Label {
                        Text("week.status.complete.title")
                            .font(VecklyDesign.Typography.displayHeading(size: 20))
                            .foregroundStyle(VecklyDesign.Colors.inkDeep)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(VecklyDesign.Colors.hearthOrange)
                    }

                    Button("week.status.complete.cta", action: onOpenShoppingList)
                        .buttonStyle(VecklyPrimaryButtonStyle())
                        .padding(.top, 4)

                    Button("week.regenerate", action: onRegenerate)
                        .buttonStyle(.bordered)
                        .tint(VecklyDesign.Colors.inkMid)
                        .accessibilityIdentifier("weekRegenerateButton")
                } else {
                    Text(L10n.format(openDayCount == 1 ? "week.status.daysLeft.one" : "week.status.daysLeft.other", openDayCount))
                        .font(VecklyDesign.Typography.displayHeading(size: 20))
                        .foregroundStyle(VecklyDesign.Colors.inkDeep)

                    Button("week.generateRest", action: onPlanRest)
                        .buttonStyle(VecklyPrimaryButtonStyle())
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier(isComplete ? "weekStatusComplete" : "weekStatusOpenDays")
    }
}

import SwiftUI

/// The "nothing planned yet" card — for an empty current week and, with
/// forward-looking copy, an empty next week (instead of "Tonight" framing
/// that doesn't apply there). Choosing the first dinner is primary; filling
/// the week and starting from last week are quieter alternatives.
struct WeekEmptyStateCard: View {
    let eyebrow: LocalizedStringKey
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let fillActionTitle: String
    let canChooseFirstDinner: Bool
    let canFill: Bool
    let canStartFromLastWeek: Bool
    let onChooseFirstDinner: () -> Void
    let onFill: () -> Void
    let onStartFromLastWeek: () -> Void

    var body: some View {
        VecklyCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(eyebrow)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VecklyDesign.Colors.inkFaint)
                    .textCase(.uppercase)

                Text(title)
                    .font(VecklyDesign.Typography.cardTitle)
                    .foregroundStyle(VecklyDesign.Colors.inkDeep)

                Text(message)
                    .font(.body)
                    .foregroundStyle(VecklyDesign.Colors.inkMid)

                Button("week.empty.chooseFirst") {
                    onChooseFirstDinner()
                }
                .buttonStyle(VecklyPrimaryButtonStyle())
                .padding(.top, 4)
                .disabled(!canChooseFirstDinner)

                Button(fillActionTitle) {
                    onFill()
                }
                .disabled(!canFill)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(VecklyDesign.Colors.hearthOrangeText)
                .frame(maxWidth: .infinity)

                Button("previousWeek.action") {
                    onStartFromLastWeek()
                }
                .disabled(!canStartFromLastWeek)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(VecklyDesign.Colors.inkMid)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A compact, action-free summary of a browsed week: Next week once it has
/// a plan, or any state of Last week. No "Tonight" framing — there's no
/// today in these weeks.
struct WeekSummaryCard: View {
    let eyebrow: String
    let eyebrowColor: Color
    let summaryLine: String

    var body: some View {
        VecklyCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(eyebrow)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(eyebrowColor)
                    .textCase(.uppercase)
                Text(summaryLine)
                    .font(VecklyDesign.Typography.cardTitle)
                    .foregroundStyle(VecklyDesign.Colors.inkDeep)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

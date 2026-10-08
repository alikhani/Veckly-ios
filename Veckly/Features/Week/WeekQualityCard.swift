import SwiftUI

/// One concrete, reviewable improvement to the viewed week (an open day,
/// leftovers, a quicker/easier/varied dinner), confirmed before applying.
struct WeekQualityCard: View {
    let suggestion: WeekQualitySuggestion
    @Binding var isConfirming: Bool
    let onDismiss: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("week.quality.suggestion.title")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(VecklyDesign.Colors.inkFaint)
                        .textCase(.uppercase)
                    Spacer()
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.string("week.quality.suggestion.dismiss"))
                }

                Label(reason, systemImage: icon)
                    .font(.subheadline)
                    .foregroundStyle(VecklyDesign.Colors.inkMid)

                VStack(alignment: .leading, spacing: 5) {
                    Text(before)
                        .font(.subheadline)
                        .foregroundStyle(VecklyDesign.Colors.inkFaint)
                    Label(after, systemImage: "arrow.down")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(VecklyDesign.Colors.inkDeep)
                }

                Button(actionTitle) {
                    isConfirming = true
                }
                .buttonStyle(.borderedProminent)
                .tint(VecklyDesign.Colors.hearthOrangePrimaryFill)
                .accessibilityIdentifier("weekQualitySuggestionAction")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .confirmationDialog(
            L10n.string("week.quality.suggestion.confirmTitle"),
            isPresented: $isConfirming,
            titleVisibility: .visible
        ) {
            Button(confirmTitle) {
                onConfirm()
            }
            Button(L10n.string("common.cancel"), role: .cancel) {}
        } message: {
            Text("\(before)\n\(after)")
        }
    }

    private var icon: String {
        switch suggestion.kind {
        case .fillOpenDay: "calendar.badge.plus"
        case .useLeftovers: "arrow.3.trianglepath"
        case .makeQuicker: "clock.arrow.circlepath"
        case .makeEasier: "basket"
        case .addVariation: "arrow.2.squarepath"
        }
    }

    private var reason: String {
        switch suggestion.kind {
        case .fillOpenDay:
            L10n.format("week.quality.suggestion.reason.open", suggestion.day.weekdayLabel)
        case .useLeftovers:
            L10n.format("week.quality.suggestion.reason.leftovers", suggestion.day.weekdayLabel)
        case .makeQuicker:
            L10n.format("week.quality.suggestion.reason.quicker", suggestion.day.weekdayLabel)
        case .makeEasier:
            L10n.format("week.quality.suggestion.reason.easier", suggestion.day.weekdayLabel)
        case .addVariation:
            L10n.format("week.quality.suggestion.reason.variation", suggestion.day.weekdayLabel)
        }
    }

    private var before: String {
        let meal = suggestion.day.recipe?.title ?? L10n.string("week.quality.suggestion.openDay")
        return L10n.format("week.quality.suggestion.before", suggestion.day.weekdayLabel, meal)
    }

    private var after: String {
        if suggestion.kind == .useLeftovers, let source = suggestion.sourceDay, let recipe = source.recipe {
            return L10n.format("week.quality.suggestion.afterLeftovers", recipe.title, source.weekdayLabel)
        }
        return L10n.format(
            "week.quality.suggestion.after",
            suggestion.replacement?.title ?? L10n.string("week.quality.suggestion.openDay")
        )
    }

    private var actionTitle: LocalizedStringKey {
        suggestion.kind == .useLeftovers
            ? "week.quality.suggestion.reviewLeftovers"
            : "week.quality.suggestion.reviewSwap"
    }

    private var confirmTitle: String {
        suggestion.kind == .useLeftovers
            ? L10n.string("week.quality.suggestion.confirmLeftovers")
            : L10n.string("week.quality.suggestion.confirmSwap")
    }
}

/// Why this week looks the way it does: up to two generator explanations
/// plus the household's pulse wishes.
struct WeekExplanationSummary: View {
    let summary: WeekSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("week.explanation.title", systemImage: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(VecklyDesign.Colors.inkFaint)
                .textCase(.uppercase)

            ForEach(Array(summary.explanations.prefix(2).enumerated()), id: \.offset) { _, explanation in
                Text(explanation.sentence)
                    .font(.subheadline)
                    .foregroundStyle(VecklyDesign.Colors.inkMid)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(summary.pulse?.wishes ?? []) { wish in
                Text(wish.sentence)
                    .font(.subheadline)
                    .foregroundStyle(VecklyDesign.Colors.inkMid)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }
}

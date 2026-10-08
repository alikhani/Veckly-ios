import SwiftUI

/// The week list — every relevant day, in order, with no holes (beslut 3).
/// Weekend days are the one exception, moved to `WeekCollapsedWeekendSection`
/// when the household doesn't plan them.
struct WeekDayList: View {
    let days: [WeekDayRowViewModel]
    let row: (WeekDayRowViewModel) -> CompactDayRow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("week.section")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(VecklyDesign.Colors.inkFaint)
                .padding(.bottom, 4)

            ForEach(days) { day in
                row(day)
                if day.id != days.last?.id {
                    Divider().padding(.leading, 56)
                }
            }
        }
        .accessibilityIdentifier("weekPlanList")
    }
}

/// Beslut 8: a disclosure the household can open to plan an optional
/// weekend day without it affecting scope, the status card, or the hero.
struct WeekCollapsedWeekendSection: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let days: [WeekDayRowViewModel]
    @Binding var isExpanded: Bool
    let row: (WeekDayRowViewModel) -> CompactDayRow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Text(isExpanded ? "week.hideWeekend" : "week.showWeekend")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(VecklyDesign.Colors.hearthOrangeText)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(VecklyDesign.Colors.hearthOrangeFill)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    Spacer()
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("weekendToggle")

            if isExpanded {
                ForEach(days) { day in
                    row(day)
                    if day.id != days.last?.id {
                        Divider().padding(.leading, 56)
                    }
                }
            }
        }
    }
}

struct CompactDayRow: View {
    let day: WeekDayRowViewModel
    var coverage: PrepBatchCoverage? = nil
    /// Purely informational "I dag" chip — shown whenever this is literally
    /// today's row, independent of whether the hero happens to be showing
    /// today too. Informational redundancy between hero and list is
    /// intentional (beslut 3); only action redundancy is forbidden.
    var isTodayBadge: Bool = false
    /// True when the hero card above is already showing this exact day —
    /// only then does the row give up its tap target and trailing "Plan"
    /// hint, so the hero's actions are never duplicated (beslut 3).
    var isHeroOwned: Bool = false
    var interaction: WeekDayRowInteraction = .editDay
    let onTap: () -> Void

    var body: some View {
        Group {
            if isHeroOwned || interaction == .none {
                rowContent
                    .accessibilityElement(children: .combine)
            } else {
                Button(action: onTap) {
                    rowContent
                }
                .buttonStyle(.plain)
            }
        }
        .opacity(isDimmed ? 0.7 : 1)
    }

    private var isDimmed: Bool { day.isPast || isHeroOwned }

    private var rowContent: some View {
        HStack(alignment: .center, spacing: 12) {
            dateColumn

            if isTodayBadge {
                todayBadge
            }

            if day.isSkipped {
                skippedContent
            } else if day.isEmpty {
                emptyContent
            } else {
                plannedContent
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var todayBadge: some View {
        Text("meal.today")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(VecklyDesign.Colors.hearthOrangeText)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(Capsule().stroke(VecklyDesign.Colors.hearthOrangeText, lineWidth: 1))
            .fixedSize()
    }

    private var dateColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(day.weekday.shortDisplayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(day.isToday ? VecklyDesign.Colors.hearthOrangeText : VecklyDesign.Colors.inkMid)
            Text(day.dateLabel)
                .font(.caption2)
                .foregroundStyle(VecklyDesign.Colors.inkFaint)
        }
        .frame(width: 44, alignment: .leading)
    }

    private var plannedContent: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(day.mealTitle)
                    .font(.body.weight(.medium))
                    .foregroundStyle(VecklyDesign.Colors.inkDeep)
                    .lineLimit(1)
                if let reason = day.reason {
                    Text(reason.label)
                        .font(.caption2)
                        .foregroundStyle(VecklyDesign.Colors.inkFaint)
                        .lineLimit(1)
                }
            }
            Spacer()
            if day.recipe == nil, let _ = coverage {
                Label(L10n.string("prep.fallbackTitle"), systemImage: "arrow.3.trianglepath")
                    .font(.caption)
                    .foregroundStyle(VecklyDesign.Colors.inkMid)
                    .accessibilityLabel(L10n.string("accessibility.coveredByLeftovers"))
            }
            if day.isLocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(VecklyDesign.Colors.hearthOrangeFill)
                    .accessibilityLabel(L10n.string("accessibility.locked"))
            }
        }
    }

    private var emptyContent: some View {
        HStack(alignment: .center, spacing: 8) {
            if let coverage {
                Image(systemName: "arrow.3.trianglepath")
                    .font(.system(size: 12))
                    .foregroundStyle(VecklyDesign.Colors.inkMid)
                    .accessibilityLabel(L10n.string("accessibility.coveredByLeftovers"))
                Text(coverage.recipeTitle)
                    .font(.body.weight(.medium))
                    .foregroundStyle(VecklyDesign.Colors.inkDeep)
                    .lineLimit(1)
            } else {
                Text("meal.addDinner")
                    .font(.body.italic())
                    .foregroundStyle(VecklyDesign.Colors.inkFaint)
            }
            Spacer()
            if interaction == .planDay && !isHeroOwned {
                Text("meal.plan")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(VecklyDesign.Colors.hearthOrangeText)
            }
        }
    }

    /// A skipped day keeps its assigned meal (see `WeekDayRowViewModel.withSkipped`)
    /// so it's shown here, dimmed, alongside a "Skipped" badge — instead of a
    /// blank row that would make un-skipping look like it lost the plan.
    private var skippedContent: some View {
        HStack(alignment: .center, spacing: 8) {
            if !day.mealTitle.isEmpty {
                Text(day.mealTitle)
                    .font(.body.weight(.medium))
                    .foregroundStyle(VecklyDesign.Colors.inkFaint)
                    .lineLimit(1)
                    .strikethrough(color: VecklyDesign.Colors.inkFaint)
            }
            Text("meal.skipped")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(VecklyDesign.Colors.inkFaint)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(VecklyDesign.Colors.surfaceStrong)
                .clipShape(Capsule())
            Spacer()
            if interaction == .editDay && !isHeroOwned {
                Text("meal.plan")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(VecklyDesign.Colors.hearthOrangeText)
            }
        }
        .opacity(0.7)
    }
}

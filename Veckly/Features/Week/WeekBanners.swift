import SwiftUI

/// Shown for a few seconds after "Regenerate" so the previous plan can be
/// put back.
struct WeekRegenerateUndoBanner: View {
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("week.regenerate.undoBanner")
                .font(.subheadline)
                .foregroundStyle(.white)
            Spacer()
            Button(L10n.string("common.undo")) {
                onUndo()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(VecklyDesign.Colors.hearthOrangeTextDark)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(VecklyDesign.Colors.toastSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }
}

/// Why the week just got filled the way it did — one concrete reason.
struct WeekFillCompletionBanner: View {
    let notice: WeekFillCompletionNotice

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("week.fill.success", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(VecklyDesign.Colors.inkDeep)

            Text(notice.reason)
                .font(.subheadline)
                .foregroundStyle(VecklyDesign.Colors.inkMid)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(VecklyDesign.Colors.surfaceStrong)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("weekFillCompletion")
    }
}

/// Weekend-only nudge to plan next week while it's still empty; dismissible
/// for the rest of the day.
struct WeekendNudgeBanner: View {
    let onPlanNextWeek: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("week.weekendNudge.title")
                .font(.subheadline)
                .foregroundStyle(VecklyDesign.Colors.inkDeep)
            Spacer()
            Button("week.weekendNudge.cta") {
                onPlanNextWeek()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(VecklyDesign.Colors.hearthOrangeText)
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VecklyDesign.Colors.inkMid)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(L10n.string("common.dismiss"))
        }
        .padding(12)
        .background(VecklyDesign.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// "Veckan är klar" — a one-time, dismissible beat shown the moment the
/// last empty day of the current week gets filled or skipped (see
/// `WeekScreenModel.checkForSessionEnd`). Not persisted anywhere: scoped to
/// this session, gone once dismissed or a CTA is tapped.
struct WeekSessionEndCard: View {
    let summary: WeekSessionSummary
    let showsInviteNudge: Bool
    let onDismiss: () -> Void
    let onOpenShoppingList: () -> Void
    let onInvitePartner: () -> Void

    var body: some View {
        VecklyCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("week.sessionEnd.title")
                        .font(VecklyDesign.Typography.cardTitle)
                        .foregroundStyle(VecklyDesign.Colors.inkDeep)
                    Spacer()
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(VecklyDesign.Colors.inkMid)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(L10n.string("common.dismiss"))
                }

                Text(L10n.format(summary.plannedDinnerCount == 1 ? "week.summary.plannedDinners.one" : "week.summary.plannedDinners.other", summary.plannedDinnerCount))
                    .font(.body.weight(.medium))
                    .foregroundStyle(VecklyDesign.Colors.inkMid)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(summaryRows.enumerated()), id: \.offset) { _, row in
                        Label {
                            Text(verbatim: row.text)
                                .font(.subheadline)
                                .foregroundStyle(VecklyDesign.Colors.inkMid)
                        } icon: {
                            Image(systemName: row.icon)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(VecklyDesign.Colors.hearthOrangeFill)
                        }
                    }
                }
                .padding(.top, 2)

                Button("week.sessionEnd.cta") {
                    onOpenShoppingList()
                }
                .buttonStyle(VecklyPrimaryButtonStyle())
                .padding(.top, 4)

                if showsInviteNudge {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("week.sessionEnd.inviteHint")
                            .font(.footnote)
                            .foregroundStyle(VecklyDesign.Colors.inkMid)
                        Button("week.sessionEnd.inviteCta") {
                            onInvitePartner()
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(VecklyDesign.Colors.hearthOrangeText)
                    }
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var summaryRows: [(icon: String, text: String)] {
        var rows: [(icon: String, text: String)] = []
        if summary.quickDinnerCount > 0 {
            rows.append((
                icon: "clock",
                text: L10n.format(summary.quickDinnerCount == 1 ? "week.sessionEnd.quick.one" : "week.sessionEnd.quick.other", summary.quickDinnerCount)
            ))
        }
        if summary.prepFriendlyDinnerCount > 0 {
            rows.append((
                icon: "takeoutbag.and.cup.and.straw",
                text: L10n.format(summary.prepFriendlyDinnerCount == 1 ? "week.sessionEnd.prep.one" : "week.sessionEnd.prep.other", summary.prepFriendlyDinnerCount)
            ))
        }
        rows.append((icon: "cart", text: L10n.string("week.sessionEnd.shoppingReady")))
        return rows
    }
}

/// Quiet note while week changes made offline wait to sync.
struct WeekPendingSyncNote: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(L10n.string("week.sync.pending"))
                .font(.caption)
                .foregroundStyle(VecklyDesign.Colors.inkMid)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }
}

import SwiftUI

/// Household name, week title/date and the last/this/next week picker —
/// extracted from `WeekTabView` (Fas 3) so the top-of-page chrome isn't
/// interleaved with hero/list logic. Purely presentational: week navigation
/// state is owned by the caller via bindings.
struct WeekHeaderView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let householdName: String
    @Binding var viewedWeekOffset: ViewedWeekOffset
    @Binding var isWeekPickerPresented: Bool
    /// Called after `viewedWeekOffset` has already been updated, so the
    /// caller can reload the newly-selected week.
    let onSelectWeek: (ViewedWeekOffset) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(householdName)
                .font(.subheadline)
                .foregroundStyle(VecklyDesign.Colors.hearthOrangeText)
                .textCase(.uppercase)

            Button {
                isWeekPickerPresented = true
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(L10n.string(viewedWeekOffset.relativeLabelKey))
                        .font(VecklyDesign.Typography.displayHeading(size: 34))
                        .foregroundStyle(VecklyDesign.Colors.inkDeep)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(VecklyDesign.Colors.inkMid)
                        .rotationEffect(.degrees(isWeekPickerPresented ? 180 : 0))
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: isWeekPickerPresented)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(weekPickerTriggerAccessibilityLabel)
            .accessibilityHint(L10n.string("week.picker.hint"))
            .popover(isPresented: $isWeekPickerPresented, attachmentAnchor: .point(.bottomLeading), arrowEdge: .top) {
                weekPickerMenu
                    .presentationCompactAdaptation(.popover)
            }

            Text(viewedWeekOffset.subtitleLabel())
                .font(.subheadline)
                .foregroundStyle(VecklyDesign.Colors.inkFaint)
        }
    }

    private var weekPickerTriggerAccessibilityLabel: String {
        "\(L10n.string(viewedWeekOffset.relativeLabelKey)), \(viewedWeekOffset.subtitleLabel())"
    }

    private var weekPickerMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(ViewedWeekOffset.allCases) { offset in
                Button {
                    viewedWeekOffset = offset
                    isWeekPickerPresented = false
                    onSelectWeek(offset)
                } label: {
                    weekPickerRow(for: offset)
                }
                .buttonStyle(.plain)

                if offset != ViewedWeekOffset.allCases.last {
                    Divider()
                }
            }
        }
        .frame(width: 260)
        .padding(.vertical, 4)
    }

    private func weekPickerRow(for offset: ViewedWeekOffset) -> some View {
        let isSelected = offset == viewedWeekOffset
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(L10n.string(offset.relativeLabelKey))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(VecklyDesign.Colors.inkDeep)
                    if offset.isViewOnly {
                        Text("week.viewOnly")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(VecklyDesign.Colors.inkFaint)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(VecklyDesign.Colors.surfaceStrong)
                            .clipShape(Capsule())
                    }
                }
                Text(offset.subtitleLabel())
                    .font(.caption)
                    .foregroundStyle(VecklyDesign.Colors.inkFaint)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(VecklyDesign.Colors.hearthOrangeFill)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            offset.isViewOnly
                ? "\(L10n.string(offset.relativeLabelKey)), \(offset.subtitleLabel()), \(L10n.string("week.viewOnly"))"
                : "\(L10n.string(offset.relativeLabelKey)), \(offset.subtitleLabel())"
        )
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

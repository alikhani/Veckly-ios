import SwiftUI

/// Shown when the list has nothing to buy: either the week plan exists but
/// every meal is skipped/unassigned, or there is no week plan at all.
struct ShoppingEmptyStateCard: View {
    let hasWeekPlan: Bool
    let onGoToWeekTab: (() -> Void)?

    var body: some View {
        if hasWeekPlan {
            // Week plan exists but all meals are skipped/unassigned.
            VecklyCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.string("shopping.noMeals.title"))
                        .font(.headline)
                    if let onGoToWeekTab {
                        Button(L10n.string("shopping.noMeals.action"), action: onGoToWeekTab)
                            .buttonStyle(VecklyPrimaryButtonStyle())
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            // No week plan at all.
            VecklyCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.string("shopping.empty.title"))
                        .font(.headline)
                    Text(L10n.string("shopping.empty.message"))
                        .foregroundStyle(VecklyDesign.Colors.inkMid)
                    if let onGoToWeekTab {
                        Button("week.empty.primary", action: onGoToWeekTab)
                            .buttonStyle(VecklyPrimaryButtonStyle())
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// "3 / 7" progress, with a small spinner while checks are still syncing.
struct ShoppingProgressRow: View {
    let checkedItemCount: Int
    let totalItemCount: Int
    let showsPendingSync: Bool

    var body: some View {
        HStack(spacing: 10) {
            ProgressView(value: Double(checkedItemCount), total: Double(totalItemCount))
                .tint(VecklyDesign.Colors.hearthOrangeFill)
            Text("\(checkedItemCount) / \(totalItemCount)")
                .font(.caption)
                .foregroundStyle(VecklyDesign.Colors.inkMid)
                .monospacedDigit()
            ProgressView()
                .controlSize(.small)
                .frame(width: 18, height: 18)
                .opacity(showsPendingSync ? 1 : 0)
                .accessibilityHidden(!showsPendingSync)
                .accessibilityLabel(pendingSyncMessage)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.format("accessibility.itemsChecked", checkedItemCount, totalItemCount))
        .accessibilityValue(showsPendingSync ? pendingSyncMessage : "")
    }

    private var pendingSyncMessage: String {
        L10n.string("shopping.sync.pending")
    }
}

/// The "Items cleared · Undo" toast after "Clear checked".
struct ShoppingClearedToast: View {
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Text(L10n.string("shopping.itemsCleared"))
                .font(.subheadline)
                .foregroundStyle(.white)
            Spacer()
            Button(L10n.string("common.undo")) {
                onUndo()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(VecklyDesign.Colors.hearthOrangeTextDark)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(VecklyDesign.Colors.toastSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }
}

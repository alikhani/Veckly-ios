import SwiftUI

/// The Shopping tab's header: week context line, the three secondary
/// actions (store order, share, add item) and the screen title.
struct ShoppingHeader: View {
    let contextLine: String?
    let hasReminderItems: Bool
    let remindersExportButtonLabel: String
    let isExportingReminders: Bool
    let shareText: String?
    let onExportToReminders: () -> Void
    let onAddItem: () -> Void
    let onArrangeCategories: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Fas F: at accessibility Dynamic Type sizes the share/add
            // buttons grow enough to squeeze `weekContextLine` down to
            // an unreadable sliver (`minimumScaleFactor` alone can't
            // save it) — verified with a screenshot at
            // `.accessibilityExtraExtraExtraLarge`. Giving the context
            // line its own row at those sizes, instead of fighting the
            // buttons for space in one line, fixes it without
            // affecting the normal-size layout at all.
            if dynamicTypeSize.isAccessibilitySize {
                if let contextLine {
                    Text(contextLine)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(VecklyDesign.Colors.hearthOrangeText)
                }
                HStack(spacing: 12) {
                    Spacer(minLength: 0)
                    categoryOrderButton
                    shareMenu
                    addItemButton
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    if let contextLine {
                        Text(contextLine)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(VecklyDesign.Colors.hearthOrangeText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .layoutPriority(-1)
                    }
                    Spacer()
                    categoryOrderButton
                    shareMenu
                    addItemButton
                }
            }

            Text(L10n.string("shopping.title"))
                .font(VecklyDesign.Typography.screenTitle)
                .foregroundStyle(VecklyDesign.Colors.inkDeep)

        }
    }

    @ViewBuilder
    private var shareMenu: some View {
        if hasReminderItems {
            Menu {
                Button {
                    onExportToReminders()
                } label: {
                    Label(remindersExportButtonLabel, systemImage: "checklist")
                }
                .disabled(isExportingReminders)

                if let shareText {
                    ShareLink(item: shareText) {
                        Label(L10n.string("shopping.share.textFallback"), systemImage: "square.and.arrow.up")
                    }
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.callout.weight(.semibold))
                    // No explicit frame here: sizing purely from
                    // the font (matching "Lägg till vara"'s Label
                    // font below) is what makes both buttons come
                    // out the same height under the same button
                    // style. A fixed frame on just this icon used
                    // to override that and make the share button
                    // visibly taller than its neighbor.
                    .frame(minWidth: 20)
            }
            .buttonStyle(.bordered)
            .tint(VecklyDesign.Colors.inkMid)
            .accessibilityLabel(L10n.string("shopping.share.action"))
        }
    }

    private var addItemButton: some View {
        Button {
            onAddItem()
        } label: {
            ViewThatFits(in: .horizontal) {
                addOwnItemButtonContent(L10n.string("shopping.customItem.addButton"))
                addOwnItemButtonContent(L10n.string("shopping.customItem.add"))
                Image(systemName: "plus")
                    .font(.callout.weight(.semibold))
                    .frame(minWidth: 20, minHeight: 24, alignment: .center)
            }
        }
        // Bordered, not `.borderedProminent` (Fas D): checking
        // items off is the screen's actual job, so adding a
        // new item shouldn't outweigh it visually — same
        // secondary vocabulary as the share button next to it.
        .buttonStyle(.bordered)
        .tint(VecklyDesign.Colors.inkMid)
        .layoutPriority(1)
        .accessibilityLabel(L10n.string("shopping.customItem.add"))
    }

    private var categoryOrderButton: some View {
        Button { onArrangeCategories() } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.callout.weight(.semibold))
                .frame(minWidth: 20, minHeight: 24)
        }
        .buttonStyle(.bordered)
        .tint(VecklyDesign.Colors.inkMid)
        .accessibilityLabel(L10n.string("shopping.categoryOrder.action"))
    }

    private func addOwnItemButtonContent(_ title: String) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "plus")
            Text(title)
                .lineLimit(1)
        }
        .font(.callout.weight(.semibold))
        .fixedSize(horizontal: true, vertical: false)
    }
}

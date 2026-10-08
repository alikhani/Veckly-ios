import SwiftUI

struct ShoppingGroupView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let group: ShoppingListGroup
    let checkedItems: Set<String>
    let onToggle: (String) -> Void
    let onRemoveCustom: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ShoppingCategory.from(group.category).displayLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(VecklyDesign.Colors.inkMid)
                .textCase(.uppercase)

            VecklyCard {
                VStack(spacing: 0) {
                    ForEach(group.items) { item in
                        let isChecked = checkedItems.contains(item.itemKey)
                        let amountLabel = [item.amount, item.unit].compactMap { $0 }.joined(separator: " ")
                        HStack {
                            Button {
                                onToggle(item.itemKey)
                            } label: {
                                HStack {
                                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isChecked ? VecklyDesign.Colors.hearthOrangeFill : VecklyDesign.Colors.inkFaint)
                                    .contentTransition(.symbolEffect(.replace))
                                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: isChecked)
                                Text(item.label)
                                    .strikethrough(isChecked)
                                    .foregroundStyle(isChecked ? VecklyDesign.Colors.inkFaint : VecklyDesign.Colors.inkDeep)
                                Spacer()
                                if !amountLabel.isEmpty {
                                    Text(amountLabel)
                                        .foregroundStyle(VecklyDesign.Colors.inkFaint)
                                }
                                }
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(item.label)\(amountLabel.isEmpty ? "" : ", \(amountLabel)"), \(isChecked ? L10n.string("shopping.item.checked") : L10n.string("shopping.item.unchecked"))")
                            if item.isCustom {
                                Button(role: .destructive) {
                                    onRemoveCustom(item.itemKey)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(VecklyDesign.Colors.inkFaint)
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(L10n.format("accessibility.removeCustomItem", item.label))
                            }
                        }
                    }
                }
            }
        }
    }
}

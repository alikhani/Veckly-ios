import SwiftUI

struct StaplesGroupView: View {
    let items: [ShoppingListItem]
    let checkedItems: Set<String>
    let onToggle: (String) -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack {
                    Text("shopping.likelyAtHome")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(VecklyDesign.Colors.inkMid)
                        .textCase(.uppercase)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(VecklyDesign.Colors.inkFaint)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VecklyCard {
                    VStack(spacing: 0) {
                        ForEach(items) { item in
                            let isChecked = checkedItems.contains(item.itemKey)
                            Button {
                                onToggle(item.itemKey)
                            } label: {
                                HStack {
                                    Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(isChecked ? VecklyDesign.Colors.hearthOrangeFill : VecklyDesign.Colors.inkFaint)
                                        .font(.body)
                                    Text(item.label)
                                        .strikethrough(isChecked)
                                        .foregroundStyle(VecklyDesign.Colors.inkFaint)
                                    Spacer()
                                }
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(item.label), \(isChecked ? L10n.string("shopping.item.checked") : L10n.string("shopping.item.unchecked"))")
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.string(isExpanded ? "shopping.staples.expanded" : "shopping.staples.collapsed"))
    }
}

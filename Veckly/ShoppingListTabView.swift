import SwiftUI

struct ShoppingListTabView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Shopping list")
                    .font(.system(size: 34, weight: .bold, design: .serif))
                    .foregroundStyle(VecklyDesign.Colors.inkDeep)

                if appModel.shoppingListStore.isLoading {
                    LoadingPanel(title: "Loading shopping list")
                } else if let errorMessage = appModel.shoppingListStore.errorMessage {
                    ErrorPanel(message: errorMessage) {
                        Task { await appModel.loadCoreReader() }
                    }
                } else if appModel.shoppingListStore.groups.isEmpty {
                    EmptyPanel(title: "Nothing to buy yet", message: "Lock in a week plan and the grouped list will appear here.")
                } else {
                    ForEach(appModel.shoppingListStore.groups) { group in
                        ShoppingGroupView(
                            group: group,
                            checkedItems: appModel.shoppingListStore.checkedItems,
                            onToggle: { key in
                                Task { await appModel.shoppingListStore.toggleItem(key: key) }
                            }
                        )
                    }
                }
            }
            .padding(18)
            .accessibilityIdentifier("shoppingList")
        }
        .background(VecklyDesign.Colors.canvas)
        .navigationTitle("Shopping")
    }
}

struct ShoppingGroupView: View {
    let group: ShoppingListGroup
    let checkedItems: Set<String>
    let onToggle: (String) -> Void

    private var sortedItems: [ShoppingListItem] {
        group.items.sorted { a, b in
            let aChecked = checkedItems.contains(a.itemKey)
            let bChecked = checkedItems.contains(b.itemKey)
            if aChecked == bChecked { return false }
            return !aChecked
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(group.category)
                .font(.caption.weight(.semibold))
                .foregroundStyle(VecklyDesign.Colors.hearthOrange)
                .textCase(.uppercase)

            VecklyCard {
                VStack(spacing: 0) {
                    ForEach(sortedItems) { item in
                        let isChecked = checkedItems.contains(item.itemKey)
                        Button {
                            onToggle(item.itemKey)
                        } label: {
                            HStack {
                                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isChecked ? VecklyDesign.Colors.hearthOrange : VecklyDesign.Colors.inkFaint)
                                Text(item.label)
                                    .strikethrough(isChecked)
                                    .foregroundStyle(isChecked ? VecklyDesign.Colors.inkFaint : VecklyDesign.Colors.inkDeep)
                                Spacer()
                                Text([item.amount, item.unit].compactMap { $0 }.joined(separator: " "))
                                    .foregroundStyle(VecklyDesign.Colors.inkFaint)
                            }
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: checkedItems)
            }
        }
    }
}

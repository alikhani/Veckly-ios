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
                        ShoppingGroupView(group: group)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(group.category)
                .font(.caption.weight(.semibold))
                .foregroundStyle(VecklyDesign.Colors.hearthOrange)
                .textCase(.uppercase)

            VecklyCard {
                VStack(spacing: 0) {
                    ForEach(group.items) { item in
                        HStack {
                            Image(systemName: item.checked ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(item.checked ? VecklyDesign.Colors.hearthOrange : VecklyDesign.Colors.inkFaint)
                            Text(item.label)
                                .strikethrough(item.checked)
                            Spacer()
                            Text([item.amount, item.unit].compactMap { $0 }.joined(separator: " "))
                                .foregroundStyle(VecklyDesign.Colors.inkFaint)
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
    }
}

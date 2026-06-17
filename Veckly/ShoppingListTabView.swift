import SwiftUI

struct ShoppingListTabView: View {
    @Environment(AppModel.self) private var appModel
    @State private var showPrepSheet = false

    /// Base recipe servings are baked into the shopping list items by the backend.
    /// The backend stores raw ingredient amounts (no household scaling), so we scale
    /// on the client using the same factor as RecipeDetailView.
    ///
    /// The shopping list aggregates ingredients across multiple recipes that may each
    /// have different base servings. Because each item's `amount` was written from a
    /// specific recipe's ingredient row, they share the same base servings context.
    /// For simplicity (and because most households plan one recipe per day from a
    /// standard 4-serving base), we apply one global factor: householdSize / 4.
    /// If the profile isn't loaded, factor is 1.0 (no change).
    private var shoppingScaleFactor: Double {
        guard let hid = appModel.householdStore.activeHousehold?.id,
              let profile = appModel.householdStore.cachedProfile(for: hid) else { return 1.0 }
        let householdSize = profile.adults + profile.children
        // Shopping list backend uses raw recipe ingredient amounts; recipes default to 4 servings.
        return IngredientScaler.scaleFactor(householdSize: householdSize, recipeServings: 4)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Shopping list")
                    .font(VecklyDesign.Typography.displayHeading(size: 34))
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
                            scaleFactor: shoppingScaleFactor,
                            onToggle: { key in
                                Task { await appModel.shoppingListStore.toggleItem(key: key) }
                            }
                        )
                    }
                }

                PrepBatchSection(showPrepSheet: $showPrepSheet)
            }
            .padding(18)
            .accessibilityIdentifier("shoppingList")
        }
        .background(VecklyDesign.Colors.canvas)
        .navigationTitle("Shopping")
        .sheet(isPresented: $showPrepSheet) {
            PrepBatchFormSheet()
        }
        .task {
            guard let household = appModel.householdStore.activeHousehold else { return }
            let weekStart = appModel.weekStore.weekStartDate
            // Load profile so shoppingScaleFactor is accurate.
            async let profile: Void = appModel.householdStore.loadHouseholdDetails(householdID: household.id)
            async let prep: Void = appModel.prepBatchStore.load(householdID: household.id, weekStartDate: weekStart)
            _ = await (profile, prep)
        }
    }
}

struct ShoppingGroupView: View {
    let group: ShoppingListGroup
    let checkedItems: Set<String>
    var scaleFactor: Double = 1.0
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
                                let scaledAmount = IngredientScaler.scale(amount: item.amount, unit: item.unit, by: scaleFactor)
                                Text([scaledAmount, item.unit].compactMap { $0 }.joined(separator: " "))
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

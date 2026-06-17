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

    private var totalItemCount: Int {
        appModel.shoppingListStore.groups.flatMap { $0.items }.count
            + appModel.shoppingListStore.stapledItems.count
    }

    private var checkedItemCount: Int {
        appModel.shoppingListStore.checkedItems.count
    }

    /// "WEEK 25 · MON–FRI · 5 MEALS" — nil if data is unavailable.
    private var weekContextLine: String? {
        let weekStartString = appModel.weekStore.weekStartDate
        guard let weekStartDate = WeekCalendar.date(from: weekStartString) else { return nil }

        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(secondsFromGMT: 0)!
        let weekNumber = utcCal.component(.weekOfYear, from: weekStartDate)

        let dayRows = appModel.weekStore.dayRows
        let lockedRows = dayRows.filter { $0.isLocked }
        let mealCount = lockedRows.count

        var dayRange: String? = nil
        if let first = lockedRows.first, let last = lockedRows.last {
            let abbrev: (WeekDayRowViewModel) -> String = { row in
                String(row.weekdayLabel.prefix(3)).uppercased()
            }
            dayRange = first.weekday == last.weekday
                ? abbrev(first)
                : "\(abbrev(first))–\(abbrev(last))"
        }

        var parts: [String] = ["WEEK \(weekNumber)"]
        if let range = dayRange { parts.append(range) }
        if mealCount > 0 { parts.append("\(mealCount) \(mealCount == 1 ? "MEAL" : "MEALS")") }

        return parts.joined(separator: " · ")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Header block
                VStack(alignment: .leading, spacing: 4) {
                    if let contextLine = weekContextLine {
                        Text(contextLine)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(VecklyDesign.Colors.hearthOrange)
                    }
                    Text("Shopping list")
                        .font(VecklyDesign.Typography.displayHeading(size: 34))
                        .foregroundStyle(VecklyDesign.Colors.inkDeep)
                }

                if appModel.shoppingListStore.isLoading {
                    LoadingPanel(title: "Loading shopping list")
                } else if let errorMessage = appModel.shoppingListStore.errorMessage {
                    ErrorPanel(message: errorMessage) {
                        Task { await appModel.loadCoreReader() }
                    }
                } else if appModel.shoppingListStore.groups.isEmpty && appModel.shoppingListStore.stapledItems.isEmpty {
                    EmptyPanel(title: "Nothing to buy yet", message: "Lock in a week plan and the grouped list will appear here.")
                } else {
                    // Progress indicator
                    if totalItemCount > 0 {
                        HStack(spacing: 10) {
                            ProgressView(value: Double(checkedItemCount), total: Double(totalItemCount))
                                .tint(VecklyDesign.Colors.hearthOrange)
                            Text("\(checkedItemCount) / \(totalItemCount)")
                                .font(.caption)
                                .foregroundStyle(VecklyDesign.Colors.inkMid)
                                .monospacedDigit()
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(checkedItemCount) of \(totalItemCount) items checked")
                    }

                    // Category groups
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

                    // Pantry staples collapsed group
                    if !appModel.shoppingListStore.stapledItems.isEmpty {
                        StaplesGroupView(
                            items: appModel.shoppingListStore.stapledItems,
                            checkedItems: appModel.shoppingListStore.checkedItems,
                            onToggle: { key in
                                Task { await appModel.shoppingListStore.toggleItem(key: key) }
                            }
                        )
                    }

                    // Meal prep — shown once we've had a successful load (even if empty)
                    if appModel.prepBatchStore.isLoading || appModel.prepBatchStore.lastFetchedAt != nil {
                        PrepBatchSection(showPrepSheet: $showPrepSheet)
                    }
                }
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

// MARK: - Shopping group

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
            Text(ShoppingCategory.from(group.category).displayLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(VecklyDesign.Colors.inkMid)
                .textCase(.uppercase)

            VecklyCard {
                VStack(spacing: 0) {
                    ForEach(sortedItems) { item in
                        let isChecked = checkedItems.contains(item.itemKey)
                        let scaledAmount = IngredientScaler.scale(amount: item.amount, unit: item.unit, by: scaleFactor)
                        let amountLabel = [scaledAmount, item.unit].compactMap { $0 }.joined(separator: " ")
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
                                Text(amountLabel)
                                    .foregroundStyle(VecklyDesign.Colors.inkFaint)
                            }
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(item.label)\(amountLabel.isEmpty ? "" : ", \(amountLabel)"), \(isChecked ? "checked" : "unchecked")")
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: checkedItems)
            }
        }
    }
}

// MARK: - Staples group

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
                    Text("Likely at home")
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
                                        .foregroundStyle(isChecked ? VecklyDesign.Colors.hearthOrange : VecklyDesign.Colors.inkFaint)
                                        .font(.body)
                                    Text(item.label)
                                        .strikethrough(isChecked)
                                        .foregroundStyle(VecklyDesign.Colors.inkFaint)
                                    Spacer()
                                }
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(item.label), \(isChecked ? "checked" : "unchecked")")
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pantry staples, \(isExpanded ? "expanded" : "collapsed")")
    }
}

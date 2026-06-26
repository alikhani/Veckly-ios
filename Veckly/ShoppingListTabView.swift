import SwiftUI

struct ShoppingListTabView: View {
    var onGoToWeekTab: (() -> Void)? = nil

    @Environment(AppModel.self) private var appModel
    @State private var showCustomItemSheet = false
    @State private var customItemErrorMessage: String?

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
        guard WeekCalendar.date(from: weekStartString) != nil else { return nil }

        let weekNumber = WeekCalendar.weekNumber(for: weekStartString)

        let dayRows = appModel.weekStore.currentWeekDayRows
        let plannedRows = dayRows.filter { $0.recipe != nil }
        let mealCount = plannedRows.count

        var dayRange: String? = nil
        if let first = plannedRows.first, let last = plannedRows.last {
            let abbrev: (WeekDayRowViewModel) -> String = { row in
                String(row.weekdayLabel.prefix(3)).uppercased()
            }
            dayRange = first.weekday == last.weekday
                ? abbrev(first)
                : "\(abbrev(first))–\(abbrev(last))"
        }

        var parts: [String] = [L10n.format("format.week", weekNumber)]
        if let range = dayRange { parts.append(range) }
        if mealCount > 0 {
            parts.append(L10n.format(mealCount == 1 ? "format.meals.one" : "format.meals.other", mealCount))
        }

        return parts.joined(separator: " · ")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let err = appModel.shoppingListStore.mutationError {
                    HStack(spacing: 10) {
                        Text(err)
                            .font(.subheadline)
                            .foregroundStyle(VecklyDesign.Colors.inkDeep)
                        Spacer()
                        Button {
                            appModel.shoppingListStore.clearMutationError()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(VecklyDesign.Colors.inkMid)
                        }
                        .accessibilityLabel(L10n.string("common.dismissError"))
                    }
                    .padding(12)
                    .background(VecklyDesign.Colors.surfaceStrong)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                // Header block
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            if let contextLine = weekContextLine {
                                Text(contextLine)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(VecklyDesign.Colors.hearthOrange)
                            }
                            Text("shopping.title")
                                .font(VecklyDesign.Typography.displayHeading(size: 34))
                                .foregroundStyle(VecklyDesign.Colors.inkDeep)
                        }
                        Spacer()
                        Button {
                            showCustomItemSheet = true
                        } label: {
                            Label(addOwnItemButtonLabel, systemImage: "plus")
                                .font(.callout.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(VecklyDesign.Colors.hearthOrange)
                    }

                    if appModel.shoppingListStore.hasPendingSync {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(pendingSyncMessage)
                                .font(.caption)
                                .foregroundStyle(VecklyDesign.Colors.inkMid)
                        }
                    }
                }

                if appModel.shoppingListStore.isLoading {
                    LoadingPanel(title: L10n.string("shopping.loading"))
                } else if let errorMessage = appModel.shoppingListStore.errorMessage {
                    ErrorPanel(message: errorMessage) {
                        Task { await appModel.loadCoreReader() }
                    }
                } else if appModel.shoppingListStore.groups.isEmpty && appModel.shoppingListStore.stapledItems.isEmpty {
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
                        .accessibilityLabel(L10n.format("accessibility.itemsChecked", checkedItemCount, totalItemCount))
                    }

                    // Category groups
                    ForEach(appModel.shoppingListStore.groups) { group in
                        ShoppingGroupView(
                            group: group,
                            checkedItems: appModel.shoppingListStore.checkedItems,
                            scaleFactor: shoppingScaleFactor,
                            onToggle: { key in
                                Task { await appModel.shoppingListStore.toggleItem(key: key) }
                            },
                            onRemoveCustom: { key in
                                Task { await removeCustomItem(key: key) }
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
                }
            }
            .padding(18)
            .accessibilityIdentifier("shoppingList")
        }
        .background(VecklyDesign.Colors.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCustomItemSheet) {
            ShoppingCustomItemSheet { label, category in
                try await appModel.shoppingListStore.addCustomItem(label: label, category: category)
            }
        }
        .alert(
            customItemErrorTitle,
            isPresented: Binding(
                get: { customItemErrorMessage != nil },
                set: { if !$0 { customItemErrorMessage = nil } }
            )
        ) {
            Button("OK") { customItemErrorMessage = nil }
        } message: {
            Text(customItemErrorMessage ?? "")
        }
        .task(id: appModel.householdStore.activeHousehold?.id) {
            guard let household = appModel.householdStore.activeHousehold else { return }
            // Load profile so shoppingScaleFactor is accurate.
            await appModel.householdStore.loadHouseholdDetails(householdID: household.id)
        }
    }

    private func removeCustomItem(key: String) async {
        do {
            try await appModel.shoppingListStore.removeCustomItem(itemKey: key)
        } catch {
            customItemErrorMessage = customItemRemoveError
        }
    }

    private var customItemTitle: String {
        L10n.string("shopping.customItem.title")
    }

    private var addOwnItemButtonLabel: String {
        L10n.string("shopping.customItem.addButton")
    }

    private var customItemErrorTitle: String {
        L10n.string("shopping.customItem.errorTitle")
    }

    private var customItemAddError: String {
        L10n.string("shopping.customItem.addError")
    }

    private var customItemRemoveError: String {
        L10n.string("shopping.customItem.removeError")
    }

    private var pendingSyncMessage: String {
        L10n.string("shopping.sync.pending")
    }
}

private struct ShoppingCustomItemSheet: View {
    let onSave: (String, ShoppingCategory) async throws -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var label = ""
    @State private var category: ShoppingCategory = .other
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L10n.string("shopping.customItem.placeholder"), text: $label)
                        .textInputAutocapitalization(.sentences)
                    Picker(L10n.string("shopping.customItem.category"), selection: $category) {
                        ForEach(ShoppingCategory.allCases, id: \.self) { option in
                            Text(option.displayLabel).tag(option)
                        }
                    }
                } header: {
                    Text(L10n.string("shopping.customItem.name"))
                }
            }
            .navigationTitle(L10n.string("shopping.customItem.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("shopping.customItem.add") { Task { await save() } }
                            .disabled(trimmedLabel.isEmpty)
                    }
                }
            }
            .alert(L10n.string("common.error"),
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                ),
                actions: { Button("common.ok") { errorMessage = nil } },
                message: { Text(errorMessage ?? "") }
            )
        }
    }

    private var trimmedLabel: String {
        label.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() async {
        guard !trimmedLabel.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            try await onSave(trimmedLabel, category)
            dismiss()
        } catch {
            errorMessage = L10n.string("shopping.customItem.addError")
        }
    }
}

// MARK: - Shopping group

struct ShoppingGroupView: View {
    let group: ShoppingListGroup
    let checkedItems: Set<String>
    var scaleFactor: Double = 1.0
    let onToggle: (String) -> Void
    let onRemoveCustom: (String) -> Void

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
                        HStack {
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
                                }
                                .buttonStyle(.plain)
                            }
                        }
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

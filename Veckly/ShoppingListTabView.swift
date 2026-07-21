import SwiftUI

struct ShoppingListTabView: View {
    var onGoToWeekTab: (() -> Void)? = nil

    @Environment(AppModel.self) private var appModel
    @State private var showCustomItemSheet = false
    @State private var clearedKeys: [String] = []
    @State private var undoTask: Task<Void, Never>?
    @State private var reportedCompletedShoppingListWeeks: Set<String> = []
    @State private var reminderExporter = ShoppingListReminderExporter()
    @State private var reminderExportNotice: ShoppingReminderExportNotice?
    @State private var isExportingReminders = false

    private var totalItemCount: Int {
        appModel.shoppingListStore.groups.flatMap { $0.items }.count
    }

    private var checkedItemCount: Int {
        let stapleKeys = Set(appModel.shoppingListStore.stapledItems.map(\.itemKey))
        return appModel.shoppingListStore.checkedItems.filter { !stapleKeys.contains($0) }.count
    }

    /// "V.26 · 2 MIDDAGAR" — nil if data is unavailable.
    private var weekContextLine: String? {
        let weekStartString = appModel.weekStore.weekStartDate
        guard WeekCalendar.date(from: weekStartString) != nil else { return nil }

        let weekNumber = WeekCalendar.weekNumber(for: weekStartString)

        let dayRows = appModel.weekStore.currentWeekDayRows
        let mealCount = dayRows.filter { $0.recipe != nil }.count

        var parts: [String] = [L10n.format("format.week", weekNumber)]
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
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel(L10n.string("common.dismissError"))
                    }
                    .padding(12)
                    .background(VecklyDesign.Colors.surfaceStrong)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                // Header block
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 12) {
                        if let contextLine = weekContextLine {
                            Text(contextLine)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(VecklyDesign.Colors.hearthOrangeText)
                        }
                        Spacer()
                        if !shoppingReminderItems.isEmpty {
                            Menu {
                                Button {
                                    Task { await exportShoppingListToReminders() }
                                } label: {
                                    Label(remindersExportButtonLabel, systemImage: "checklist")
                                }
                                .disabled(isExportingReminders)

                                if let shoppingShareText {
                                    ShareLink(item: shoppingShareText) {
                                        Label(L10n.string("shopping.share.textFallback"), systemImage: "square.and.arrow.up")
                                    }
                                }
                            } label: {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.callout.weight(.semibold))
                                    .frame(width: 34, height: 34)
                            }
                            .buttonStyle(.bordered)
                            .tint(VecklyDesign.Colors.inkMid)
                            .accessibilityLabel(L10n.string("shopping.share.action"))
                        }
                        Button {
                            showCustomItemSheet = true
                        } label: {
                            Label(addOwnItemButtonLabel, systemImage: "plus")
                                .font(.callout.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(VecklyDesign.Colors.hearthOrangePrimaryFill)
                    }

                    Text(L10n.string("shopping.title"))
                        .font(VecklyDesign.Typography.displayHeading(size: 34))
                        .foregroundStyle(VecklyDesign.Colors.inkDeep)

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
                        Task { await appModel.loadCoreReader(trigger: .pullToRefresh) }
                    }
                } else if appModel.shoppingListStore.groups.isEmpty && appModel.shoppingListStore.stapledItems.isEmpty {
                    if appModel.shoppingListStore.summary != nil {
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
                } else {
                    // Progress indicator
                    if totalItemCount > 0 {
                        HStack(spacing: 10) {
                            ProgressView(value: Double(checkedItemCount), total: Double(totalItemCount))
                                .tint(VecklyDesign.Colors.hearthOrangeFill)
                            Text("\(checkedItemCount) / \(totalItemCount)")
                                .font(.caption)
                                .foregroundStyle(VecklyDesign.Colors.inkMid)
                                .monospacedDigit()
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(L10n.format("accessibility.itemsChecked", checkedItemCount, totalItemCount))
                    }

                    if let shoppingHandoffState {
                        ShoppingHandoffStatusCard(state: shoppingHandoffState)
                    }

                    // Category groups
                    ForEach(appModel.shoppingListStore.groups) { group in
                        ShoppingGroupView(
                            group: group,
                            checkedItems: appModel.shoppingListStore.checkedItems,
                            onToggle: { key in
                                Task { await appModel.shoppingListStore.toggleItem(key: key) }
                            },
                            onRemoveCustom: { key in
                                removeCustomItem(key: key)
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
        .refreshable {
            guard let household = appModel.householdStore.activeHousehold else { return }
            let weekStartDate = appModel.weekStore.weekStartDate
            appModel.shoppingListStore.invalidateCache()
            await appModel.shoppingListStore.loadCurrentWeek(household: household, weekStartDate: weekStartDate)
        }
        .safeAreaPadding(.bottom, VecklyDesign.Spacing.large)
        .background(VecklyDesign.Colors.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !appModel.shoppingListStore.checkedItems.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.string("shopping.clearChecked")) {
                        let keys = appModel.shoppingListStore.bulkClearChecked()
                        guard !keys.isEmpty else { return }
                        clearedKeys = keys
                        undoTask?.cancel()
                        undoTask = Task {
                            try? await Task.sleep(nanoseconds: 4_000_000_000)
                            guard !Task.isCancelled else { return }
                            clearedKeys = []
                        }
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if !clearedKeys.isEmpty {
                HStack(spacing: 16) {
                    Text(L10n.string("shopping.itemsCleared"))
                        .font(.subheadline)
                        .foregroundStyle(.white)
                    Spacer()
                    Button(L10n.string("common.undo")) {
                        undoTask?.cancel()
                        let keys = clearedKeys
                        clearedKeys = []
                        Task {
                            for key in keys {
                                await appModel.shoppingListStore.toggleItem(key: key)
                            }
                        }
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
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.25), value: clearedKeys.isEmpty)
            }
        }
        .sheet(isPresented: $showCustomItemSheet) {
            ShoppingCustomItemSheet { label, category in
                appModel.shoppingListStore.addCustomItem(label: label, category: category)
            }
        }
        .onAppear {
            // Re-fetch the shopping list whenever the tab becomes visible so
            // that mutations made on the Week tab (add/remove/generate) are
            // reflected here. `ShoppingListStore.loadCurrentWeek` short-circuits
            // if data is fresh (< 5 min), so this is cheap during normal
            // browsing and only hits the network after `invalidateCache()` is
            // called following a week plan change.
            //
            // Unlike `WeekTabView`, this tab was never migrated onto
            // `AppRefreshCoordinator` (Fas 7's migration only covered the
            // Week tab), so it needs its own `usesSeededCoreReader` guard —
            // without it, seeded UI-test mode still made a real network call
            // here and silently overwrote the seeded shopping list with a
            // load-error banner.
            guard !appModel.usesSeededCoreReader else { return }
            guard let household = appModel.householdStore.activeHousehold else { return }
            let weekStartDate = appModel.weekStore.weekStartDate
            Task { await appModel.shoppingListStore.loadCurrentWeek(household: household, weekStartDate: weekStartDate) }
        }
        .task(id: appModel.weekStore.weekStartDate) {
            guard !appModel.usesSeededCoreReader else { return }
            guard let household = appModel.householdStore.activeHousehold else { return }
            let weekStartDate = appModel.weekStore.weekStartDate
            appModel.shoppingListStore.invalidateCache()
            await appModel.shoppingListStore.loadCurrentWeek(household: household, weekStartDate: weekStartDate)
        }
        .onChange(of: shoppingHandoffState?.isCompleted) { _, isCompleted in
            guard isCompleted == true else { return }
            recordShoppingMainListCompletedIfNeeded()
        }
        .alert(item: $reminderExportNotice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text(L10n.string("common.ok")))
            )
        }
    }

    private func removeCustomItem(key: String) {
        appModel.shoppingListStore.removeCustomItem(itemKey: key)
    }

    private var addOwnItemButtonLabel: String {
        L10n.string("shopping.customItem.addButton")
    }

    private var pendingSyncMessage: String {
        L10n.string("shopping.sync.pending")
    }

    private var shoppingShareText: String? {
        ShoppingListShareText.make(
            title: L10n.string("shopping.title"),
            contextLine: weekContextLine,
            groups: appModel.shoppingListStore.groups,
            staples: appModel.shoppingListStore.stapledItems,
            checkedItems: appModel.shoppingListStore.checkedItems
        )
    }

    private var shoppingReminderItems: [String] {
        let reminderItems = ShoppingListShareText.reminderItems(
            groups: appModel.shoppingListStore.groups,
            checkedItems: appModel.shoppingListStore.checkedItems
        )

        if !reminderItems.isEmpty {
            return reminderItems
        }

        return shoppingShareText.map { [$0] } ?? []
    }

    private var remindersExportButtonLabel: String {
        let count = shoppingReminderItems.count
        let key = count == 1 ? "shopping.reminders.export.one" : "shopping.reminders.export.other"
        return L10n.format(key, count)
    }

    private var shoppingHandoffState: ShoppingListHandoffState? {
        ShoppingListHandoffState.make(
            groups: appModel.shoppingListStore.groups,
            checkedItems: appModel.shoppingListStore.checkedItems
        )
    }

    private func exportShoppingListToReminders() async {
        guard !isExportingReminders else { return }
        isExportingReminders = true
        defer { isExportingReminders = false }

        do {
            let count = try await reminderExporter.export(
                items: shoppingReminderItems,
                listTitle: L10n.string("shopping.title"),
                notes: weekContextLine
            )
            reminderExportNotice = ShoppingReminderExportNotice(
                title: L10n.string("shopping.reminders.success.title"),
                message: L10n.format(
                    count == 1 ? "shopping.reminders.success.message.one" : "shopping.reminders.success.message.other",
                    count
                )
            )
            appModel.recordProductEvent(.shoppingShared, weekStartDate: appModel.weekStore.weekStartDate, properties: [
                "items": .int(count),
                "checkedItems": .int(checkedItemCount)
            ])
        } catch ShoppingListReminderExportError.accessDenied {
            reminderExportNotice = ShoppingReminderExportNotice(
                title: L10n.string("shopping.reminders.denied.title"),
                message: L10n.string("shopping.reminders.denied.message")
            )
        } catch {
            reminderExportNotice = ShoppingReminderExportNotice(
                title: L10n.string("shopping.reminders.error.title"),
                message: L10n.string("shopping.reminders.error.message")
            )
        }
    }

    private func recordShoppingMainListCompletedIfNeeded() {
        let weekStartDate = appModel.weekStore.weekStartDate
        guard reportedCompletedShoppingListWeeks.insert(weekStartDate).inserted else { return }
        appModel.recordProductEvent(.shoppingMainListCompleted, weekStartDate: weekStartDate, properties: [
            "items": .int(totalItemCount)
        ])
    }
}

private struct ShoppingReminderExportNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private extension ShoppingListHandoffState {
    var isCompleted: Bool {
        switch self {
        case .completed: true
        case .ready: false
        }
    }
}

private struct ShoppingHandoffStatusCard: View {
    let state: ShoppingListHandoffState

    var body: some View {
        VecklyCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: iconName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(VecklyDesign.Colors.hearthOrangeFill)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(VecklyDesign.Colors.inkDeep)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(VecklyDesign.Colors.inkMid)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private var iconName: String {
        switch state {
        case .ready: "cart"
        case .completed: "checkmark.seal"
        }
    }

    private var title: String {
        switch state {
        case .ready: L10n.string("shopping.handoff.ready.title")
        case .completed: L10n.string("shopping.handoff.completed.title")
        }
    }

    private var message: String {
        switch state {
        case .ready(let totalItems, let checkedItems):
            L10n.format("shopping.handoff.ready.message", checkedItems, totalItems)
        case .completed:
            L10n.string("shopping.handoff.completed.message")
        }
    }
}

private struct ShoppingCustomItemSheet: View {
    let onSave: (String, ShoppingCategory) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var label = ""
    @State private var category: ShoppingCategory = .other

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
                    Button("shopping.customItem.add") { save() }
                        .disabled(trimmedLabel.isEmpty)
                }
            }
        }
    }

    private var trimmedLabel: String {
        label.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        guard !trimmedLabel.isEmpty else { return }
        onSave(trimmedLabel, category)
        dismiss()
    }
}

// MARK: - Shopping group

struct ShoppingGroupView: View {
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

import SwiftUI

struct ShoppingListTabView: View {
    var onGoToWeekTab: (() -> Void)? = nil

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var model: ShoppingScreenModel
    @State private var showPendingSyncIndicator = false

    init(model: ShoppingScreenModel, onGoToWeekTab: (() -> Void)? = nil) {
        _model = State(initialValue: model)
        self.onGoToWeekTab = onGoToWeekTab
    }

    @ViewBuilder
    private var shareMenu: some View {
        if !model.reminderItems.isEmpty {
            Menu {
                Button {
                    Task { await model.exportToReminders() }
                } label: {
                    Label(model.remindersExportButtonLabel, systemImage: "checklist")
                }
                .disabled(model.isExportingReminders)

                if let shoppingShareText = model.shareText {
                    ShareLink(item: shoppingShareText) {
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
            model.presentCustomItemSheet()
        } label: {
            ViewThatFits(in: .horizontal) {
                addOwnItemButtonContent(addOwnItemButtonLabel)
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
        Button { model.presentCategoryOrderSheet() } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.callout.weight(.semibold))
                .frame(minWidth: 20, minHeight: 24)
        }
        .buttonStyle(.bordered)
        .tint(VecklyDesign.Colors.inkMid)
        .accessibilityLabel(L10n.string("shopping.categoryOrder.action"))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let err = model.mutationError {
                    HStack(spacing: 10) {
                        Text(err)
                            .font(.subheadline)
                            .foregroundStyle(VecklyDesign.Colors.inkDeep)
                        Spacer()
                        Button {
                            model.dismissMutationError()
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
                    // Fas F: at accessibility Dynamic Type sizes the share/add
                    // buttons grow enough to squeeze `weekContextLine` down to
                    // an unreadable sliver (`minimumScaleFactor` alone can't
                    // save it) — verified with a screenshot at
                    // `.accessibilityExtraExtraExtraLarge`. Giving the context
                    // line its own row at those sizes, instead of fighting the
                    // buttons for space in one line, fixes it without
                    // affecting the normal-size layout at all.
                    if dynamicTypeSize.isAccessibilitySize {
                        if let contextLine = model.weekContextLine {
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
                            if let contextLine = model.weekContextLine {
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

                if model.showsLoadingPanel {
                    LoadingPanel(title: L10n.string("shopping.loading"))
                } else if let errorMessage = model.loadErrorMessage {
                    ErrorPanel(message: errorMessage) {
                        model.retryLoad()
                    }
                } else if model.isListEmpty {
                    if model.hasWeekPlan {
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
                    if model.totalItemCount > 0 {
                        HStack(spacing: 10) {
                            ProgressView(value: Double(model.checkedItemCount), total: Double(model.totalItemCount))
                                .tint(VecklyDesign.Colors.hearthOrangeFill)
                            Text("\(model.checkedItemCount) / \(model.totalItemCount)")
                                .font(.caption)
                                .foregroundStyle(VecklyDesign.Colors.inkMid)
                                .monospacedDigit()
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 18, height: 18)
                                .opacity(showPendingSyncIndicator ? 1 : 0)
                                .accessibilityHidden(!showPendingSyncIndicator)
                                .accessibilityLabel(pendingSyncMessage)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(L10n.format("accessibility.itemsChecked", model.checkedItemCount, model.totalItemCount))
                        .accessibilityValue(showPendingSyncIndicator ? pendingSyncMessage : "")
                    }

                    // Fas D: the `.ready` card used to show permanently and
                    // just repeat the progress row above in prose ("3 of 7
                    // checked"). Only the `.completed` handoff moment earns
                    // its own card now — the list itself is the workspace.
                    if let handoffState = model.handoffState, handoffState.isCompleted {
                        ShoppingHandoffStatusCard(state: handoffState)
                    }

                    // Category groups
                    ForEach(model.groups) { group in
                        ShoppingGroupView(
                            group: group,
                            checkedItems: model.checkedItems,
                            onToggle: { key in
                                model.toggleItem(key)
                            },
                            onRemoveCustom: { key in
                                model.removeCustomItem(key)
                            }
                        )
                    }

                    // Pantry staples collapsed group
                    if !model.stapledItems.isEmpty {
                        StaplesGroupView(
                            items: model.stapledItems,
                            checkedItems: model.checkedItems,
                            onToggle: { key in
                                model.toggleItem(key)
                            }
                        )
                    }
                }
            }
            .padding(18)
            .accessibilityIdentifier("shoppingList")
        }
        .refreshable {
            await model.refresh()
        }
        .safeAreaPadding(.bottom, VecklyDesign.Spacing.large)
        .background(VecklyDesign.Colors.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !model.checkedItems.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.string("shopping.clearChecked")) {
                        model.clearChecked()
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if !model.clearedKeys.isEmpty {
                HStack(spacing: 16) {
                    Text(L10n.string("shopping.itemsCleared"))
                        .font(.subheadline)
                        .foregroundStyle(.white)
                    Spacer()
                    Button(L10n.string("common.undo")) {
                        model.undoClearChecked()
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
                .animation(.easeInOut(duration: 0.25), value: model.clearedKeys.isEmpty)
            }
        }
        .sheet(item: $model.sheet) { sheet in
            switch sheet {
            case .customItem:
                ShoppingCustomItemSheet { label, category in
                    model.addCustomItem(label: label, category: category)
                }
            case .categoryOrder:
                if model.hasActiveHousehold {
                    ShoppingCategoryOrderSheet(initialOrder: model.categoryOrder) { order in
                        await model.saveCategoryOrder(order)
                    }
                }
            }
        }
        .onAppear {
            model.tabDidAppear()
        }
        .task(id: model.weekStartDate) {
            await model.weekDidChange()
        }
        .task(id: model.hasPendingSync) {
            if model.hasPendingSync {
                try? await Task.sleep(for: .milliseconds(800))
                guard !Task.isCancelled, model.hasPendingSync else { return }
                showPendingSyncIndicator = true
            } else {
                showPendingSyncIndicator = false
            }
        }
        .onChange(of: model.handoffState?.isCompleted) { _, isCompleted in
            model.handoffCompletionDidChange(isCompleted: isCompleted)
        }
        .alert(item: $model.reminderExportNotice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text(L10n.string("common.ok")))
            )
        }
    }

    private var addOwnItemButtonLabel: String {
        L10n.string("shopping.customItem.addButton")
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

    private var pendingSyncMessage: String {
        L10n.string("shopping.sync.pending")
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

private struct ShoppingCategoryOrderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var order: [ShoppingCategory]
    @State private var isSaving = false
    let onSave: ([ShoppingCategory]) async -> Void

    init(initialOrder: [ShoppingCategory], onSave: @escaping ([ShoppingCategory]) async -> Void) {
        _order = State(initialValue: initialOrder)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(order) { category in
                        Label(category.displayLabel, systemImage: category.systemImage)
                    }
                    .onMove { source, destination in
                        order.move(fromOffsets: source, toOffset: destination)
                    }
                } footer: {
                    Text("shopping.categoryOrder.footer")
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("shopping.categoryOrder.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") {
                        isSaving = true
                        Task {
                            await onSave(order)
                            dismiss()
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
    }
}

private extension ShoppingCategory {
    var systemImage: String {
        switch self {
        case .produce: "carrot"
        case .meat: "takeoutbag.and.cup.and.straw"
        case .dairy: "waterbottle"
        case .pantry: "cabinet"
        case .frozen: "snowflake"
        case .bakery: "birthday.cake"
        case .other: "ellipsis.circle"
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

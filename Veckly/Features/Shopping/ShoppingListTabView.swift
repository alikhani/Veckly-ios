import SwiftUI

struct ShoppingListTabView: View {
    var onGoToWeekTab: (() -> Void)? = nil

    @State private var model: ShoppingScreenModel
    @State private var showPendingSyncIndicator = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: ShoppingScreenModel, onGoToWeekTab: (() -> Void)? = nil) {
        _model = State(initialValue: model)
        self.onGoToWeekTab = onGoToWeekTab
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let err = model.mutationError {
                    DismissibleErrorBanner(message: err) {
                        model.dismissMutationError()
                    }
                }

                ShoppingHeader(
                    contextLine: model.weekContextLine,
                    hasReminderItems: !model.reminderItems.isEmpty,
                    remindersExportButtonLabel: model.remindersExportButtonLabel,
                    isExportingReminders: model.isExportingReminders,
                    shareText: model.shareText,
                    onExportToReminders: { Task { await model.exportToReminders() } },
                    onAddItem: { model.presentCustomItemSheet() },
                    onArrangeCategories: { model.presentCategoryOrderSheet() }
                )

                if model.showsLoadingPanel {
                    LoadingPanel(title: L10n.string("shopping.loading"))
                } else if let errorMessage = model.loadErrorMessage {
                    ErrorPanel(message: errorMessage) {
                        model.retryLoad()
                    }
                } else if model.isListEmpty {
                    ShoppingEmptyStateCard(hasWeekPlan: model.hasWeekPlan, onGoToWeekTab: onGoToWeekTab)
                } else {
                    listContent
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
            if model.hasCheckedItemsOnList {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.string("shopping.clearChecked")) {
                        model.clearChecked()
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 0) {
                if model.hasPendingUpdate {
                    // An overlay with a fade only: it never moves the list
                    // under the user's finger.
                    UpdateAvailableBanner(onShow: { model.showPendingUpdate() })
                        .padding(.horizontal, 18)
                        .padding(.bottom, 12)
                        .transition(.opacity)
                }
                if !model.clearedKeys.isEmpty {
                    ShoppingClearedToast {
                        model.undoClearChecked()
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.25), value: model.clearedKeys.isEmpty)
                }
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.hasPendingUpdate)
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

    @ViewBuilder
    private var listContent: some View {
        if model.totalItemCount > 0 {
            ShoppingProgressRow(
                checkedItemCount: model.checkedItemCount,
                totalItemCount: model.totalItemCount,
                showsPendingSync: showPendingSyncIndicator
            )
        }

        // Fas D: the `.ready` card used to show permanently and
        // just repeat the progress row above in prose ("3 of 7
        // checked"). Only the `.completed` handoff moment earns
        // its own card now — the list itself is the workspace.
        if let handoffState = model.handoffState, handoffState.isCompleted {
            ShoppingHandoffStatusCard(state: handoffState)
        }

        ForEach(model.groups) { group in
            ShoppingGroupView(
                group: group,
                checkedItems: model.checkedItems,
                onToggle: { key in model.toggleItem(key) },
                onRemoveCustom: { key in model.removeCustomItem(key) }
            )
        }

        // Pantry staples collapsed group
        if !model.stapledItems.isEmpty {
            StaplesGroupView(
                items: model.stapledItems,
                checkedItems: model.checkedItems,
                onToggle: { key in model.toggleItem(key) }
            )
        }
    }
}

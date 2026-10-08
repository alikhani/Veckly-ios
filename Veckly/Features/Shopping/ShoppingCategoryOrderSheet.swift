import SwiftUI

struct ShoppingCategoryOrderSheet: View {
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

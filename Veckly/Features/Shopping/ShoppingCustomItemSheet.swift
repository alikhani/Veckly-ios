import SwiftUI

struct ShoppingCustomItemSheet: View {
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

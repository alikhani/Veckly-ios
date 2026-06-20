import SwiftUI

struct RenameHouseholdView: View {
    let householdID: String
    let currentName: String

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                TextField(L10n.string("household.name"), text: $name)
                    .autocorrectionDisabled()
            }
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
        }
        .navigationTitle(L10n.string("household.rename"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button(L10n.string("common.save")) {
                        Task { await save() }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || name == currentName)
                }
            }
        }
        .onAppear { name = currentName }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await appModel.householdStore.renameHousehold(householdID: householdID, name: name)
            dismiss()
        } catch {
            errorMessage = L10n.string("error.household.rename")
        }
    }
}

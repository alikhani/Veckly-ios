import SwiftUI

struct EditDisplayNameView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var givenName: String = ""
    @State private var familyName: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                TextField(L10n.string("settings.givenName.placeholder"), text: $givenName)
                    .autocorrectionDisabled()
                TextField(L10n.string("settings.familyName.placeholder"), text: $familyName)
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
        .navigationTitle(L10n.string("settings.displayName"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button(L10n.string("common.save")) {
                        Task { await save() }
                    }
                    .disabled(givenName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || (givenName == appModel.userProfileStore.givenName
                            && familyName == (appModel.userProfileStore.familyName ?? "")))
                }
            }
        }
        .task {
            await appModel.userProfileStore.load()
            givenName = appModel.userProfileStore.givenName ?? ""
            familyName = appModel.userProfileStore.familyName ?? ""
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let trimmedFamilyName = familyName.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await appModel.userProfileStore.save(
                givenName: givenName,
                familyName: trimmedFamilyName.isEmpty ? nil : trimmedFamilyName
            )
            dismiss()
        } catch {
            errorMessage = L10n.string("error.profile.save")
        }
    }
}

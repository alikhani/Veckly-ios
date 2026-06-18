import SwiftUI

struct SettingsTabView: View {
    @Environment(AppModel.self) private var appModel
    @State private var showDeleteConfirmation = false
    @State private var isDeletingAccount = false
    @State private var deleteErrorMessage: String?

    var body: some View {
        Form {
            Section("household.section") {
                LabeledContent("household.name") {
                    Text(appModel.householdStore.activeHousehold?.name ?? "—")
                        .foregroundStyle(VecklyDesign.Colors.inkFaint)
                }
                NavigationLink("settings.membersInvites") {
                    HouseholdMembersView()
                }
                NavigationLink("household.preferences") {
                    HouseholdProfileView()
                }
            }

            Section {
                Button(role: .destructive) {
                    appModel.signOut()
                } label: {
                    Text("settings.signOut")
                }
                .accessibilityIdentifier("signOutButton")
            }

            Section {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    if isDeletingAccount {
                        HStack {
                            ProgressView()
                            Text("settings.deletingAccount")
                        }
                    } else {
                        Text("settings.deleteAccount")
                    }
                }
                .disabled(isDeletingAccount)
            } footer: {
                Text("settings.deleteFooter")
            }
        }
        .navigationTitle(L10n.string("tabs.settings"))
        .confirmationDialog(
            L10n.string("settings.deleteConfirmation"),
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("settings.deleteAccount", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text("settings.deleteMessage")
        }
        .alert(L10n.string("settings.deleteFailed"),
            isPresented: Binding(get: { deleteErrorMessage != nil }, set: { if !$0 { deleteErrorMessage = nil } }),
            actions: { Button("common.ok") { deleteErrorMessage = nil } },
            message: { Text(deleteErrorMessage ?? "") }
        )
    }

    private func deleteAccount() async {
        isDeletingAccount = true
        defer { isDeletingAccount = false }
        do {
            try await appModel.deleteAccount()
        } catch {
            deleteErrorMessage = L10n.string("error.settings.deleteAccount")
        }
    }
}

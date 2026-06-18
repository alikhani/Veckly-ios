import SwiftUI

struct SettingsTabView: View {
    @Environment(AppModel.self) private var appModel
    @State private var showDeleteConfirmation = false
    @State private var isDeletingAccount = false
    @State private var deleteErrorMessage: String?

    var body: some View {
        Form {
            Section("Household") {
                LabeledContent("Name") {
                    Text(appModel.householdStore.activeHousehold?.name ?? "—")
                        .foregroundStyle(VecklyDesign.Colors.inkFaint)
                }
                NavigationLink("Members & Invites") {
                    HouseholdMembersView()
                }
                NavigationLink("Preferences") {
                    HouseholdProfileView()
                }
            }

            Section {
                Button(role: .destructive) {
                    appModel.signOut()
                } label: {
                    Text("Sign out")
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
                            Text("Deleting account…")
                        }
                    } else {
                        Text("Delete Account")
                    }
                }
                .disabled(isDeletingAccount)
            } footer: {
                Text("Permanently deletes your account and all household data. This cannot be undone.")
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog(
            "Delete your account?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Account", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your account and all household data will be permanently deleted.")
        }
        .alert("Could not delete account",
            isPresented: Binding(get: { deleteErrorMessage != nil }, set: { if !$0 { deleteErrorMessage = nil } }),
            actions: { Button("OK") { deleteErrorMessage = nil } },
            message: { Text(deleteErrorMessage ?? "") }
        )
    }

    private func deleteAccount() async {
        isDeletingAccount = true
        defer { isDeletingAccount = false }
        do {
            try await appModel.deleteAccount()
        } catch {
            deleteErrorMessage = "Account deletion failed. Contact support at support@veckly.app if the problem persists."
        }
    }
}

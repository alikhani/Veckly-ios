import SwiftUI

struct SettingsTabView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        Form {
            Section("Household") {
                Text(appModel.householdStore.activeHousehold?.name ?? "No household")
            }

            Section {
                Button(role: .destructive) {
                    appModel.signOut()
                } label: {
                    Text("Sign out")
                }
                .accessibilityIdentifier("signOutButton")
            }
        }
        .navigationTitle("Settings")
    }
}

import SwiftUI

struct SettingsTabView: View {
    @Environment(AppModel.self) private var appModel

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
        }
        .navigationTitle("Settings")
    }
}

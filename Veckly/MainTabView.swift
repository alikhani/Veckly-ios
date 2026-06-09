import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationStack {
                WeekTabView()
            }
            .tabItem {
                Label("Week", systemImage: "calendar")
            }

            NavigationStack {
                ShoppingListTabView()
            }
            .tabItem {
                Label("Shopping", systemImage: "checklist")
            }

            NavigationStack {
                SettingsTabView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .tint(VecklyDesign.Colors.hearthOrange)
    }
}

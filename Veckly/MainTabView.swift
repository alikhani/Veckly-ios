import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationStack {
                WeekTabView()
            }
            .tabItem {
                Label("tabs.week", systemImage: "calendar")
            }

            NavigationStack {
                ShoppingListTabView()
            }
            .tabItem {
                Label("tabs.shopping", systemImage: "checklist")
            }

            NavigationStack {
                RecipesTabView()
            }
            .tabItem {
                Label("tabs.recipes", systemImage: "fork.knife")
            }

            NavigationStack {
                SettingsTabView()
            }
            .tabItem {
                Label("tabs.settings", systemImage: "gearshape")
            }
        }
        .tint(VecklyDesign.Colors.hearthOrange)
    }
}

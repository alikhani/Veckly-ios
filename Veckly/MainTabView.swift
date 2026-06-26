import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                WeekTabView()
            }
            .tabItem {
                Label("tabs.week", systemImage: "calendar")
            }
            .tag(0)

            NavigationStack {
                ShoppingListTabView(onGoToWeekTab: { selectedTab = 0 })
            }
            .tabItem {
                Label("tabs.shopping", systemImage: "checklist")
            }
            .tag(1)

            NavigationStack {
                RecipesTabView()
            }
            .tabItem {
                Label("tabs.recipes", systemImage: "fork.knife")
            }
            .tag(2)

            NavigationStack {
                HouseholdTabView()
            }
            .tabItem {
                Label("tabs.household", systemImage: "person.2")
            }
            .tag(3)
        }
        .tint(VecklyDesign.Colors.hearthOrange)
    }
}

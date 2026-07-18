import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                WeekTabView(
                    onGoToShoppingTab: { selectedTab = 1 },
                    onGoToHouseholdTab: { selectedTab = 2 }
                )
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
                HouseholdTabView()
            }
            .tabItem {
                Label("tabs.household", systemImage: "person.2")
            }
            .tag(2)
        }
        .tint(VecklyDesign.Colors.hearthOrange)
    }
}

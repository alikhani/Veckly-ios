import SwiftUI

struct MainTabView: View {
    @Environment(AppModel.self) private var appModel
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                WeekTabView(
                    model: WeekScreenModel.live(appModel),
                    onGoToShoppingTab: { selectedTab = 1 },
                    onGoToHouseholdTab: { selectedTab = 2 }
                )
            }
            .tabItem {
                Label("tabs.week", systemImage: "calendar")
            }
            .tag(0)

            NavigationStack {
                ShoppingListTabView(
                    model: ShoppingScreenModel.live(appModel),
                    onGoToWeekTab: { selectedTab = 0 }
                )
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
        .tint(VecklyDesign.Colors.hearthOrangeFill)
        .onAppear { applyPendingDeepLink() }
        .onChange(of: appModel.pendingDeepLink) { _, _ in applyPendingDeepLink() }
    }

    private func applyPendingDeepLink() {
        guard let destination = appModel.pendingDeepLink else { return }
        switch destination {
        case .meal: selectedTab = 0
        case .shopping:
            selectedTab = 1
            appModel.pendingDeepLink = nil
        }
    }
}

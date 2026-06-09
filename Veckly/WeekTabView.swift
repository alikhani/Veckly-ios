import SwiftUI

struct WeekTabView: View {
    @Environment(AppModel.self) private var appModel
    @State private var selectedRecipe: WeekSummaryRecipe?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if appModel.householdStore.isLoading || appModel.weekStore.isLoading {
                    LoadingPanel(title: "Loading this week")
                } else if let errorMessage = appModel.weekStore.errorMessage ?? appModel.householdStore.errorMessage {
                    ErrorPanel(message: errorMessage) {
                        Task { await appModel.loadCoreReader() }
                    }
                } else {
                    todayPanel
                    weekList
                }
            }
            .padding(18)
        }
        .background(VecklyDesign.Colors.canvas)
        .navigationTitle("Week")
        .toolbar {
            Button {
                Task { await appModel.loadCoreReader() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .accessibilityLabel("Refresh")
        }
        .sheet(item: $selectedRecipe) { recipe in
            RecipeDetailView(recipe: recipe)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(appModel.householdStore.activeHousehold?.name ?? "Your household")
                .font(.subheadline)
                .foregroundStyle(VecklyDesign.Colors.hearthOrange)
                .textCase(.uppercase)
            Text("This week")
                .font(.system(size: 34, weight: .bold, design: .serif))
                .foregroundStyle(VecklyDesign.Colors.inkDeep)
        }
    }

    private var todayPanel: some View {
        VecklyCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Tonight")
                    .font(.caption)
                    .foregroundStyle(VecklyDesign.Colors.hearthOrange)
                    .textCase(.uppercase)

                if let today = appModel.weekStore.today {
                    Text(today.mealTitle)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(VecklyDesign.Colors.inkDeep)
                    Text(today.detail)
                        .font(.body)
                        .foregroundStyle(VecklyDesign.Colors.inkMid)
                    if let recipe = today.recipe {
                        Button("View recipe") {
                            selectedRecipe = recipe
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    Text("No dinner planned")
                        .font(.title2.weight(.semibold))
                    Text("Once a week exists, it will show up here first.")
                        .foregroundStyle(VecklyDesign.Colors.inkMid)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("todayMealPanel")
        }
    }

    private var weekList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Plan")
                .font(.headline)
                .foregroundStyle(VecklyDesign.Colors.inkDeep)

            ForEach(appModel.weekStore.dayRows) { day in
                Button {
                    selectedRecipe = day.recipe
                } label: {
                    WeekDayRow(day: day)
                }
                .buttonStyle(.plain)
                .disabled(day.recipe == nil)
            }
        }
        .accessibilityIdentifier("weekPlanList")
    }
}

struct WeekDayRow: View {
    let day: WeekDayRowViewModel

    var body: some View {
        VecklyCard {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(day.weekdayLabel)
                        .font(.headline)
                    Text(day.dateLabel)
                        .font(.caption)
                        .foregroundStyle(VecklyDesign.Colors.inkFaint)
                }
                .frame(width: 92, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text(day.mealTitle)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(day.isEmpty ? VecklyDesign.Colors.inkFaint : VecklyDesign.Colors.inkDeep)
                    Text(day.detail)
                        .font(.footnote)
                        .foregroundStyle(VecklyDesign.Colors.inkMid)
                }

                Spacer()

                if day.isToday {
                    Text("Today")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(VecklyDesign.Colors.hearthOrange)
                }
            }
        }
    }
}

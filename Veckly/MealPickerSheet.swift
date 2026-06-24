import SwiftUI

/// The conversion `WeekTabView` already needed to call `assignMeal` — shared
/// here since the preview step (below) needs the same shape to hand off to
/// `RecipeDetailView`.
extension FullRecipe {
    var asWeekSummaryRecipe: WeekSummaryRecipe {
        WeekSummaryRecipe(
            id: id,
            title: title,
            description: description,
            servings: servings,
            prepTimeMinutes: prepTimeMinutes,
            cookTimeMinutes: cookTimeMinutes,
            tags: tags
        )
    }
}

struct MealPickerSheet: View {
    let day: WeekDayRowViewModel
    let isSkipped: Bool
    /// Set when this (recipe-less) day is already covered by another day's
    /// leftovers — shown as a banner above the recipe list instead of the
    /// usual blank-picker look.
    var coverage: PrepBatchCoverage? = nil
    let householdID: String
    let onSelect: (FullRecipe) -> Void
    let onClear: () -> Void
    let onSkip: () -> Void
    let onMarkAsLeftover: (String) -> Void
    let onMarkAsLeftoverNoRecipe: () -> Void
    let onRemoveCoverage: () -> Void
    let onDismiss: () -> Void

    @Environment(AppModel.self) private var appModel
    @State private var searchText = ""
    /// Pushed when a recipe row is tapped — reading about a dish doesn't
    /// commit it; only the confirm action inside the preview does. Keyed by
    /// id (not the recipe itself) since the generated `FullRecipe` type isn't
    /// `Hashable`, which `navigationDestination(item:)` requires.
    @State private var previewRecipeID: String?
    /// Set once a recipe has been confirmed for this day in this sheet
    /// session — switches the root content from the picker list to the same
    /// view `DayDetailSheet` uses, instead of dismissing.
    @State private var confirmedRecipe: WeekSummaryRecipe?
    @State private var showClearConfirmation = false

    private var recipes: [FullRecipe] { appModel.recipeStore.recipes }

    var filtered: [FullRecipe] {
        guard !searchText.isEmpty else { return recipes }
        return recipes.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    private var likedRecipes: [FullRecipe] {
        filtered.filter { appModel.feedbackStore.vote(for: $0.id) == .up }
    }

    private var otherRecipes: [FullRecipe] {
        filtered.filter { appModel.feedbackStore.vote(for: $0.id) != .up }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let confirmedRecipe {
                    DayDetailContent(
                        day: day.withPlannedRecipe(confirmedRecipe),
                        householdID: householdID,
                        onViewRecipe: { previewRecipeID = confirmedRecipe.id },
                        onSwap: { self.confirmedRecipe = nil },
                        onSkip: { onSkip(); onDismiss() },
                        onClear: onClear,
                        onMarkAsLeftover: { onMarkAsLeftover(confirmedRecipe.id) }
                    )
                } else if appModel.recipeStore.isLoading {
                    VStack {
                        ProgressView()
                            .tint(VecklyDesign.Colors.hearthOrange)
                        Text("recipes.loadingEllipsis")
                            .foregroundStyle(VecklyDesign.Colors.inkMid)
                            .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage = appModel.recipeStore.errorMessage {
                    VStack(spacing: 12) {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(VecklyDesign.Colors.inkMid)
                            .multilineTextAlignment(.center)
                        Button("common.tryAgain") {
                            Task { await loadRecipes() }
                        }
                        .foregroundStyle(VecklyDesign.Colors.hearthOrange)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else if filtered.isEmpty && !searchText.isEmpty {
                    ContentUnavailableView(
                        L10n.string("recipes.noResults"),
                        systemImage: "fork.knife",
                        description: Text(L10n.string("recipes.tryDifferentSearchTerm"))
                    )
                } else {
                    recipeList
                }
            }
            .navigationTitle(day.weekdayLabel)
            .navigationBarTitleDisplayMode(.inline)
            .modifier(SearchableWhenPickingModifier(isPicking: confirmedRecipe == nil, searchText: $searchText))
            .navigationDestination(item: $previewRecipeID) { recipeID in
                if let recipe = recipes.first(where: { $0.id == recipeID }) {
                    RecipeDetailView(
                        recipe: recipe.asWeekSummaryRecipe,
                        householdID: householdID,
                        confirmButtonTitle: confirmedRecipe == nil ? L10n.format("meal.chooseForDay", day.weekdayLabel) : nil,
                        onConfirm: confirmedRecipe == nil ? {
                            onSelect(recipe)
                            confirmedRecipe = recipe.asWeekSummaryRecipe
                            previewRecipeID = nil
                        } : nil
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel", action: onDismiss)
                }
                if confirmedRecipe != nil || (!day.isEmpty && !isSkipped) {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("meal.clear", role: .destructive) {
                            showClearConfirmation = true
                        }
                        .foregroundStyle(.red)
                    }
                }
                if confirmedRecipe == nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: { onSkip(); onDismiss() }) {
                            Image(systemName: isSkipped ? "calendar.badge.plus" : "calendar.badge.minus")
                        }
                        .accessibilityLabel(isSkipped ? L10n.format("accessibility.planDayInstead", day.weekdayLabel) : L10n.format("accessibility.skipDay", day.weekdayLabel))
                    }
                }
            }
            .confirmationDialog(L10n.string("meal.removeConfirmation"), isPresented: $showClearConfirmation, titleVisibility: .visible) {
                Button("meal.clear", role: .destructive) { onClear() }
                Button("common.cancel", role: .cancel) {}
            }
        }
        .task { await loadRecipes() }
    }

    private var recipeList: some View {
        List {
            if let coverage {
                coverageBanner(coverage)
            } else {
                Section {
                    Button(action: onMarkAsLeftoverNoRecipe) {
                        HStack {
                            Image(systemName: "arrow.3.trianglepath")
                                .foregroundStyle(VecklyDesign.Colors.inkMid)
                            Text("prep.markAsLeftovers")
                                .foregroundStyle(VecklyDesign.Colors.inkMid)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            if filtered.isEmpty {
                Section {
                    ContentUnavailableView(
                        L10n.string("recipes.empty.title"),
                        systemImage: "fork.knife",
                        description: Text(L10n.string("recipes.empty.pickerMessage"))
                    )
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                if !likedRecipes.isEmpty {
                    Section(L10n.string("recipes.liked")) {
                        ForEach(likedRecipes) { recipe in
                            Button { previewRecipeID = recipe.id } label: { RecipePickerRow(recipe: recipe) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                if !otherRecipes.isEmpty {
                    Section(likedRecipes.isEmpty ? "" : L10n.string("recipes.all")) {
                        ForEach(otherRecipes) { recipe in
                            Button { previewRecipeID = recipe.id } label: { RecipePickerRow(recipe: recipe) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func coverageBanner(_ coverage: PrepBatchCoverage) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "arrow.3.trianglepath")
                        .foregroundStyle(VecklyDesign.Colors.inkMid)
                    Text(L10n.format("prep.coveredByLeftovers", coverage.recipeTitle, WeekCalendar.shortDateLabel(yyyyMmDd: coverage.cookDate)))
                        .foregroundStyle(VecklyDesign.Colors.inkMid)
                }
                Button(role: .destructive, action: onRemoveCoverage) {
                    Text("prep.removeCoverage")
                }
                .buttonStyle(.borderless)
            }
            .padding(.vertical, 4)
        }
    }

    private func loadRecipes() async {
        await appModel.loadRecipesAndSeedFeedback(householdID: householdID)
    }
}

/// `.searchable` only while actively picking — once a recipe is confirmed the
/// root content switches to `DayDetailContent`, where a search field makes no
/// sense.
private struct SearchableWhenPickingModifier: ViewModifier {
    let isPicking: Bool
    @Binding var searchText: String

    func body(content: Content) -> some View {
        if isPicking {
            content.searchable(text: $searchText, prompt: L10n.string("recipes.search"))
        } else {
            content
        }
    }
}

private struct RecipePickerRow: View {
    let recipe: FullRecipe

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(recipe.title)
                .font(.body.weight(.medium))
                .foregroundStyle(VecklyDesign.Colors.inkDeep)
            HStack(spacing: 6) {
                Text(L10n.format("format.servings", recipe.servings))
                if let total = cookTime {
                    Text("·")
                    Text("\(total) min")
                }
            }
            .font(.caption)
            .foregroundStyle(VecklyDesign.Colors.inkFaint)
        }
        .padding(.vertical, 4)
    }

    private var cookTime: Int? {
        let t = (recipe.prepTimeMinutes ?? 0) + (recipe.cookTimeMinutes ?? 0)
        return t > 0 ? t : nil
    }
}

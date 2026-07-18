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
    @State private var showSkipConfirmation = false
    @State private var showAddRecipeSheet = false
    @State private var selectedIntent: MealSwapIntent = .any

    private var recipes: [FullRecipe] { appModel.recipeStore.recipes }

    private var rankedResult: MealSwapIntentRanker.Result {
        let matchesSearch = searchText.isEmpty
            ? recipes
            : recipes.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        return MealSwapIntentRanker.rankWithFallback(
            matchesSearch,
            intent: searchText.isEmpty ? selectedIntent : .any,
            currentRecipe: day.recipe
        )
    }

    var filtered: [FullRecipe] {
        rankedResult.recipes
    }

    private var likedRecipes: [FullRecipe] {
        filtered.filter { appModel.feedbackStore.vote(for: $0.id) == .up }
    }

    private var otherRecipes: [FullRecipe] {
        filtered.filter { appModel.feedbackStore.vote(for: $0.id) != .up }
    }

    /// AI-ranked picks (see `RecipeRecommendationStore`), resolved against
    /// the loaded recipe list and ranked in the order Claude returned them.
    /// Hidden while searching — suggestions answer "what should we cook?",
    /// not "find this specific dish."
    private var suggestedRecipes: [(recipe: FullRecipe, reason: String)] {
        guard searchText.isEmpty else { return [] }
        let recipesByID = Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, $0) })
        return appModel.recipeRecommendationStore.recommendations(for: householdID).compactMap { recommendation in
            guard let recipe = recipesByID[recommendation.mealID] else { return nil }
            return (recipe, recommendation.reason)
        }
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
                    Button(confirmedRecipe != nil ? "common.done" : "common.cancel", action: onDismiss)
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
                        Button(isSkipped ? "meal.plan" : "meal.skip") {
                            if day.recipe != nil && !isSkipped {
                                showSkipConfirmation = true
                            } else {
                                onSkip(); onDismiss()
                            }
                        }
                        .accessibilityLabel(isSkipped ? L10n.format("accessibility.planDayInstead", day.weekdayLabel) : L10n.format("accessibility.skipDay", day.weekdayLabel))
                    }
                }
            }
            .confirmationDialog(L10n.string("meal.removeConfirmation"), isPresented: $showClearConfirmation, titleVisibility: .visible) {
                Button("meal.clear", role: .destructive) { onClear() }
                Button("common.cancel", role: .cancel) {}
            }
            .confirmationDialog(L10n.string("meal.skipConfirmation"), isPresented: $showSkipConfirmation, titleVisibility: .visible) {
                Button("meal.skip", role: .destructive) { onSkip(); onDismiss() }
                Button("common.cancel", role: .cancel) {}
            }
        }
        .task { await loadRecipes() }
        .sheet(isPresented: $showAddRecipeSheet) {
            RecipeFormSheet(mode: .create) { draft in
                guard let household = appModel.householdStore.activeHousehold else { return }
                // A recipe created here (new or imported) is both saved to
                // the household's Family recipes (createRecipe already does
                // that) and assigned to the day being planned — the same
                // outcome as tapping an existing row, so it follows the
                // identical onSelect → confirmedRecipe hand-off (beslut 18).
                let recipe = try await appModel.recipeStore.createRecipe(householdID: household.id, draft: draft)
                onSelect(recipe)
                confirmedRecipe = recipe.asWeekSummaryRecipe
            }
        }
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

            if searchText.isEmpty {
                swapIntentSection
            }

            if rankedResult.isFallback {
                intentFallbackSection
            }

            if !suggestedRecipes.isEmpty {
                Section(L10n.string("recipes.suggestions")) {
                    ForEach(suggestedRecipes, id: \.recipe.id) { entry in
                        Button { previewRecipeID = entry.recipe.id } label: {
                            RecipePickerRow(recipe: entry.recipe, reason: entry.reason)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if filtered.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label(L10n.string("recipes.empty.title"), systemImage: "fork.knife")
                    } description: {
                        Text(L10n.string("recipes.empty.pickerMessage"))
                    } actions: {
                        Button("recipe.add") { showAddRecipeSheet = true }
                            .buttonStyle(.borderedProminent)
                            .tint(VecklyDesign.Colors.hearthOrange)
                    }
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
                addRecipeRow
            }
        }
        .listStyle(.insetGrouped)
    }

    /// Quiet entry point at the end of the picker's results — for when
    /// nothing above is quite right, without competing with the prominent
    /// empty-state CTA above (beslut 18: "utan att appen framstår som en
    /// receptapp").
    private var addRecipeRow: some View {
        Section {
            Button { showAddRecipeSheet = true } label: {
                Label(L10n.string("recipe.add"), systemImage: "plus.circle")
                    .foregroundStyle(VecklyDesign.Colors.inkMid)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("mealPickerAddRecipeRow")
        }
    }

    private var intentFallbackSection: some View {
        Section {
            Label {
                Text("meal.swapIntent.fallback")
                    .font(.subheadline)
                    .foregroundStyle(VecklyDesign.Colors.inkMid)
            } icon: {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(VecklyDesign.Colors.hearthOrange)
            }
        }
    }

    private var swapIntentSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(MealSwapIntent.allCases) { intent in
                        Button {
                            selectedIntent = intent
                        } label: {
                            Text(intent.label)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(selectedIntent == intent ? .white : VecklyDesign.Colors.inkMid)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(selectedIntent == intent ? VecklyDesign.Colors.hearthOrange : Color("chipSurface"))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("meal.swapIntent.title")
        } footer: {
            if let reason = selectedIntent.reasonLabel {
                Text(verbatim: reason)
            }
        }
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
        guard let profile = appModel.householdStore.cachedProfile(for: householdID) else { return }
        await appModel.recipeRecommendationStore.loadIfNeeded(
            householdID: householdID,
            householdProfile: profile,
            feedbackVotes: appModel.feedbackStore.allVotes,
            recipes: appModel.recipeStore.recipes
        )
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
    /// Set only for rows in the "Suggestions for you" section — Claude's
    /// one-sentence reason for this pick, in the same language as the title.
    var reason: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(recipe.title)
                .font(.body.weight(.medium))
                .foregroundStyle(VecklyDesign.Colors.inkDeep)
            if let reason {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(VecklyDesign.Colors.hearthOrange)
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                chip(L10n.format("format.servings", recipe.servings))
                if let total = cookTime {
                    chip("\(total) min")
                }
                if let cuisine = recipe.cuisine {
                    chip(cuisine)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(VecklyDesign.Colors.inkMid)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color("chipSurface"))
            .clipShape(Capsule())
    }

    private var cookTime: Int? {
        let t = (recipe.prepTimeMinutes ?? 0) + (recipe.cookTimeMinutes ?? 0)
        return t > 0 ? t : nil
    }
}

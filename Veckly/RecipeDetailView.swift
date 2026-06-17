import SwiftUI

struct RecipeDetailView: View {
    let recipe: WeekSummaryRecipe
    let householdID: String
    /// When provided, shows a "Skip / Plan this day" row at the top of the sheet.
    var isSkipped: Bool? = nil
    var onSkip: (() -> Void)? = nil

    @Environment(AppModel.self) private var appModel
    @State private var fullRecipe: FullRecipe?
    @State private var isLoadingFull = false

    // MARK: - Scaling

    /// Total people in the household — 0 means profile not loaded yet (no scaling).
    private var householdSize: Int {
        guard let hid = appModel.householdStore.activeHousehold?.id,
              let profile = appModel.householdStore.cachedProfile(for: hid) else { return 0 }
        return profile.adults + profile.children
    }

    /// Base servings from the full recipe; falls back to the summary field.
    private var baseServings: Int {
        fullRecipe?.servings ?? recipe.servings
    }

    /// The servings count to display: household size when known, otherwise the base.
    private var displayServings: Int {
        householdSize > 0 ? householdSize : baseServings
    }

    private var scaleFactor: Double {
        IngredientScaler.scaleFactor(householdSize: displayServings, recipeServings: baseServings)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Day-level action — surfaced before recipe content so it is
                    // reachable without scrolling.
                    if let isSkipped, let onSkip {
                        skipDayRow(isSkipped: isSkipped, onSkip: onSkip)
                    }

                    headerSection

                    if isLoadingFull {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 12)
                    } else if let full = fullRecipe {
                        if !full.ingredients.isEmpty {
                            ingredientsSection(full.ingredients)
                        }
                        if !full.steps.isEmpty {
                            stepsSection(full.steps)
                        }
                    }

                    if !recipe.tags.isEmpty {
                        FlowTags(tags: recipe.tags)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(VecklyDesign.Colors.canvas)
            .navigationTitle("Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .task { await loadFull() }
        }
    }

    @ViewBuilder
    private func skipDayRow(isSkipped: Bool, onSkip: @escaping () -> Void) -> some View {
        Button(action: onSkip) {
            HStack(spacing: 10) {
                Image(systemName: isSkipped ? "calendar.badge.plus" : "calendar.badge.minus")
                    .font(.body)
                    .foregroundStyle(VecklyDesign.Colors.inkMid)
                Text(isSkipped ? "Plan this day instead" : "Skip this day")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(VecklyDesign.Colors.inkMid)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(VecklyDesign.Colors.surfaceStrong)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSkipped ? "Plan this day instead" : "Skip this day")
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(recipe.title)
                .font(VecklyDesign.Typography.displayHeading(size: 28))

            let totalMinutes = [recipe.prepTimeMinutes, recipe.cookTimeMinutes].compactMap { $0 }.reduce(0, +)
            HStack(spacing: 16) {
                Label("\(displayServings) servings", systemImage: "person.2")
                if totalMinutes > 0 {
                    Label("\(totalMinutes) min", systemImage: "clock")
                }
            }
            .font(.footnote)
            .foregroundStyle(VecklyDesign.Colors.inkMid)

            if !recipe.description.isEmpty {
                Text(recipe.description)
                    .foregroundStyle(VecklyDesign.Colors.inkMid)
            }
        }
    }

    @ViewBuilder
    private func ingredientsSection(_ ingredients: [RecipeIngredient]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ingredients")
                .font(.headline)
                .foregroundStyle(VecklyDesign.Colors.inkDeep)

            VecklyCard {
                VStack(spacing: 0) {
                    ForEach(Array(ingredients.enumerated()), id: \.offset) { index, ing in
                        HStack(spacing: 12) {
                            let scaledAmount = IngredientScaler.scale(amount: ing.amount, unit: ing.unit, by: scaleFactor)
                            Text([scaledAmount, ing.unit].compactMap { $0 }.joined(separator: " "))
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(VecklyDesign.Colors.inkMid)
                                .frame(width: 64, alignment: .trailing)
                            Text(ing.item)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 8)
                        if index < ingredients.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func stepsSection(_ steps: [RecipeStep]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Instructions")
                .font(.headline)
                .foregroundStyle(VecklyDesign.Colors.inkDeep)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(VecklyDesign.Colors.hearthOrange)
                            .frame(width: 20, alignment: .center)
                            .padding(.top, 2)
                        Text(step.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func loadFull() async {
        // Ensure household profile is loaded so scaling is available.
        await appModel.householdStore.loadHouseholdDetails(householdID: householdID)

        guard fullRecipe == nil else { return }
        isLoadingFull = true
        defer { isLoadingFull = false }
        do {
            fullRecipe = try await appModel.recipeStore.getOrFetchFull(
                householdID: householdID,
                recipeID: recipe.id
            )
        } catch {
            // header data already visible; silent failure is acceptable
        }
    }
}

struct FlowTags: View {
    let tags: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(VecklyDesign.Colors.surfaceStrong)
                    .clipShape(Capsule())
            }
        }
    }
}

import SwiftUI

struct RecipeDetailView: View {
    let recipe: WeekSummaryRecipe
    let householdID: String

    @Environment(AppModel.self) private var appModel
    @State private var fullRecipe: FullRecipe?
    @State private var isLoadingFull = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
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

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(recipe.title)
                .font(VecklyDesign.Typography.displayHeading(size: 28))

            let totalMinutes = [recipe.prepTimeMinutes, recipe.cookTimeMinutes].compactMap { $0 }.reduce(0, +)
            HStack(spacing: 16) {
                Label("\(recipe.servings) servings", systemImage: "person.2")
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
                            Text([ing.amount, ing.unit].compactMap { $0 }.joined(separator: " "))
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
        guard fullRecipe == nil else { return }
        isLoadingFull = true
        defer { isLoadingFull = false }
        do {
            fullRecipe = try await appModel.weekStore.fetchFullRecipe(householdID: householdID, recipeID: recipe.id)
        } catch {
            // keep existing summary data; no crash on network failure
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

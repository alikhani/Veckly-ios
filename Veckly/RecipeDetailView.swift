import SwiftUI

struct RecipeDetailView: View {
    let recipe: WeekSummaryRecipe

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(recipe.title)
                        .font(.system(size: 28, weight: .bold, design: .serif))
                    if !recipe.description.isEmpty {
                        Text(recipe.description)
                            .foregroundStyle(VecklyDesign.Colors.inkMid)
                    }
                    Text("\(recipe.servings) servings")
                        .font(.headline)
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

import SwiftUI

enum RecipeFormMode {
    case create
    case edit(FullRecipe)
}

struct RecipeFormSheet: View {
    let mode: RecipeFormMode
    let onSave: (RecipeDraft) async throws -> Void

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var draft: RecipeDraft
    @State private var urlText = ""
    @State private var isImporting = false
    @State private var isFilling = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(mode: RecipeFormMode, onSave: @escaping (RecipeDraft) async throws -> Void) {
        self.mode = mode
        self.onSave = onSave
        switch mode {
        case .create: _draft = State(initialValue: .empty)
        case let .edit(recipe): _draft = State(initialValue: RecipeDraft(from: recipe))
        }
    }

    var isNew: Bool { if case .create = mode { return true } else { return false } }

    var body: some View {
        NavigationStack {
            Form {
                if isNew { importSection }
                basicSection
                timingSection
                ingredientsSection
                stepsSection
            }
            .navigationTitle(isNew ? "New Recipe" : "Edit Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { Task { await save() } }
                            .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil), actions: {
                Button("OK") { errorMessage = nil }
            }, message: { Text(errorMessage ?? "") })
        }
    }

    private var importSection: some View {
        Section("Import from URL") {
            TextField("https://...", text: $urlText)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button {
                Task { await importFromURL() }
            } label: {
                if isImporting {
                    HStack { ProgressView(); Text("Importing…") }
                } else {
                    Text("Import recipe")
                }
            }
            .disabled(urlText.isEmpty || isImporting)
        }
    }

    private var basicSection: some View {
        Section {
            TextField("Title", text: $draft.title)
            if !draft.title.trimmingCharacters(in: .whitespaces).isEmpty {
                Button {
                    Task { await fillWithAI() }
                } label: {
                    if isFilling {
                        HStack { ProgressView(); Text("Filling in with AI…") }
                    } else {
                        Label("Fill with AI", systemImage: "sparkles")
                            .foregroundStyle(VecklyDesign.Colors.hearthOrange)
                    }
                }
                .disabled(isFilling)
            }
            TextField("Description", text: $draft.description, axis: .vertical)
                .lineLimit(2...5)
        }
    }

    private var timingSection: some View {
        Section {
            Stepper("Servings: \(draft.servings)", value: $draft.servings, in: 1...20)
            HStack {
                Text("Prep")
                Spacer()
                TextField("min", value: $draft.prepTimeMinutes, format: .number)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numberPad)
                    .frame(width: 60)
            }
            HStack {
                Text("Cook")
                Spacer()
                TextField("min", value: $draft.cookTimeMinutes, format: .number)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numberPad)
                    .frame(width: 60)
            }
        }
    }

    private var ingredientsSection: some View {
        Section("Ingredients") {
            ForEach($draft.ingredients) { $ing in
                HStack(spacing: 8) {
                    TextField("Amount", text: $ing.amount)
                        .frame(width: 56)
                        .keyboardType(.decimalPad)
                    TextField("Unit", text: $ing.unit)
                        .frame(width: 52)
                    TextField("Ingredient", text: $ing.item)
                }
                .font(.body)
            }
            .onDelete { draft.ingredients.remove(atOffsets: $0) }
            Button("Add ingredient") {
                draft.ingredients.append(DraftIngredient())
            }
        }
    }

    private var stepsSection: some View {
        Section("Steps") {
            ForEach(draft.steps.indices, id: \.self) { i in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(i + 1).")
                        .foregroundStyle(VecklyDesign.Colors.inkFaint)
                        .frame(width: 24, alignment: .leading)
                    TextField("Step", text: $draft.steps[i], axis: .vertical)
                        .lineLimit(2...6)
                }
            }
            .onDelete { draft.steps.remove(atOffsets: $0) }
            Button("Add step") { draft.steps.append("") }
        }
    }

    private func importFromURL() async {
        isImporting = true
        errorMessage = nil
        defer { isImporting = false }
        do {
            draft = try await appModel.apiClient.importRecipeFromURL(urlText)
        } catch {
            errorMessage = "Could not import recipe from that URL."
        }
    }

    private func fillWithAI() async {
        isFilling = true
        errorMessage = nil
        defer { isFilling = false }
        do {
            let filled = try await appModel.apiClient.fillInRecipe(title: draft.title)
            draft.ingredients = filled.ingredients
            draft.steps = filled.steps
            if draft.description.isEmpty { draft.description = "" }
            if draft.prepTimeMinutes == nil { draft.prepTimeMinutes = filled.prepTimeMinutes }
        } catch {
            errorMessage = "AI fill-in failed. You can fill in manually."
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await onSave(draft)
            dismiss()
        } catch {
            errorMessage = "Could not save recipe. Please try again."
        }
    }
}

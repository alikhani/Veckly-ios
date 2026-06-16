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
    @State private var initialDraft: RecipeDraft
    @State private var urlText = ""
    @State private var isImporting = false
    @State private var isFilling = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showDiscardConfirmation = false

    init(mode: RecipeFormMode, onSave: @escaping (RecipeDraft) async throws -> Void) {
        self.mode = mode
        self.onSave = onSave
        switch mode {
        case .create:
            _draft = State(initialValue: .empty)
            _initialDraft = State(initialValue: .empty)
        case let .edit(recipe):
            let draft = RecipeDraft(from: recipe)
            _draft = State(initialValue: draft)
            _initialDraft = State(initialValue: draft)
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
                    Button("Cancel") {
                        if draft == initialDraft {
                            dismiss()
                        } else {
                            showDiscardConfirmation = true
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { Task { await save() } }
                            .disabled(normalizedTitle.isEmpty || isSaving || isImporting || isFilling)
                    }
                }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil), actions: {
                Button("OK") { errorMessage = nil }
            }, message: { Text(errorMessage ?? "") })
            .confirmationDialog(
                "Discard changes?",
                isPresented: $showDiscardConfirmation,
                titleVisibility: .visible
            ) {
                Button("Discard Changes", role: .destructive) { dismiss() }
                Button("Cancel", role: .cancel) {}
            }
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
            .disabled(normalizedURL.isEmpty || isImporting || isSaving || isFilling)
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
                .disabled(isFilling || isSaving || isImporting)
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
        let url = normalizedURL
        guard !url.isEmpty else { return }
        isImporting = true
        errorMessage = nil
        defer { isImporting = false }
        do {
            draft = try await appModel.recipeStore.importFromURL(url)
            urlText = url
        } catch {
            errorMessage = "Could not import recipe from that URL."
        }
    }

    private func fillWithAI() async {
        let title = normalizedTitle
        guard !title.isEmpty else { return }
        isFilling = true
        errorMessage = nil
        defer { isFilling = false }
        do {
            let filled = try await appModel.recipeStore.fillIn(title: title)
            if draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { draft.title = filled.title }
            if draft.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { draft.description = filled.description }
            if draft.prepTimeMinutes == nil { draft.prepTimeMinutes = filled.prepTimeMinutes }
            if draft.cookTimeMinutes == nil { draft.cookTimeMinutes = filled.cookTimeMinutes }
            draft.ingredients = filled.ingredients
            draft.steps = filled.steps
        } catch {
            errorMessage = "AI fill-in failed. You can fill in manually."
        }
    }

    private func save() async {
        var draftToSave = draft
        draftToSave.title = normalizedTitle
        draftToSave.description = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceURL = draft.sourceUrl?.trimmingCharacters(in: .whitespacesAndNewlines)
        draftToSave.sourceUrl = sourceURL?.isEmpty == true ? nil : sourceURL
        draftToSave.ingredients = draft.ingredients.map {
            DraftIngredient(
                item: $0.item.trimmingCharacters(in: .whitespacesAndNewlines),
                amount: $0.amount.trimmingCharacters(in: .whitespacesAndNewlines),
                unit: $0.unit.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        draftToSave.steps = draft.steps.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        isSaving = true
        defer { isSaving = false }
        do {
            try await onSave(draftToSave)
            dismiss()
        } catch {
            errorMessage = "Could not save recipe. Please try again."
        }
    }

    private var normalizedTitle: String {
        draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedURL: String {
        urlText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

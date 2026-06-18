import SwiftUI

enum RecipeFormMode {
    case create
    case edit(FullRecipe)
}

private enum RecipeFormTab: String, CaseIterable, Identifiable {
    case write = "Write"
    case importRecipe = "Import"

    var id: Self { self }
}

private enum RecipeImportInputMode: String, CaseIterable, Identifiable {
    case link = "Link"
    case text = "Text"

    var id: Self { self }
}

struct RecipeFormSheet: View {
    let mode: RecipeFormMode
    let onSave: (RecipeDraft) async throws -> Void

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var draft: RecipeDraft
    @State private var initialDraft: RecipeDraft
    @State private var selectedTab: RecipeFormTab
    @State private var selectedImportMode: RecipeImportInputMode = .link
    @State private var urlText = ""
    @State private var importText = ""
    @State private var importSourceURLText = ""
    @State private var tagsText = ""
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
            _selectedTab = State(initialValue: .write)
            _tagsText = State(initialValue: "")
        case let .edit(recipe):
            let draft = RecipeDraft(from: recipe)
            _draft = State(initialValue: draft)
            _initialDraft = State(initialValue: draft)
            _selectedTab = State(initialValue: .write)
            _tagsText = State(initialValue: recipe.tags.joined(separator: ", "))
        }
    }

    var isNew: Bool { if case .create = mode { return true } else { return false } }

    var body: some View {
        NavigationStack {
            Form {
                if isNew { modeSection }
                if selectedTab == .importRecipe {
                    importSection
                } else {
                    recipeFields
                }
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

    @ViewBuilder
    private var recipeFields: some View {
        if isNew, let sourceURL = draft.sourceUrl, !sourceURL.isEmpty {
            sourceSection(sourceURL)
        }
        basicSection
        timingSection
        ingredientsSection
        stepsSection
        tagsSection
    }

    private var modeSection: some View {
        Section {
            Picker("Mode", selection: $selectedTab) {
                ForEach(RecipeFormTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isSaving || isImporting || isFilling)
        }
    }

    @ViewBuilder
    private var importSection: some View {
        Section {
            Picker("Import type", selection: $selectedImportMode) {
                ForEach(RecipeImportInputMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isSaving || isImporting || isFilling)
        }

        if selectedImportMode == .link {
            linkImportSection
        } else {
            textImportSection
        }
    }

    private var linkImportSection: some View {
        Section("Link") {
            TextField("Recipe page URL", text: $urlText)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button {
                Task { await importFromURL() }
            } label: {
                if isImporting {
                    HStack { ProgressView(); Text("Importing…") }
                } else {
                    Label("Create draft", systemImage: "square.and.arrow.down")
                }
            }
            .disabled(normalizedURL.isEmpty || isImporting || isSaving || isFilling)
        }
    }

    private var textImportSection: some View {
        Section("Text") {
            TextEditor(text: $importText)
                .frame(minHeight: 140)
                .overlay(alignment: .topLeading) {
                    if normalizedImportText.isEmpty {
                        Text("Paste recipe text")
                            .foregroundStyle(VecklyDesign.Colors.inkFaint)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                    }
                }
            TextField("Source URL", text: $importSourceURLText)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button {
                Task { await importFromText() }
            } label: {
                if isImporting {
                    HStack { ProgressView(); Text("Importing…") }
                } else {
                    Label("Create draft", systemImage: "text.page")
                }
            }
            .disabled(normalizedImportText.isEmpty || isImporting || isSaving || isFilling)
        }
    }

    private func sourceSection(_ sourceURL: String) -> some View {
        Section {
            LabeledContent("Draft source") {
                Text(sourceURL)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(VecklyDesign.Colors.inkFaint)
            }
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

    private var tagsSection: some View {
        Section("Tags") {
            TextField("e.g. quick, vegetarian, kid-friendly", text: $tagsText)
                .autocorrectionDisabled()
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
            selectedTab = .write
        } catch APIError.recipeImport(let failure) {
            errorMessage = failure.message
        } catch {
            errorMessage = "Could not create a draft from that URL."
        }
    }

    private func importFromText() async {
        let text = normalizedImportText
        guard !text.isEmpty else { return }
        isImporting = true
        errorMessage = nil
        defer { isImporting = false }
        do {
            draft = try await appModel.recipeStore.importFromText(text, sourceURL: normalizedImportSourceURL)
            importText = text
            selectedTab = .write
        } catch APIError.recipeImport(let failure) {
            errorMessage = failure.message
        } catch {
            errorMessage = "Could not create a draft from that text."
        }
    }

    private func fillWithAI() async {
        let title = normalizedTitle
        guard !title.isEmpty else { return }
        isFilling = true
        errorMessage = nil
        defer { isFilling = false }
        do {
            var context = draft
            context.title = title
            let filled = try await appModel.recipeStore.fillIn(draft: context)
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
        if draftToSave.sourceUrl == nil && draftToSave.source == .urlImport {
            draftToSave.source = .userCreated
        }
        draftToSave.ingredients = draft.ingredients.map {
            DraftIngredient(
                item: $0.item.trimmingCharacters(in: .whitespacesAndNewlines),
                amount: $0.amount.trimmingCharacters(in: .whitespacesAndNewlines),
                unit: $0.unit.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        draftToSave.steps = draft.steps.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        draftToSave.tags = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

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

    private var normalizedImportText: String {
        importText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedImportSourceURL: String? {
        let sourceURL = importSourceURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        return sourceURL.isEmpty ? nil : sourceURL
    }
}

private extension RecipeImportFailure {
    var message: String {
        switch self {
        case .invalidURL:
            return "Enter a valid recipe page URL."
        case .unsupportedURL:
            return "This kind of link is not supported yet."
        case .fetchFailed:
            return "We could not access that page."
        case .noRecipeFound:
            return "We could not find enough recipe detail on that page."
        case .rateLimited:
            return "Wait a moment before importing another recipe."
        case .importFailed:
            return "Could not create a draft from that URL."
        case .unsupportedSocialSource:
            return "This social platform is not supported yet."
        case .captionRequired:
            return "Paste the caption or text from the post to import the recipe."
        }
    }
}

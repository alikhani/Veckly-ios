import SwiftUI

enum RecipeFormMode {
    case create
    case edit(FullRecipe)
}

private enum RecipeFormTab: String, CaseIterable, Identifiable {
    case write
    case importRecipe

    var id: Self { self }

    var displayLabel: String {
        switch self {
        case .write: return L10n.string("recipeForm.tab.write")
        case .importRecipe: return L10n.string("recipeForm.tab.import")
        }
    }
}

private enum RecipeImportInputMode: String, CaseIterable, Identifiable {
    case link
    case text

    var id: Self { self }

    var displayLabel: String {
        switch self {
        case .link: return L10n.string("recipeForm.import.link")
        case .text: return L10n.string("recipeForm.import.text")
        }
    }
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
            .navigationTitle(isNew ? L10n.string("recipeForm.newTitle") : L10n.string("recipeForm.editTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") {
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
                        Button("common.save") { Task { await save() } }
                            .disabled(normalizedTitle.isEmpty || isSaving || isImporting || isFilling)
                    }
                }
            }
            .alert(L10n.string("common.error"),
                isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }),
                actions: { Button("common.ok") { errorMessage = nil } },
                message: { Text(errorMessage ?? "") }
            )
            .confirmationDialog(
                L10n.string("recipeForm.discardConfirmation"),
                isPresented: $showDiscardConfirmation,
                titleVisibility: .visible
            ) {
                Button("recipeForm.discardChanges", role: .destructive) { dismiss() }
                Button("common.cancel", role: .cancel) {}
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
            Picker("recipeForm.mode", selection: $selectedTab) {
                ForEach(RecipeFormTab.allCases) { tab in
                    Text(tab.displayLabel).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isSaving || isImporting || isFilling)
        }
    }

    @ViewBuilder
    private var importSection: some View {
        Section {
            Picker("recipeForm.importType", selection: $selectedImportMode) {
                ForEach(RecipeImportInputMode.allCases) { mode in
                    Text(mode.displayLabel).tag(mode)
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
        Section("recipeForm.import.link") {
            TextField(L10n.string("recipeForm.recipePageURL"), text: $urlText)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button {
                Task { await importFromURL() }
            } label: {
                if isImporting {
                    HStack { ProgressView(); Text("recipeForm.importing") }
                } else {
                    Label("recipeForm.createDraft", systemImage: "square.and.arrow.down")
                }
            }
            .disabled(normalizedURL.isEmpty || isImporting || isSaving || isFilling)
        }
    }

    private var textImportSection: some View {
        Section("recipeForm.import.text") {
            TextEditor(text: $importText)
                .frame(minHeight: 140)
                .overlay(alignment: .topLeading) {
                    if normalizedImportText.isEmpty {
                        Text("recipeForm.pasteRecipeText")
                            .foregroundStyle(VecklyDesign.Colors.inkFaint)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                    }
                }
            TextField(L10n.string("recipeForm.sourceURL"), text: $importSourceURLText)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button {
                Task { await importFromText() }
            } label: {
                if isImporting {
                    HStack { ProgressView(); Text("recipeForm.importing") }
                } else {
                    Label("recipeForm.createDraft", systemImage: "text.page")
                }
            }
            .disabled(normalizedImportText.isEmpty || isImporting || isSaving || isFilling)
        }
    }

    private func sourceSection(_ sourceURL: String) -> some View {
        Section {
            LabeledContent("recipeForm.draftSource") {
                Text(sourceURL)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(VecklyDesign.Colors.inkFaint)
            }
        }
    }

    private var basicSection: some View {
        Section {
            TextField(L10n.string("recipeForm.title"), text: $draft.title)
            if !draft.title.trimmingCharacters(in: .whitespaces).isEmpty {
                Button {
                    Task { await fillWithAI() }
                } label: {
                    if isFilling {
                        HStack { ProgressView(); Text("recipeForm.fillingAI") }
                    } else {
                        Label("recipeForm.fillAI", systemImage: "sparkles")
                            .foregroundStyle(VecklyDesign.Colors.hearthOrange)
                    }
                }
                .disabled(isFilling || isSaving || isImporting)
            }
            TextField(L10n.string("recipeForm.description"), text: $draft.description, axis: .vertical)
                .lineLimit(2...5)
        }
    }

    private var timingSection: some View {
        Section {
            Stepper(L10n.format("recipeForm.servingsCount", draft.servings), value: $draft.servings, in: 1...20)
            HStack {
                Text("recipeForm.prep")
                Spacer()
                TextField(L10n.string("recipeForm.minutesPlaceholder"), value: $draft.prepTimeMinutes, format: .number)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numberPad)
                    .frame(width: 60)
            }
            HStack {
                Text("recipeForm.cook")
                Spacer()
                TextField(L10n.string("recipeForm.minutesPlaceholder"), value: $draft.cookTimeMinutes, format: .number)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numberPad)
                    .frame(width: 60)
            }
        }
    }

    private var ingredientsSection: some View {
        Section("recipes.ingredients") {
            ForEach($draft.ingredients) { $ing in
                HStack(spacing: 8) {
                    TextField(L10n.string("recipeForm.amount"), text: $ing.amount)
                        .frame(width: 56)
                        .keyboardType(.decimalPad)
                    TextField(L10n.string("recipeForm.unit"), text: $ing.unit)
                        .frame(width: 52)
                    TextField(L10n.string("recipeForm.ingredient"), text: $ing.item)
                }
                .font(.body)
            }
            .onDelete { draft.ingredients.remove(atOffsets: $0) }
            Button("recipes.addIngredient") {
                draft.ingredients.append(DraftIngredient())
            }
        }
    }

    private var stepsSection: some View {
        Section("recipeForm.steps") {
            ForEach(Array(draft.steps.enumerated()), id: \.element.id) { i, _ in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(i + 1).")
                        .foregroundStyle(VecklyDesign.Colors.inkFaint)
                        .frame(width: 24, alignment: .leading)
                    TextField(L10n.string("recipeForm.step"), text: $draft.steps[i].text, axis: .vertical)
                        .lineLimit(2...6)
                }
            }
            .onDelete { draft.steps.remove(atOffsets: $0) }
            Button("recipeForm.addStep") { draft.steps.append(StepItem()) }
        }
    }

    private var tagsSection: some View {
        Section("recipeForm.tags") {
            TextField(L10n.string("recipeForm.tagsPlaceholder"), text: $tagsText)
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
            errorMessage = L10n.string("error.recipeImport.urlDraft")
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
            errorMessage = L10n.string("error.recipeImport.textDraft")
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
            errorMessage = L10n.string("error.recipeForm.aiFill")
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
        draftToSave.steps = draft.steps.map { StepItem($0.text.trimmingCharacters(in: .whitespacesAndNewlines)) }
        draftToSave.tags = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        isSaving = true
        defer { isSaving = false }
        do {
            try await onSave(draftToSave)
            dismiss()
        } catch {
            errorMessage = L10n.string("error.recipeForm.save")
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
            return L10n.string("error.recipeImport.invalidURL")
        case .unsupportedURL:
            return L10n.string("error.recipeImport.unsupportedURL")
        case .fetchFailed:
            return L10n.string("error.recipeImport.fetchFailed")
        case .noRecipeFound:
            return L10n.string("error.recipeImport.noRecipeFound")
        case .rateLimited:
            return L10n.string("error.recipeImport.rateLimited")
        case .importFailed:
            return L10n.string("error.recipeImport.urlDraft")
        case .unsupportedSocialSource:
            return L10n.string("error.recipeImport.unsupportedSocialSource")
        case .captionRequired:
            return L10n.string("error.recipeImport.captionRequired")
        }
    }
}

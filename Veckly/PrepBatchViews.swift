import SwiftUI

// MARK: - Prep section inside Shopping tab

struct PrepBatchSection: View {
    @Environment(AppModel.self) private var appModel
    @Binding var showPrepSheet: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("prep.title")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VecklyDesign.Colors.hearthOrange)
                    .textCase(.uppercase)
                Spacer()
                Button {
                    showPrepSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(VecklyDesign.Colors.hearthOrange)
                }
            }

            if appModel.prepBatchStore.isLoading {
                LoadingPanel(title: L10n.string("prep.loading"))
            } else if let error = appModel.prepBatchStore.errorMessage {
                VecklyCard {
                    Button {
                        guard let hid = appModel.householdStore.activeHousehold?.id else { return }
                        let weekStart = appModel.weekStore.weekStartDate
                        Task { await appModel.prepBatchStore.load(householdID: hid, weekStartDate: weekStart) }
                    } label: {
                        Label(error + " " + L10n.string("prep.tapToRetry"), systemImage: "arrow.clockwise")
                            .font(.subheadline)
                            .foregroundStyle(VecklyDesign.Colors.inkMid)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                }
            } else if appModel.prepBatchStore.batches.isEmpty {
                VecklyCard {
                    Text("prep.empty")
                        .font(.subheadline)
                        .foregroundStyle(VecklyDesign.Colors.inkFaint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                }
            } else {
                VecklyCard {
                    VStack(spacing: 0) {
                        ForEach(appModel.prepBatchStore.batches) { batch in
                            PrepBatchRow(batch: batch)
                        }
                    }
                }
            }
        }
    }
}

private struct PrepBatchRow: View {
    @Environment(AppModel.self) private var appModel
    let batch: PrepBatch

    private var recipeName: String? {
        guard let rid = batch.recipeId else { return nil }
        return appModel.recipeStore.recipes.first(where: { $0.id == rid })?.title
    }

    private var assignmentSummary: String {
        let sorted = batch.assignments.sorted { $0.date < $1.date }
        let parts = sorted.map { a -> String in
            let day = shortDay(a.date)
            return "\(day) \(a.mealType.label)"
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.caption)
                        .foregroundStyle(VecklyDesign.Colors.hearthOrange)
                    Text(L10n.format("prep.cookDay", shortDay(batch.cookDate)))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(VecklyDesign.Colors.inkDeep)
                    Text("· \(L10n.format("format.portions", batch.totalPortions))")
                        .font(.subheadline)
                        .foregroundStyle(VecklyDesign.Colors.inkFaint)
                }
                if let name = recipeName {
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(VecklyDesign.Colors.inkFaint)
                }
                if !batch.assignments.isEmpty {
                    Text(assignmentSummary)
                        .font(.caption)
                        .foregroundStyle(VecklyDesign.Colors.inkFaint)
                }
            }
            Spacer()
            Button(role: .destructive) {
                Task { await deleteBatch() }
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(VecklyDesign.Colors.inkFaint)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 8)
    }

    private func deleteBatch() async {
        guard let hid = appModel.householdStore.activeHousehold?.id else { return }
        try? await appModel.prepBatchStore.delete(householdID: hid, batchID: batch.id)
    }

    private func shortDay(_ dateString: String) -> String {
        guard let date = weekDateFormatter.date(from: dateString) else { return dateString }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM"
        formatter.locale = AppLocalePreference.effectiveLocale
        return formatter.string(from: date)
    }
}

// MARK: - Create sheet

struct PrepBatchFormSheet: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedRecipeID: String? = nil
    @State private var cookDate = Date()
    @State private var totalPortions = 4
    @State private var assignedDays: Set<String> = []
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var weekDates: [Date] {
        guard let start = weekDateFormatter.date(from: appModel.weekStore.weekStartDate) else { return [] }
        return (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("prep.recipeOptional") {
                    Picker("meal.recipe", selection: $selectedRecipeID) {
                        Text("common.none").tag(Optional<String>.none)
                        ForEach(appModel.recipeStore.recipes) { recipe in
                            Text(recipe.title).tag(Optional<String>.some(recipe.id))
                        }
                    }
                    .labelsHidden()
                }

                Section {
                    DatePicker("prep.cookDate", selection: $cookDate, displayedComponents: .date)
                    Stepper(L10n.format("prep.portionsCount", totalPortions), value: $totalPortions, in: 1...20)
                } header: {
                    Text("prep.details")
                }

                Section {
                    ForEach(weekDates, id: \.self) { date in
                        let key = weekDateFormatter.string(from: date)
                        Toggle(dayLabel(date), isOn: Binding(
                            get: { assignedDays.contains(key) },
                            set: { if $0 { assignedDays.insert(key) } else { assignedDays.remove(key) } }
                        ))
                    }
                } header: {
                    Text("prep.coverDinners")
                } footer: {
                    Text("prep.coverDinnersFooter")
                }
            }
            .navigationTitle(L10n.string("prep.newTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("common.add") { Task { await save() } }
                            .disabled(assignedDays.isEmpty)
                    }
                }
            }
            .alert(L10n.string("common.error"),
                isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }),
                actions: { Button("common.ok") { errorMessage = nil } },
                message: { Text(errorMessage ?? "") }
            )
            .task {
                guard let hid = appModel.householdStore.activeHousehold?.id else { return }
                if appModel.recipeStore.recipes.isEmpty {
                    await appModel.recipeStore.loadRecipes(householdID: hid)
                }
            }
        }
    }

    private func save() async {
        guard let hid = appModel.householdStore.activeHousehold?.id else { return }
        isSaving = true
        defer { isSaving = false }
        let dateStr = weekDateFormatter.string(from: cookDate)
        let assignments = assignedDays.sorted().map { (date: $0, mealType: MealType.dinner) }
        do {
            try await appModel.prepBatchStore.create(
                householdID: hid,
                weekStartDate: appModel.weekStore.weekStartDate,
                recipeId: selectedRecipeID,
                cookDate: dateStr,
                totalPortions: totalPortions,
                assignments: assignments
            )
            dismiss()
        } catch {
            errorMessage = L10n.string("error.prep.create")
        }
    }

    private func dayLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE d MMM"
        f.locale = AppLocalePreference.effectiveLocale
        return f.string(from: date)
    }
}

private let weekDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.locale = Locale(identifier: "en_US_POSIX")
    return f
}()

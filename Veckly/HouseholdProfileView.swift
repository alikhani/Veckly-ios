import SwiftUI

struct HouseholdProfileView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var adults = 1
    @State private var children = 0
    @State private var selectedDays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
    @State private var priorities: Set<HouseholdPriority> = []
    @State private var avoidIngredients: [String] = []
    @State private var newIngredient = ""
    @State private var isSaving = false
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var didSave = false

    private var household: Household? { appModel.householdStore.activeHousehold }

    var body: some View {
        Form {
            if isLoading {
                Section { HStack { Spacer(); ProgressView(); Spacer() } }
            } else {
                sizeSection
                daysSection
                prioritiesSection
                avoidSection
            }
        }
        .navigationTitle(L10n.string("settings.householdPreferences"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("common.save") { Task { await save() } }
                        .disabled(selectedDays.isEmpty || isLoading)
                }
            }
        }
        .alert(L10n.string("common.error"),
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }),
            actions: { Button("common.ok") { errorMessage = nil } },
            message: { Text(errorMessage ?? "") }
        )
        .task(id: household?.id) { await loadExisting() }
    }

    private var sizeSection: some View {
        Section("household.size") {
            Stepper(L10n.format("household.adultsCount", adults), value: $adults, in: 1...20)
            Stepper(L10n.format("household.childrenCount", children), value: $children, in: 0...20)
        }
    }

    private var daysSection: some View {
        Section {
            ForEach(Weekday.allCases, id: \.self) { day in
                Toggle(day.displayName, isOn: Binding(
                    get: { selectedDays.contains(day) },
                    set: { if $0 { selectedDays.insert(day) } else { selectedDays.remove(day) } }
                ))
            }
        } header: {
            Text("household.cookingDays")
        } footer: {
            Text("household.cookingDaysFooter")
        }
    }

    private var prioritiesSection: some View {
        Section("settings.priorities") {
            ForEach(HouseholdPriority.allCases, id: \.self) { priority in
                Toggle(priority.label, isOn: Binding(
                    get: { priorities.contains(priority) },
                    set: { if $0 { priorities.insert(priority) } else { priorities.remove(priority) } }
                ))
            }
        }
    }

    private var avoidSection: some View {
        Section {
            if didSave {
                Text("settings.saved")
                    .font(.caption)
                    .foregroundStyle(VecklyDesign.Colors.hearthOrange)
            }

            ForEach(avoidIngredients, id: \.self) { ingredient in
                Text(ingredient)
            }
            .onDelete { avoidIngredients.remove(atOffsets: $0) }

            HStack {
                TextField(L10n.string("settings.addIngredientToAvoid"), text: $newIngredient)
                    .onSubmit { addIngredient() }
                Button("common.add") { addIngredient() }
                    .disabled(newIngredient.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("settings.avoidIngredients")
        } footer: {
            Text("settings.avoidIngredientsFooter")
        }
    }

    private func addIngredient() {
        let trimmed = normalizedIngredient(newIngredient)
        guard !trimmed.isEmpty else { return }
        guard !avoidIngredients.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        avoidIngredients.append(trimmed)
        newIngredient = ""
        didSave = false
    }

    private func loadExisting() async {
        isLoading = true
        errorMessage = nil
        didSave = false
        defer { isLoading = false }
        guard let hid = household?.id else { return }

        if let existing = appModel.householdStore.cachedProfile(for: hid) {
            apply(existing)
            return
        }

        await appModel.householdStore.loadHouseholdDetails(householdID: hid)
        if let fetched = appModel.householdStore.cachedProfile(for: hid) {
            apply(fetched)
        } else if let message = appModel.householdStore.detailsErrorMessage {
            errorMessage = message
        }
    }

    private func apply(_ p: HouseholdProfile) {
        adults = p.adults
        children = p.children
        selectedDays = Set(p.selectedDays)
        priorities = Set(p.priorities)
        avoidIngredients = p.avoidIngredients
    }

    private func save() async {
        guard let hid = household?.id else { return }
        isSaving = true
        didSave = false
        defer { isSaving = false }
        do {
            try await appModel.householdStore.saveProfile(
                householdID: hid,
                adults: adults, children: children,
                priorities: Array(priorities),
                avoidIngredients: avoidIngredients.map(normalizedIngredient).filter { !$0.isEmpty },
                selectedDays: Weekday.allCases.filter { selectedDays.contains($0) }
            )
            didSave = true
        } catch {
            errorMessage = L10n.string("error.settings.savePreferences")
        }
    }

    private func normalizedIngredient(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

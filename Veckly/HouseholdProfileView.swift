import SwiftUI

struct HouseholdProfileView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var adults = 2
    @State private var children = 0
    @State private var selectedDays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
    @State private var priorities: Set<HouseholdPriority> = []
    @State private var avoidIngredients: [String] = []
    @State private var newIngredient = ""
    @State private var isSaving = false
    @State private var isLoading = true
    @State private var errorMessage: String?

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
        .navigationTitle("Household Preferences")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Save") { Task { await save() } }
                        .disabled(selectedDays.isEmpty)
                }
            }
        }
        .alert("Error", isPresented: .constant(errorMessage != nil), actions: {
            Button("OK") { errorMessage = nil }
        }, message: { Text(errorMessage ?? "") })
        .task { await loadExisting() }
    }

    private var sizeSection: some View {
        Section("Household size") {
            Stepper("Adults: \(adults)", value: $adults, in: 1...20)
            Stepper("Children: \(children)", value: $children, in: 0...20)
        }
    }

    private var daysSection: some View {
        Section {
            ForEach(Weekday.allCases, id: \.self) { day in
                Toggle(day.rawValue.capitalized, isOn: Binding(
                    get: { selectedDays.contains(day) },
                    set: { if $0 { selectedDays.insert(day) } else { selectedDays.remove(day) } }
                ))
            }
        } header: {
            Text("Cooking days")
        } footer: {
            Text("The week plan will only include meals on these days.")
        }
    }

    private var prioritiesSection: some View {
        Section("Priorities") {
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
            ForEach(avoidIngredients, id: \.self) { ingredient in
                Text(ingredient)
            }
            .onDelete { avoidIngredients.remove(atOffsets: $0) }

            HStack {
                TextField("Add ingredient to avoid", text: $newIngredient)
                    .onSubmit { addIngredient() }
                Button("Add") { addIngredient() }
                    .disabled(newIngredient.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Avoid ingredients")
        } footer: {
            Text("Recipes containing these won't be suggested.")
        }
    }

    private func addIngredient() {
        let trimmed = newIngredient.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !avoidIngredients.contains(trimmed) else { return }
        avoidIngredients.append(trimmed)
        newIngredient = ""
    }

    private func loadExisting() async {
        defer { isLoading = false }
        guard let hid = household?.id else { return }
        if let existing = appModel.householdStore.profile {
            apply(existing)
            return
        }
        if let fetched = try? await appModel.apiClient.getProfile(householdID: hid) {
            apply(fetched)
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
        defer { isSaving = false }
        do {
            try await appModel.householdStore.saveProfile(
                householdID: hid,
                adults: adults, children: children,
                priorities: Array(priorities),
                avoidIngredients: avoidIngredients,
                selectedDays: Weekday.allCases.filter { selectedDays.contains($0) }
            )
        } catch {
            errorMessage = "Could not save preferences. Try again."
        }
    }
}

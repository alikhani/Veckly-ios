import SwiftUI

// MARK: - "Eat this again" sheet

/// Always launched from a day that already has this exact recipe planned —
/// the recipe and cook date are fixed, not user-editable, since this flow
/// only ever repeats a specific known dish from a specific known day.
struct PrepBatchFormSheet: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    let initialRecipeID: String
    let initialCookDate: Date

    @State private var totalPortions = 4
    @State private var assignedDays: Set<String> = []
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(initialRecipeID: String, initialCookDate: Date) {
        self.initialRecipeID = initialRecipeID
        self.initialCookDate = initialCookDate
        _totalPortions = State(initialValue: 4)
    }

    private var cookDateString: String { WeekCalendar.string(from: initialCookDate) }

    /// 14 days from the cook date — long enough to cover the common
    /// "cook on the weekend, eat into next week" case.
    private var coverageDates: [String] {
        (0..<14).map { WeekCalendar.addDays(to: cookDateString, offset: $0) }
    }

    /// Only the currently-loaded week's lock state is known (`WeekStore`
    /// holds one week at a time), so dates beyond it are always selectable —
    /// still strictly better than today's zero conflict detection.
    private var lockedDayByDate: [String: WeekDayRowViewModel] {
        Dictionary(uniqueKeysWithValues: appModel.weekStore.dayRows.filter(\.isLocked).map { ($0.date, $0) })
    }

    private var fixedRecipeTitle: String {
        appModel.recipeStore.recipes.first(where: { $0.id == initialRecipeID })?.title ?? L10n.string("prep.fallbackTitle")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("meal.recipe", value: fixedRecipeTitle)
                    LabeledContent("prep.cookDate", value: dayLabel(cookDateString))
                    Stepper(L10n.format("prep.portionsCount", totalPortions), value: $totalPortions, in: 1...20)
                } header: {
                    Text("prep.details")
                }

                Section {
                    ForEach(coverageDates, id: \.self) { date in
                        dayRow(for: date)
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

    @ViewBuilder
    private func dayRow(for date: String) -> some View {
        if let locked = lockedDayByDate[date] {
            HStack {
                Text(dayLabel(date))
                Spacer()
                Text(locked.mealTitle)
                    .font(.footnote)
                    .foregroundStyle(VecklyDesign.Colors.inkFaint)
                Image(systemName: "lock.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(VecklyDesign.Colors.hearthOrange)
                Button("prep.unlock") {
                    Task { await unlock(locked) }
                }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.borderless)
            }
            .foregroundStyle(VecklyDesign.Colors.inkFaint)
        } else {
            Toggle(dayLabel(date), isOn: Binding(
                get: { assignedDays.contains(date) },
                set: { if $0 { assignedDays.insert(date) } else { assignedDays.remove(date) } }
            ))
        }
    }

    private func unlock(_ day: WeekDayRowViewModel) async {
        guard let household = appModel.householdStore.activeHousehold else { return }
        guard let userID = appModel.authSessionStore.userID else {
            await appModel.handleUnauthorized()
            return
        }
        await appModel.weekStore.toggleLock(day: day, household: household, userID: userID)
    }

    private func save() async {
        guard let hid = appModel.householdStore.activeHousehold?.id else { return }
        isSaving = true
        defer { isSaving = false }
        let assignments = assignedDays.sorted().map { (date: $0, mealType: MealType.dinner) }
        do {
            try await appModel.prepBatchStore.create(
                householdID: hid,
                weekStartDate: appModel.weekStore.weekStartDate,
                recipeId: initialRecipeID,
                cookDate: cookDateString,
                totalPortions: totalPortions,
                assignments: assignments
            )
            dismiss()
        } catch {
            errorMessage = L10n.string("error.prep.create")
        }
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE d MMM"
        f.locale = AppLocalePreference.effectiveLocale
        return f
    }()

    private func dayLabel(_ dateString: String) -> String {
        guard let date = WeekCalendar.date(from: dateString) else { return dateString }
        Self.dayFormatter.locale = AppLocalePreference.effectiveLocale
        return Self.dayFormatter.string(from: date)
    }
}

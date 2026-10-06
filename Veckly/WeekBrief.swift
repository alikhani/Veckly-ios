import Observation
import SwiftUI

struct PantryPlanningItem: Identifiable, Equatable {
    let id: String
    let label: String

    static func suggestions(from pantryStock: [String: Double], limit: Int = 5) -> [PantryPlanningItem] {
        pantryStock
            .filter { $0.value > 0 }
            .map { key, _ in
                let parts = key.split(separator: ":", omittingEmptySubsequences: false)
                let rawLabel = parts.count >= 2 ? String(parts[1]) : key
                return PantryPlanningItem(
                    id: key,
                    label: rawLabel
                        .replacingOccurrences(of: "-", with: " ")
                        .replacingOccurrences(of: "_", with: " ")
                        .localizedCapitalized
                )
            }
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
            .prefix(limit)
            .map { $0 }
    }
}

enum WeekBriefSignal: String, CaseIterable, Hashable, Identifiable {
    case busy
    case late
    case guests
    case away
    case extra
    case relaxed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .busy: L10n.string("weekBrief.signal.busy")
        case .late: L10n.string("weekBrief.signal.late")
        case .guests: L10n.string("weekBrief.signal.guests")
        case .away: L10n.string("weekBrief.signal.away")
        case .extra: L10n.string("weekBrief.signal.extra")
        case .relaxed: L10n.string("weekBrief.signal.relaxed")
        }
    }

    var systemImage: String {
        switch self {
        case .busy: "bolt"
        case .late: "moon"
        case .guests: "person.2"
        case .away: "house.slash"
        case .extra: "takeoutbag.and.cup.and.straw"
        case .relaxed: "frying.pan"
        }
    }
}

struct WeekBriefDay: Equatable, Identifiable {
    let weekday: Weekday
    let date: String
    let dayLabel: String
    let dateLabel: String
    let normal: HouseholdDaySelection
    var signals: Set<WeekBriefSignal>

    var id: String { date }

    var normalSummary: String {
        var parts: [String] = []
        if normal.effortLevel == .busy { parts.append(WeekBriefSignal.busy.label) }
        if normal.lateEvening { parts.append(WeekBriefSignal.late.label) }
        if normal.occasion == .guests { parts.append(WeekBriefSignal.guests.label) }
        if normal.leftoversIntent { parts.append(WeekBriefSignal.extra.label) }
        if normal.cookingTolerance == .relaxed { parts.append(WeekBriefSignal.relaxed.label) }
        return parts.isEmpty ? L10n.string("weekBrief.normal.standard") : parts.joined(separator: ", ")
    }

    func supports(_ signal: WeekBriefSignal) -> Bool {
        switch signal {
        case .busy: normal.effortLevel != .busy
        case .late: !normal.lateEvening
        case .guests: normal.occasion != .guests
        case .extra: !normal.leftoversIntent
        case .relaxed: normal.cookingTolerance != .relaxed
        case .away: true
        }
    }
}

struct WeekBriefDraft: Equatable {
    var days: [WeekBriefDay]
    private let existingByDate: [String: WeekContextOverride]
    private let initiallyAwayDates: Set<String>

    init(rows: [WeekDayRowViewModel], profile: HouseholdProfile?, overrides: [WeekContextOverride]) {
        let defaults = Dictionary(uniqueKeysWithValues: (profile?.selectedDays ?? []).map { ($0.day, $0) })
        let scope = WeekPlanningScope(profile: profile)
        let existingByDate = Dictionary(uniqueKeysWithValues: overrides.map { ($0.date, $0) })
        let includedDates = Set(overrides.map(\.date))
        let includedRows = rows.filter {
            !$0.isPast && (scope.selectedWeekdays.contains($0.weekday) || includedDates.contains($0.date) || $0.isSkipped)
        }

        self.days = includedRows.map { row in
            let normal = defaults[row.weekday] ?? HouseholdDaySelection(day: row.weekday)
            let saved = existingByDate[row.date]
            var signals: Set<WeekBriefSignal> = []
            if saved?.effortLevel == .busy && normal.effortLevel != .busy { signals.insert(.busy) }
            if saved?.lateEvening == true && !normal.lateEvening { signals.insert(.late) }
            if saved?.occasion == .guests && normal.occasion != .guests { signals.insert(.guests) }
            if saved?.leftoversIntent == true && !normal.leftoversIntent { signals.insert(.extra) }
            if saved?.cookingTolerance == .relaxed && normal.cookingTolerance != .relaxed { signals.insert(.relaxed) }
            if row.isSkipped { signals.insert(.away) }
            return WeekBriefDay(
                weekday: row.weekday,
                date: row.date,
                dayLabel: row.weekdayLabel,
                dateLabel: row.dateLabel,
                normal: normal,
                signals: signals
            )
        }
        self.existingByDate = existingByDate
        self.initiallyAwayDates = Set(includedRows.filter(\.isSkipped).map(\.date))
    }

    var hasDeviations: Bool { days.contains { !$0.signals.isEmpty } }

    var summaryLines: [String] {
        days.compactMap { day in
            guard !day.signals.isEmpty else { return nil }
            let labels = WeekBriefSignal.allCases.filter(day.signals.contains).map(\.label)
            return "\(day.dayLabel): \(labels.joined(separator: ", "))"
        }
    }

    mutating func toggle(_ signal: WeekBriefSignal, on date: String) {
        guard let index = days.firstIndex(where: { $0.date == date }), days[index].supports(signal) else { return }
        if days[index].signals.contains(signal) {
            days[index].signals.remove(signal)
        } else {
            days[index].signals.insert(signal)
        }
    }

    func override(for day: WeekBriefDay) -> WeekContextOverride? {
        let existing = existingByDate[day.date]
        let override = WeekContextOverride(
            date: day.date,
            servingsOverride: existing?.servingsOverride,
            occasion: day.signals.contains(.guests) ? .guests : nil,
            effortLevel: day.signals.contains(.busy) ? .busy : nil,
            leftoversIntent: day.signals.contains(.extra) ? true : nil,
            lateEvening: day.signals.contains(.late) ? true : nil,
            cookingTolerance: day.signals.contains(.relaxed) ? .relaxed : nil
        )
        return override.isEmpty ? nil : override
    }

    var awayChanges: [(day: Weekday, skipped: Bool)] {
        days.compactMap { day in
            let wasAway = initiallyAwayDates.contains(day.date)
            let isAway = day.signals.contains(.away)
            return wasAway == isAway ? nil : (day.weekday, isAway)
        }
    }

    var datesToClear: [String] {
        days.compactMap { day in
            existingByDate[day.date] != nil && override(for: day) == nil ? day.date : nil
        }
    }

    var overridesToUpsert: [WeekContextOverride] {
        days.compactMap { day in
            guard let value = override(for: day), value != existingByDate[day.date] else { return nil }
            return value
        }
    }
}

protocol WeekBriefAPIClient {
    func weekContextOverrides(householdID: String, weekStartDate: String) async throws -> [WeekContextOverride]
    func upsertWeekContextOverride(householdID: String, weekStartDate: String, override: WeekContextOverride) async throws
    func clearWeekContextOverride(householdID: String, weekStartDate: String, date: String) async throws
    func appendWeekPlanEvent(householdID: String, weekStartDate: String, userID: String, event: WeekPlanEventInput) async throws
}

extension VecklyAPIClient: WeekBriefAPIClient {}

@MainActor
@Observable
final class WeekBriefStore {
    private let apiClient: any WeekBriefAPIClient
    private(set) var draft: WeekBriefDraft?
    private(set) var isLoading = false
    private(set) var isSaving = false
    var errorMessage: String?

    init(apiClient: any WeekBriefAPIClient) {
        self.apiClient = apiClient
    }

    func load(householdID: String, weekStartDate: String, rows: [WeekDayRowViewModel], profile: HouseholdProfile?) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let overrides = try await apiClient.weekContextOverrides(householdID: householdID, weekStartDate: weekStartDate)
            draft = WeekBriefDraft(rows: rows, profile: profile, overrides: overrides)
        } catch {
            errorMessage = L10n.string("weekBrief.error.load")
        }
    }

    func updateDraft(_ update: (inout WeekBriefDraft) -> Void) {
        guard var draft else { return }
        update(&draft)
        self.draft = draft
    }

    func save(householdID: String, weekStartDate: String, userID: String) async -> Bool {
        guard let draft else { return false }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            for date in draft.datesToClear {
                try await apiClient.clearWeekContextOverride(householdID: householdID, weekStartDate: weekStartDate, date: date)
            }
            for override in draft.overridesToUpsert {
                try await apiClient.upsertWeekContextOverride(
                    householdID: householdID,
                    weekStartDate: weekStartDate,
                    override: override
                )
            }
            for change in draft.awayChanges {
                try await apiClient.appendWeekPlanEvent(
                    householdID: householdID,
                    weekStartDate: weekStartDate,
                    userID: userID,
                    event: change.skipped ? .daySkipped(day: change.day) : .dayUnskipped(day: change.day)
                )
            }
            return true
        } catch {
            errorMessage = L10n.string("weekBrief.error.save")
            return false
        }
    }
}

struct WeekBriefSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store: WeekBriefStore
    @State private var usePantry = false
    @State private var selectedPantryKeys: Set<String>
    @State private var selectedPortionDates: Set<String> = []
    let householdID: String
    let weekStartDate: String
    let userID: String
    let rows: [WeekDayRowViewModel]
    let profile: HouseholdProfile?
    let isRegenerating: Bool
    let pantryItems: [PantryPlanningItem]
    let onGenerate: ([String], [Weekday: Int]) async -> Void

    private var portionSuggestionRows: [WeekDayRowViewModel] {
        rows.filter { !$0.isPast && !$0.isSkipped && $0.portionSuggestion != nil }
    }

    init(
        apiClient: any WeekBriefAPIClient,
        householdID: String,
        weekStartDate: String,
        userID: String,
        rows: [WeekDayRowViewModel],
        profile: HouseholdProfile?,
        isRegenerating: Bool,
        pantryItems: [PantryPlanningItem],
        onGenerate: @escaping ([String], [Weekday: Int]) async -> Void
    ) {
        _store = State(initialValue: WeekBriefStore(apiClient: apiClient))
        _selectedPantryKeys = State(initialValue: Set(pantryItems.map(\.id)))
        self.householdID = householdID
        self.weekStartDate = weekStartDate
        self.userID = userID
        self.rows = rows
        self.profile = profile
        self.isRegenerating = isRegenerating
        self.pantryItems = pantryItems
        self.onGenerate = onGenerate
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading || store.draft == nil && store.errorMessage == nil {
                    ProgressView("weekBrief.loading")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = store.errorMessage, store.draft == nil {
                    ContentUnavailableView {
                        Label("weekBrief.error.title", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("common.tryAgain") { Task { await load() } }
                    }
                } else if let draft = store.draft {
                    briefContent(draft)
                }
            }
            .background(VecklyDesign.Colors.canvas)
            .navigationTitle("weekBrief.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
            }
        }
        .interactiveDismissDisabled(store.isSaving)
        .task { await load() }
    }

    private func briefContent(_ draft: WeekBriefDraft) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("weekBrief.intro")
                    .font(.body)
                    .foregroundStyle(VecklyDesign.Colors.inkMid)

                ForEach(draft.days) { day in
                    daySection(day)
                }

                if !portionSuggestionRows.isEmpty {
                    portionSuggestionsSection
                }

                if !pantryItems.isEmpty {
                    pantrySection
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("weekBrief.summary.title")
                        .font(VecklyDesign.Typography.cardTitle)
                        .foregroundStyle(VecklyDesign.Colors.inkDeep)
                    if draft.summaryLines.isEmpty {
                        Text("weekBrief.summary.normal")
                            .foregroundStyle(VecklyDesign.Colors.inkMid)
                    } else {
                        ForEach(draft.summaryLines, id: \.self) { line in
                            Label(line, systemImage: "checkmark")
                                .foregroundStyle(VecklyDesign.Colors.inkDeep)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)

                if let error = store.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("weekBriefError")
                }

                Button {
                    Task { await saveAndGenerate() }
                } label: {
                    if store.isSaving {
                        HStack(spacing: 8) {
                            ProgressView().tint(.white)
                            Text("weekBrief.saving")
                        }
                    } else {
                        Text(isRegenerating ? "weekBrief.generateAgain" : "weekBrief.generate")
                    }
                }
                .buttonStyle(VecklyPrimaryButtonStyle())
                .disabled(store.isSaving)
                .accessibilityIdentifier("weekBriefGenerate")

                if !draft.hasDeviations {
                    Button("weekBrief.nothingSpecial") {
                        Task { await saveAndGenerate() }
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(VecklyDesign.Colors.hearthOrangeText)
                    .frame(maxWidth: .infinity)
                    .disabled(store.isSaving)
                }
            }
            .padding(18)
        }
    }

    private var pantrySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $usePantry) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("weekBrief.pantry.title")
                        .font(.headline)
                    Text("weekBrief.pantry.subtitle")
                        .font(.footnote)
                        .foregroundStyle(VecklyDesign.Colors.inkMid)
                }
            }
            .tint(VecklyDesign.Colors.hearthOrangeFill)

            if usePantry {
                FlowLayout(spacing: 8) {
                    ForEach(pantryItems) { item in
                        let isSelected = selectedPantryKeys.contains(item.id)
                        Button {
                            if isSelected {
                                if selectedPantryKeys.count > 1 {
                                    selectedPantryKeys.remove(item.id)
                                }
                            } else {
                                selectedPantryKeys.insert(item.id)
                            }
                        } label: {
                            Text(item.label)
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .foregroundStyle(isSelected ? Color.white : VecklyDesign.Colors.inkDeep)
                                .background(isSelected ? VecklyDesign.Colors.hearthOrangePrimaryFill : Color("chipSurface"))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var portionSuggestionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("portionMemory.brief.title")
                .font(.headline)
                .foregroundStyle(VecklyDesign.Colors.inkDeep)
            Text("portionMemory.brief.subtitle")
                .font(.footnote)
                .foregroundStyle(VecklyDesign.Colors.inkMid)

            ForEach(portionSuggestionRows) { row in
                if let suggestion = row.portionSuggestion {
                    Toggle(isOn: Binding(
                        get: { selectedPortionDates.contains(row.date) },
                        set: { selected in
                            if selected { selectedPortionDates.insert(row.date) }
                            else { selectedPortionDates.remove(row.date) }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.mealTitle)
                                .font(.subheadline.weight(.semibold))
                            Text(L10n.format("portionMemory.brief.servings", suggestion.suggestedServings))
                                .font(.footnote)
                                .foregroundStyle(VecklyDesign.Colors.inkMid)
                        }
                    }
                    .tint(VecklyDesign.Colors.hearthOrangeFill)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func daySection(_ day: WeekBriefDay) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(day.dayLabel)
                    .font(.headline)
                    .foregroundStyle(VecklyDesign.Colors.inkDeep)
                Spacer()
                Text(day.dateLabel)
                    .font(.subheadline)
                    .foregroundStyle(VecklyDesign.Colors.inkFaint)
            }

            Text(L10n.format("weekBrief.normal.format", day.normalSummary))
                .font(.footnote)
                .foregroundStyle(VecklyDesign.Colors.inkMid)

            FlowLayout(spacing: 8) {
                ForEach(WeekBriefSignal.allCases) { signal in
                    if day.supports(signal) {
                        signalButton(signal, day: day)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }

    private func signalButton(_ signal: WeekBriefSignal, day: WeekBriefDay) -> some View {
        let isSelected = day.signals.contains(signal)
        return Button {
            store.updateDraft { $0.toggle(signal, on: day.date) }
        } label: {
            Label(signal.label, systemImage: signal.systemImage)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .foregroundStyle(isSelected ? Color.white : VecklyDesign.Colors.inkDeep)
                .background(isSelected ? VecklyDesign.Colors.hearthOrangePrimaryFill : Color("chipSurface"))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(day.dayLabel), \(signal.label)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(L10n.string(isSelected ? "weekBrief.accessibility.remove" : "weekBrief.accessibility.add"))
    }

    private func load() async {
        await store.load(householdID: householdID, weekStartDate: weekStartDate, rows: rows, profile: profile)
    }

    private func saveAndGenerate() async {
        guard await store.save(householdID: householdID, weekStartDate: weekStartDate, userID: userID) else { return }
        dismiss()
        let selectedAdjustments: [(Weekday, Int)] = portionSuggestionRows.compactMap { row in
            guard selectedPortionDates.contains(row.date), let suggestion = row.portionSuggestion else { return nil }
            return (row.weekday, suggestion.suggestedServings)
        }
        let portionAdjustments = Dictionary(uniqueKeysWithValues: selectedAdjustments)
        await onGenerate(
            usePantry ? pantryItems.map(\.id).filter(selectedPantryKeys.contains) : [],
            portionAdjustments
        )
    }
}

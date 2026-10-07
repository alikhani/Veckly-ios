import SwiftUI

struct WeekPulseView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft = WeekPulseDraft()
    /// The household the draft was seeded from. The draft is only built from
    /// a successful load — saving an empty draft after a failed load would
    /// overwrite this member's real answers.
    @State private var draftHouseholdID: String?
    @State private var loadFailed = false
    @State private var isSaving = false
    @State private var saveError: String?

    private let weekStartDate = WeekCalendar.currentWeekStartDate()

    private var household: Household? { appModel.householdStore.activeHousehold }
    private var pulse: WeekPulse? {
        guard let pulse = appModel.householdStore.weekPulse,
              pulse.householdID == household?.id, pulse.weekStartDate == weekStartDate else { return nil }
        return pulse
    }
    private var isDraftReady: Bool { draftHouseholdID != nil && draftHouseholdID == household?.id }

    private var weekDays: [(weekday: Weekday, date: String)] {
        Weekday.allCases.enumerated().map { index, weekday in
            (weekday, WeekCalendar.addDays(to: weekStartDate, offset: index))
        }
    }

    var body: some View {
        Form {
            Section {
                Text(L10n.string("pulse.intro"))
                    .font(.subheadline)
                    .foregroundStyle(VecklyDesign.Colors.inkMid)
            }

            if isDraftReady {
                editableSections
            } else if loadFailed {
                Section {
                    Text(L10n.string("pulse.loadError"))
                        .foregroundStyle(VecklyDesign.Colors.inkDeep)
                    Button(L10n.string("common.tryAgain")) {
                        Task { await load() }
                    }
                    .foregroundStyle(VecklyDesign.Colors.hearthOrangeText)
                    .accessibilityIdentifier("retryWeekPulseButton")
                }
            } else {
                Section {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            }

            if let pulse {
                Section(L10n.format("pulse.responses", pulse.responseCount, pulse.memberCount)) {
                    ForEach(pulse.members) { member in
                        HStack(spacing: 12) {
                            Image(systemName: member.responded ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(member.responded ? VecklyDesign.Colors.hearthOrangeFill : VecklyDesign.Colors.inkFaint)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(member.isCurrentUser ? L10n.string("pulse.you") : member.displayName)
                                    .foregroundStyle(VecklyDesign.Colors.inkDeep)
                                Text(memberSummary(member))
                                    .font(.footnote)
                                    .foregroundStyle(VecklyDesign.Colors.inkMid)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(L10n.string("pulse.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: household?.id) { await load() }
        .alert(
            L10n.string("pulse.saveError"),
            isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })
        ) {
            Button(L10n.string("common.ok")) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    @ViewBuilder
    private var editableSections: some View {
        Section {
            ForEach(weekDays, id: \.date) { day in
                Toggle(isOn: awayBinding(for: day.date)) {
                    Text(day.weekday.displayName)
                }
            }
        } header: {
            Text(L10n.string("pulse.away.title"))
        } footer: {
            Text(L10n.string("pulse.away.footer"))
        }

        Section {
            TextField(L10n.string("pulse.wish.placeholder"), text: $draft.wishedMeal)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
        } header: {
            Text(L10n.string("pulse.wish.title"))
        } footer: {
            Text(L10n.string("pulse.wish.footer"))
        }

        Section(L10n.string("pulse.simple.title")) {
            Picker(L10n.string("pulse.simple.title"), selection: $draft.simpleDate) {
                Text(L10n.string("pulse.simple.none")).tag(String?.none)
                ForEach(weekDays, id: \.date) { day in
                    Text(day.weekday.displayName).tag(String?.some(day.date))
                }
            }
            .pickerStyle(.menu)
        }

        Section {
            Button {
                Task { await save() }
            } label: {
                HStack {
                    if isSaving { ProgressView() }
                    Text(L10n.string("pulse.save"))
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(VecklyDesign.Colors.hearthOrangePrimaryFill)
            .disabled(isSaving || !isDraftReady)
            .accessibilityIdentifier("saveWeekPulseButton")
        }
    }

    private func awayBinding(for date: String) -> Binding<Bool> {
        Binding(
            get: { draft.awayDates.contains(date) },
            set: { enabled in
                if enabled { draft.awayDates.insert(date) } else { draft.awayDates.remove(date) }
            }
        )
    }

    private func load() async {
        guard let household else { return }
        loadFailed = false
        let loaded = await appModel.householdStore.loadWeekPulse(householdID: household.id, weekStartDate: weekStartDate)
        guard self.household?.id == household.id else { return }
        guard let loaded else {
            // A refresh failing after the draft is already seeded keeps the
            // user's in-progress edits; only an unseeded draft blocks Save.
            if draftHouseholdID != household.id { loadFailed = true }
            return
        }
        if draftHouseholdID != household.id {
            draft = WeekPulseDraft(member: loaded.currentMember)
            draftHouseholdID = household.id
        }
    }

    private func save() async {
        guard let household, isDraftReady else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await appModel.householdStore.saveWeekPulse(householdID: household.id, weekStartDate: weekStartDate, draft: draft)
            dismiss()
        } catch {
            saveError = L10n.string("pulse.saveError.message")
        }
    }

    private func memberSummary(_ member: WeekPulseMember) -> String {
        guard member.responded else { return L10n.string("pulse.notAnswered") }
        var parts: [String] = []
        if !member.awayDates.isEmpty { parts.append(L10n.format("pulse.away.count", member.awayDates.count)) }
        if let wishedMeal = member.wishedMeal { parts.append(wishedMeal) }
        if member.simpleDate != nil { parts.append(L10n.string("pulse.simple.selected")) }
        return parts.isEmpty ? L10n.string("pulse.noSpecialRequests") : parts.joined(separator: " · ")
    }
}

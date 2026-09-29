import SwiftUI
import Observation

private let retroResolvedWeekKey = "veckly.retro.resolvedWeek"

protocol RetroCardAPIClient {
    func familyRecap(householdID: String) async throws -> FamilyRecap
}

extension VecklyAPIClient: RetroCardAPIClient {}

@MainActor
@Observable
final class RetroCardViewModel {
    struct Row: Identifiable, Equatable {
        let date: String
        let recipeID: String
        let title: String
        let weekdayLabel: String
        var id: String { date }
    }

    private(set) var rows: [Row] = []
    private(set) var weekStartDate: String?
    private(set) var recap: FamilyRecap?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(
        household: Household,
        weekStore: WeekStore,
        outcomeStore: MealOutcomeStore,
        apiClient: any RetroCardAPIClient
    ) async {
        let lastWeekStart = WeekCalendar.addWeeks(to: WeekCalendar.currentWeekStartDate(), offset: -1)
        weekStartDate = lastWeekStart

        // Retry offline answers even when this retro was already dismissed.
        await outcomeStore.load(householdID: household.id, weekStartDate: lastWeekStart)

        guard !isDismissed(for: lastWeekStart) else {
            rows = []
            return
        }
        guard let summary = await weekStore.peekWeekSummary(household: household, weekStartDate: lastWeekStart) else {
            rows = []
            return
        }

        rows = Self.buildRows(days: summary.days)
        guard !rows.isEmpty else { return }
        recap = try? await apiClient.familyRecap(householdID: household.id)
    }

    static func buildRows(days: [WeekSummaryDay]) -> [Row] {
        days.compactMap { day in
            guard day.state == .planned, let recipe = day.recipe else { return nil }
            return Row(
                date: day.date,
                recipeID: recipe.id,
                title: recipe.title,
                weekdayLabel: day.dayOfWeek.shortDisplayName
            )
        }
    }

    func allAnswered(using outcomeStore: MealOutcomeStore) -> Bool {
        !rows.isEmpty && rows.allSatisfy { outcomeStore.outcome(for: $0.date) != nil }
    }

    func markResolved() {
        guard let weekStartDate else { return }
        defaults.set(weekStartDate, forKey: retroResolvedWeekKey)
    }

    func clear() {
        rows = []
    }

    private func isDismissed(for weekStartDate: String) -> Bool {
        defaults.string(forKey: retroResolvedWeekKey) == weekStartDate
    }

    static func doneCopy(recap: FamilyRecap?, monthName: String) -> String {
        guard let recap, recap.plannedWeekCount > 0 else {
            return L10n.string("retro.done")
        }
        let weekLine = L10n.format("retro.done.weekCount", recap.plannedWeekCount)
        guard let topRecipe = recap.topRecipeThisMonth else { return weekLine }
        return "\(weekLine) \(L10n.format("retro.done.topRecipe", monthName, topRecipe.title))"
    }

    static func betaFeedbackMailURL(weekStartDate: String?) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "support@veckly.app"
        components.queryItems = [
            URLQueryItem(name: "subject", value: L10n.string("retro.feedback.emailSubject")),
            URLQueryItem(name: "body", value: betaFeedbackEmailBody(weekStartDate: weekStartDate))
        ]
        return components.url
    }

    private static func betaFeedbackEmailBody(weekStartDate: String?) -> String {
        let weekLine = weekStartDate.map { L10n.format("retro.feedback.emailWeek", $0) }
        return [
            L10n.string("retro.feedback.emailIntro"),
            weekLine,
            "",
            L10n.string("retro.feedback.emailPrompt")
        ].compactMap { $0 }.joined(separator: "\n")
    }
}

struct RetroCard: View {
    let viewModel: RetroCardViewModel
    let outcomeStore: MealOutcomeStore
    let householdID: String
    let recipes: [FullRecipe]
    let onResolved: () -> Void

    @State private var detailRow: RetroCardViewModel.Row?

    private var allAnswered: Bool {
        viewModel.allAnswered(using: outcomeStore)
    }

    var body: some View {
        VecklyCard {
            VStack(alignment: .leading, spacing: 12) {
                header
                ForEach(viewModel.rows, id: \.date) { row in
                    retroRow(row)
                    if row.id != viewModel.rows.last?.id {
                        Divider().overlay(VecklyDesign.Colors.edgeLight)
                    }
                }
                syncStatus
                if allAnswered {
                    completionFooter
                }
            }
        }
        .sheet(item: $detailRow) { row in
            if let outcome = outcomeStore.outcome(for: row.date) {
                MealOutcomeDetailSheet(
                    initialDraft: outcome.draft,
                    mealTitle: row.title,
                    recipes: recipes,
                    onSave: { draft in await outcomeStore.setOutcome(draft) }
                )
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("retro.eyebrow")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VecklyDesign.Colors.inkFaint)
                    .textCase(.uppercase)
                Text("retro.title")
                    .font(VecklyDesign.Typography.cardTitle)
                    .foregroundStyle(VecklyDesign.Colors.inkDeep)
                Text("retro.outcomePrompt")
                    .font(.subheadline)
                    .foregroundStyle(VecklyDesign.Colors.inkMid)
            }
            Spacer()
            Button("retro.skip") { resolve() }
                .font(.caption.weight(.semibold))
                .foregroundStyle(VecklyDesign.Colors.inkFaint)
        }
    }

    private func retroRow(_ row: RetroCardViewModel.Row) -> some View {
        let outcome = outcomeStore.outcome(for: row.date)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(row.weekdayLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VecklyDesign.Colors.inkMid)
                    .frame(width: 36, alignment: .leading)
                Text(row.title)
                    .font(.body)
                    .foregroundStyle(VecklyDesign.Colors.inkDeep)
                    .lineLimit(2)
                    .layoutPriority(1)
                Spacer(minLength: 4)
                if outcomeStore.isPending(date: row.date) {
                    Image(systemName: "icloud.and.arrow.up")
                        .font(.caption)
                        .foregroundStyle(VecklyDesign.Colors.inkFaint)
                        .accessibilityLabel(L10n.string("retro.pending"))
                }
            }

            HStack(spacing: 6) {
                outcomeButton(.cooked, row: row, selected: outcome?.status == .cooked)
                outcomeButton(.changedPlan, row: row, selected: outcome?.status == .changedPlan)
                outcomeButton(.skipped, row: row, selected: outcome?.status == .skipped)
            }

            if let outcome {
                Button {
                    detailRow = row
                } label: {
                    Label(
                        outcomeHasDetails(outcome) ? L10n.string("retro.details.edit") : L10n.string("retro.details.add"),
                        systemImage: "slider.horizontal.3"
                    )
                    .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(VecklyDesign.Colors.hearthOrangeText)
            }
        }
        .padding(.vertical, 2)
    }

    private func outcomeButton(_ status: MealOutcomeStatus, row: RetroCardViewModel.Row, selected: Bool) -> some View {
        Button {
            guard let weekStartDate = viewModel.weekStartDate else { return }
            let existing = outcomeStore.outcome(for: row.date)
            let draft = MealOutcomeDraft(
                householdID: householdID,
                weekStartDate: weekStartDate,
                date: row.date,
                plannedRecipeID: row.recipeID,
                status: status,
                portionOutcome: existing?.portionOutcome,
                reason: existing?.reason,
                actualRecipeID: existing?.actualRecipeID,
                actualMealLabel: existing?.actualMealLabel
            )
            Task { await outcomeStore.setOutcome(draft) }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: status.systemImage)
                    .font(.footnote.weight(.semibold))
                Text(status.label)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(selected ? Color.white : VecklyDesign.Colors.inkMid)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 2)
            .background(selected ? VecklyDesign.Colors.hearthOrangeFill : VecklyDesign.Colors.surfaceStrong)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.format("accessibility.retro.outcome", status.label, row.title, row.weekdayLabel))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var syncStatus: some View {
        if let mutationError = outcomeStore.mutationError {
            HStack(spacing: 8) {
                Text(mutationError)
                    .font(.caption)
                    .foregroundStyle(VecklyDesign.Colors.inkMid)
                Spacer()
                Button("common.tryAgain") { Task { await outcomeStore.retryPending() } }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VecklyDesign.Colors.hearthOrangeText)
            }
        } else if let loadError = outcomeStore.errorMessage {
            HStack(spacing: 8) {
                Text(loadError)
                    .font(.caption)
                    .foregroundStyle(VecklyDesign.Colors.inkMid)
                Spacer()
                Button("common.tryAgain") { Task { await outcomeStore.retryLoad() } }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VecklyDesign.Colors.hearthOrangeText)
            }
        } else if outcomeStore.hasPendingSync {
            Label("retro.pending", systemImage: "icloud.and.arrow.up")
                .font(.caption)
                .foregroundStyle(VecklyDesign.Colors.inkMid)
        }
    }

    private var completionFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(RetroCardViewModel.doneCopy(recap: viewModel.recap, monthName: Date.now.formatted(.dateTime.month(.wide))))
                .font(.subheadline)
                .foregroundStyle(VecklyDesign.Colors.inkMid)
            Button("retro.finish") { resolve() }
                .buttonStyle(.borderedProminent)
                .tint(VecklyDesign.Colors.hearthOrangeFill)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func resolve() {
        viewModel.markResolved()
        onResolved()
    }

    private func outcomeHasDetails(_ outcome: MealOutcomeRecord) -> Bool {
        outcome.portionOutcome != nil || outcome.reason != nil || outcome.actualRecipeID != nil || outcome.actualMealLabel != nil
    }
}

private struct MealOutcomeDetailSheet: View {
    let mealTitle: String
    let recipes: [FullRecipe]
    let onSave: (MealOutcomeDraft) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: MealOutcomeDraft
    @State private var isSaving = false

    init(initialDraft: MealOutcomeDraft, mealTitle: String, recipes: [FullRecipe], onSave: @escaping (MealOutcomeDraft) async -> Void) {
        self.mealTitle = mealTitle
        self.recipes = recipes
        self.onSave = onSave
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("retro.details.plannedMeal", value: mealTitle)
                    Picker("retro.details.outcome", selection: $draft.status) {
                        ForEach(MealOutcomeStatus.allCases, id: \.self) { status in
                            Text(status.label).tag(status)
                        }
                    }
                }

                if draft.status != .skipped {
                    Section("retro.details.portions") {
                        Picker("retro.details.portions", selection: $draft.portionOutcome) {
                            Text("common.noAnswer").tag(MealPortionOutcome?.none)
                            ForEach(MealPortionOutcome.allCases, id: \.self) { outcome in
                                Text(outcome.label).tag(Optional(outcome))
                            }
                        }
                    }
                }

                Section("retro.details.reason") {
                    Picker("retro.details.reason", selection: $draft.reason) {
                        Text("common.noAnswer").tag(MealOutcomeReason?.none)
                        ForEach(MealOutcomeReason.allCases, id: \.self) { reason in
                            Text(reason.label).tag(Optional(reason))
                        }
                    }
                }

                if draft.status == .changedPlan {
                    Section("retro.details.replacement") {
                        Picker("retro.details.savedRecipe", selection: replacementRecipeBinding) {
                            Text("retro.details.noSavedRecipe").tag("")
                            ForEach(recipes) { recipe in
                                Text(recipe.title).tag(recipe.id)
                            }
                        }
                        TextField("retro.details.actualMealPlaceholder", text: actualMealLabelBinding)
                            .textInputAutocapitalization(.sentences)
                    }
                }
            }
            .navigationTitle("retro.details.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("common.save") { Task { await save() } }
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private var replacementRecipeBinding: Binding<String> {
        Binding(get: { draft.actualRecipeID ?? "" }, set: { draft.actualRecipeID = $0.isEmpty ? nil : $0 })
    }

    private var actualMealLabelBinding: Binding<String> {
        Binding(get: { draft.actualMealLabel ?? "" }, set: { draft.actualMealLabel = $0 })
    }

    private func save() async {
        isSaving = true
        await onSave(draft.normalized())
        isSaving = false
        dismiss()
    }
}

private extension MealOutcomeStatus {
    var label: String {
        switch self {
        case .cooked: return L10n.string("retro.outcome.cooked")
        case .changedPlan: return L10n.string("retro.outcome.changedPlan")
        case .skipped: return L10n.string("retro.outcome.skipped")
        }
    }

    var systemImage: String {
        switch self {
        case .cooked: return "checkmark"
        case .changedPlan: return "arrow.triangle.2.circlepath"
        case .skipped: return "minus"
        }
    }
}

private extension MealPortionOutcome {
    var label: String {
        switch self {
        case .tooLittle: return L10n.string("retro.portion.tooLittle")
        case .rightAmount: return L10n.string("retro.portion.rightAmount")
        case .tooMuch: return L10n.string("retro.portion.tooMuch")
        }
    }
}

private extension MealOutcomeReason {
    var label: String {
        switch self {
        case .easyWeeknight: return L10n.string("retro.reason.easyWeeknight")
        case .familyApproved: return L10n.string("retro.reason.familyApproved")
        case .goodLeftovers: return L10n.string("retro.reason.goodLeftovers")
        case .tooMuchEffort: return L10n.string("retro.reason.tooMuchEffort")
        case .familyPushback: return L10n.string("retro.reason.familyPushback")
        case .poorLeftovers: return L10n.string("retro.reason.poorLeftovers")
        }
    }
}

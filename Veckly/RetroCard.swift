import SwiftUI
import Observation

private let retroResolvedWeekKey = "veckly.retro.resolvedWeek"

/// Loads last week's un-rated meals for the Sunday retro ("Hur blev veckan?")
/// and owns the per-device dismissed/resolved state. Vote taps go straight
/// through `FeedbackStore` from the view — this model only decides *what* to
/// show and *whether* to show it at all.
@MainActor
@Observable
final class RetroCardViewModel {
    struct Row: Identifiable, Equatable {
        let recipeID: String
        let title: String
        let weekdayLabel: String
        var id: String { recipeID }
    }

    private(set) var rows: [Row] = []
    private(set) var weekStartDate: String?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Populates `rows` with last week's planned, non-skipped meals that the
    /// current user hasn't rated yet. Leaves `rows` empty (card stays hidden)
    /// when last week had nothing planned, everything is already rated, or
    /// the user already dismissed the retro for that week on this device.
    func load(household: Household, weekStore: WeekStore, feedbackStore: FeedbackStore) async {
        let lastWeekStart = WeekCalendar.addWeeks(to: WeekCalendar.currentWeekStartDate(), offset: -1)
        weekStartDate = lastWeekStart

        guard !isDismissed(for: lastWeekStart) else {
            rows = []
            return
        }
        guard let summary = await weekStore.peekWeekSummary(household: household, weekStartDate: lastWeekStart) else {
            rows = []
            return
        }

        rows = Self.buildRows(days: summary.days, feedbackStore: feedbackStore)
    }

    /// Pure grouping/filter step, split out from `load` so it's testable
    /// without a network round-trip: planned+recipe days only (a leftover-
    /// covered day has no `recipe` of its own and is naturally excluded),
    /// deduplicated by recipe (same dish twice last week → one row listing
    /// both weekdays), already-rated recipes dropped.
    static func buildRows(days: [WeekSummaryDay], feedbackStore: FeedbackStore) -> [Row] {
        var weekdaysByRecipeID: [String: [Weekday]] = [:]
        var titleByRecipeID: [String: String] = [:]
        var order: [String] = []

        for day in days {
            guard day.state == .planned, let recipe = day.recipe else { continue }
            guard feedbackStore.vote(for: recipe.id) == nil else { continue }
            if weekdaysByRecipeID[recipe.id] != nil {
                weekdaysByRecipeID[recipe.id]?.append(day.dayOfWeek)
            } else {
                weekdaysByRecipeID[recipe.id] = [day.dayOfWeek]
                titleByRecipeID[recipe.id] = recipe.title
                order.append(recipe.id)
            }
        }

        return order.compactMap { id in
            guard let weekdays = weekdaysByRecipeID[id], let title = titleByRecipeID[id] else { return nil }
            let weekdayLabel = weekdays.map(\.shortDisplayName).joined(separator: " + ")
            return Row(recipeID: id, title: title, weekdayLabel: weekdayLabel)
        }
    }

    /// Called once every row has a vote (all-rated collapse) or the user taps
    /// "Skip" — either way the retro shouldn't reappear for this week.
    func markResolved() {
        guard let weekStartDate else { return }
        defaults.set(weekStartDate, forKey: retroResolvedWeekKey)
    }

    /// Hides the card immediately (skip, or the collapse-to-confirmation
    /// finishing) without waiting for a reload round-trip.
    func clear() {
        rows = []
    }

    private func isDismissed(for weekStartDate: String) -> Bool {
        defaults.string(forKey: retroResolvedWeekKey) == weekStartDate
    }
}

/// "Hur blev veckan?" — a quick, skippable thumbs-up/down pass over last
/// week's meals, shown once per week on the current-week view. Doubles as
/// the primary feed for the family-memory feedback signal (see meal-scoring).
struct RetroCard: View {
    let viewModel: RetroCardViewModel
    let feedbackStore: FeedbackStore
    let householdID: String
    let onResolved: () -> Void

    @State private var isCollapsing = false

    private var allRated: Bool {
        !viewModel.rows.isEmpty && viewModel.rows.allSatisfy { feedbackStore.vote(for: $0.recipeID) != nil }
    }

    var body: some View {
        VecklyCard {
            if isCollapsing {
                Text("retro.done")
                    .font(.subheadline)
                    .foregroundStyle(VecklyDesign.Colors.inkMid)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    ForEach(viewModel.rows) { row in
                        retroRow(row)
                    }
                }
            }
        }
        .onChange(of: allRated) { _, isAllRated in
            guard isAllRated else { return }
            collapseAndResolve()
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
                    .font(VecklyDesign.Typography.displayHeading(size: 20))
                    .foregroundStyle(VecklyDesign.Colors.inkDeep)
            }
            Spacer()
            Button("retro.skip") {
                viewModel.markResolved()
                onResolved()
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(VecklyDesign.Colors.inkFaint)
        }
    }

    private func retroRow(_ row: RetroCardViewModel.Row) -> some View {
        let vote = feedbackStore.vote(for: row.recipeID)
        return HStack(spacing: 12) {
            Text(row.weekdayLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(VecklyDesign.Colors.inkMid)
                .frame(width: 44, alignment: .leading)

            Text(row.title)
                .font(.body)
                .foregroundStyle(vote != nil ? VecklyDesign.Colors.inkFaint : VecklyDesign.Colors.inkDeep)
                .lineLimit(1)

            Spacer()

            if vote != nil {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(VecklyDesign.Colors.hearthOrange)
                    .accessibilityHidden(true)
            } else {
                HStack(spacing: 8) {
                    retroVoteButton(.up, row: row)
                    retroVoteButton(.down, row: row)
                }
            }
        }
        .accessibilityElement(children: vote != nil ? .combine : .contain)
    }

    private func retroVoteButton(_ vote: MealVote, row: RetroCardViewModel.Row) -> some View {
        Button {
            Task { await castVote(vote, for: row) }
        } label: {
            Image(systemName: vote == .up ? "hand.thumbsup" : "hand.thumbsdown")
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.bordered)
        .tint(VecklyDesign.Colors.inkMid)
        .accessibilityLabel(
            L10n.format(
                vote == .up ? "accessibility.retro.voteUp" : "accessibility.retro.voteDown",
                row.title,
                row.weekdayLabel
            )
        )
    }

    private func castVote(_ vote: MealVote, for row: RetroCardViewModel.Row) async {
        let current = feedbackStore.vote(for: row.recipeID)
        await feedbackStore.setVote(householdID: householdID, recipeID: row.recipeID, vote: current == vote ? nil : vote)
    }

    private func collapseAndResolve() {
        viewModel.markResolved()
        withAnimation(.easeInOut(duration: 0.25)) {
            isCollapsing = true
        }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            onResolved()
        }
    }
}

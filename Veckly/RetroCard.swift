import SwiftUI
import Observation

private let retroResolvedWeekKey = "veckly.retro.resolvedWeek"

protocol RetroCardAPIClient {
    func familyRecap(householdID: String) async throws -> FamilyRecap
}

extension VecklyAPIClient: RetroCardAPIClient {}

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
    // D5: fetched alongside `rows` (only when the retro will actually show)
    // so the done-row can upgrade its copy with recap-copy once collapsed —
    // silently absent (nil) on any fetch failure, matching the calm,
    // never-block-the-ritual fallback used elsewhere in this card.
    private(set) var recap: FamilyRecap?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Populates `rows` with last week's planned, non-skipped meals that the
    /// current user hasn't rated yet. Leaves `rows` empty (card stays hidden)
    /// when last week had nothing planned, everything is already rated, or
    /// the user already dismissed the retro for that week on this device.
    func load(household: Household, weekStore: WeekStore, feedbackStore: FeedbackStore, apiClient: any RetroCardAPIClient) async {
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
        guard !rows.isEmpty else { return }
        recap = try? await apiClient.familyRecap(householdID: household.id)
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

    /// D5: builds the collapsed done-row's copy — recap-copy when there's
    /// history to draw on, the original plain confirmation otherwise. Pure
    /// (and `monthName` injected) so it's testable without a live clock.
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
                VStack(alignment: .leading, spacing: 8) {
                    Text(RetroCardViewModel.doneCopy(recap: viewModel.recap, monthName: Date.now.formatted(.dateTime.month(.wide))))
                        .font(.subheadline)
                        .foregroundStyle(VecklyDesign.Colors.inkMid)
                    if let feedbackURL = RetroCardViewModel.betaFeedbackMailURL(weekStartDate: viewModel.weekStartDate) {
                        Link(destination: feedbackURL) {
                            Label(L10n.string("retro.feedback.link"), systemImage: "envelope")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(VecklyDesign.Colors.hearthOrangeText)
                    }
                }
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
        return HStack(spacing: 10) {
            Text(row.weekdayLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(VecklyDesign.Colors.inkMid)
                .frame(width: 36, alignment: .leading)

            Text(row.title)
                .font(.body)
                .foregroundStyle(vote != nil ? VecklyDesign.Colors.inkFaint : VecklyDesign.Colors.inkDeep)
                .lineLimit(1)
                .layoutPriority(1)

            Spacer(minLength: 8)

            if vote != nil {
                Image(systemName: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(VecklyDesign.Colors.hearthOrangeFill)
                    .accessibilityHidden(true)
            } else {
                HStack(spacing: 4) {
                    retroVoteButton(.up, row: row)
                    retroVoteButton(.down, row: row)
                }
            }
        }
        .accessibilityElement(children: vote != nil ? .combine : .contain)
    }

    /// Visible affordance stays a compact 30pt circle — the 44×44 minimum
    /// touch target (Fas 8) is met with an invisible `.contentShape` hit
    /// area instead of `.buttonStyle(.bordered)`'s own chrome, which used
    /// to inflate the drawn circle well past 44pt and crowd out the recipe
    /// title next to it.
    private func retroVoteButton(_ vote: MealVote, row: RetroCardViewModel.Row) -> some View {
        Button {
            Task { await castVote(vote, for: row) }
        } label: {
            Image(systemName: vote == .up ? "hand.thumbsup" : "hand.thumbsdown")
                .font(.footnote)
                .foregroundStyle(VecklyDesign.Colors.inkMid)
                .frame(width: 30, height: 30)
                .background(VecklyDesign.Colors.surfaceStrong)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
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

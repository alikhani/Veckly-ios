import SwiftUI

/// The four hero states for "tonight's dinner" (beslut 16, Fas 3). Computed
/// once per render from the current week's day rows, the household's
/// planning scope, and prep/leftovers coverage — kept as a pure function (no
/// SwiftUI) so mode selection is unit-testable without a view hierarchy.
enum TonightMealCardMode: Equatable {
    /// Today has a dinner — its own recipe, or leftovers coverage. The
    /// ordinary case, any day of the week.
    case tonightMeal(day: WeekDayRowViewModel)
    /// Today is a planning day but nothing is assigned yet — the hero itself
    /// offers "Plan tonight" as its one action, instead of falling back to a
    /// day further ahead.
    case openTonight(day: WeekDayRowViewModel)
    /// Today isn't a planning day for this household (or is already
    /// resolved — e.g. skipped — with nothing to cook), so the hero looks
    /// ahead to the next planned dinner instead, in a calmer, non-"tonight"
    /// framing.
    case upcomingMeal(day: WeekDayRowViewModel)
    /// No planned dinner remains anywhere ahead in the active week — a
    /// quiet, closed state. No new week-navigation affordance is introduced
    /// here; the existing week picker already covers moving to next week.
    case weekDone

    /// The day this mode is centered on, if any — `nil` only for `.weekDone`.
    var day: WeekDayRowViewModel? {
        switch self {
        case .tonightMeal(let day), .openTonight(let day), .upcomingMeal(let day):
            return day
        case .weekDone:
            return nil
        }
    }

    static func compute(
        dayRows: [WeekDayRowViewModel],
        scope: WeekPlanningScope,
        hasCoverage: (WeekDayRowViewModel) -> Bool
    ) -> TonightMealCardMode {
        func isPlanned(_ day: WeekDayRowViewModel) -> Bool {
            // A skipped day keeps its `recipe` (skip is a flag layered on
            // top of an assignment, not a deletion), so `isSkipped` must be
            // checked explicitly or a skipped day could still surface as a
            // "planned" dinner.
            !day.isSkipped && (day.recipe != nil || hasCoverage(day))
        }

        guard let today = dayRows.first(where: { $0.isToday }) else {
            // No "today" row in the loaded week at all — shouldn't happen
            // for the current week, but keep this total rather than crash.
            if let next = dayRows.first(where: { isPlanned($0) && !$0.isPast }) {
                return .upcomingMeal(day: next)
            }
            return .weekDone
        }

        if isPlanned(today) {
            return .tonightMeal(day: today)
        }

        if scope.isRelevant(today), !today.isSkipped {
            return .openTonight(day: today)
        }

        let todayIndex = dayRows.firstIndex(where: { $0.id == today.id }) ?? -1
        if todayIndex >= 0, let next = dayRows[(todayIndex + 1)...].first(where: isPlanned) {
            return .upcomingMeal(day: next)
        }
        if let next = dayRows.first(where: { isPlanned($0) && !$0.isPast }) {
            return .upcomingMeal(day: next)
        }
        return .weekDone
    }
}

/// The single hero surface shown at the top of the week view every day
/// (beslut 16) — renders whichever of the four `TonightMealCardMode` states
/// applies. Owns the day's primary actions (`Öppna recept`, `Ändra`); the
/// corresponding row in the week list below never duplicates them (beslut 3).
struct TonightMealCard: View {
    let mode: TonightMealCardMode
    /// Leftovers coverage for a day with no recipe of its own — same lookup
    /// `WeekTabView` already uses, passed in rather than re-derived here.
    let coverage: (WeekDayRowViewModel) -> PrepBatchCoverage?
    let onViewRecipe: (WeekDayRowViewModel) -> Void
    let onSwap: (WeekDayRowViewModel) -> Void
    let onPlanTonight: (WeekDayRowViewModel) -> Void
    let onEatExtra: (WeekDayRowViewModel) -> Void
    let onRemoveCoverage: (WeekDayRowViewModel, PrepBatchCoverage) -> Void

    var body: some View {
        VecklyCard {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("tonightMealPanel")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .tonightMeal(let day):
            mealContent(day: day, eyebrowText: L10n.string("meal.tonight"), showTodayBadge: day.isToday)
        case .openTonight(let day):
            openTonightContent(day: day)
        case .upcomingMeal(let day):
            mealContent(day: day, eyebrowText: "\(L10n.string("week.nextUp")) · \(day.weekdayLabel)", showTodayBadge: false)
        case .weekDone:
            weekDoneContent
        }
    }

    // MARK: - Tonight / upcoming meal (modes 1 & 3)

    @ViewBuilder
    private func mealContent(day: WeekDayRowViewModel, eyebrowText: String, showTodayBadge: Bool) -> some View {
        // A day with no recipe of its own can still be the hero's subject if
        // leftovers cover it — show the covering dish instead of the (empty)
        // day fields, and hide the recipe/swap actions that assume a bound
        // `WeekSummaryRecipe`.
        let dayCoverage = day.recipe == nil ? coverage(day) : nil

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: eyebrowText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VecklyDesign.Colors.hearthOrangeText)
                    .textCase(.uppercase)
                Spacer()
                if showTodayBadge {
                    todayBadge
                }
            }

            Text(dayCoverage?.recipeTitle ?? day.mealTitle)
                .font(VecklyDesign.Typography.displayHeading(size: 24))
                .foregroundStyle(VecklyDesign.Colors.inkDeep)

            if let dayCoverage {
                Text(L10n.format("prep.leftoversFrom", WeekCalendar.shortDateLabel(yyyyMmDd: dayCoverage.cookDate)))
                    .font(.body)
                    .foregroundStyle(VecklyDesign.Colors.inkMid)
            } else if !day.detail.isEmpty {
                Text(day.detail)
                    .font(.body)
                    .foregroundStyle(VecklyDesign.Colors.inkMid)
            }

            if dayCoverage == nil, let reason = day.reason {
                Text(reason.label)
                    .font(.caption)
                    .foregroundStyle(VecklyDesign.Colors.inkFaint)
            }

            if dayCoverage == nil, day.confidence == .low {
                Label("week.confidence.low", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(VecklyDesign.Colors.hearthOrangeText)
            }

            if dayCoverage == nil, let streakWeeks = day.streakWeeks {
                Label(L10n.format("week.satiation.hint", streakWeeks), systemImage: "arrow.2.squarepath")
                    .font(.caption)
                    .foregroundStyle(VecklyDesign.Colors.hearthOrangeText)
            }

            if let dayCoverage {
                Button(role: .destructive) {
                    onRemoveCoverage(day, dayCoverage)
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.bordered)
                .tint(VecklyDesign.Colors.inkMid)
                .accessibilityLabel(L10n.string("prep.removeCoverage"))
            } else {
                actionRow(day: day)
            }
        }
    }

    /// The two visible primary actions plus the low-priority "Laga extra" —
    /// the hero owns these; the matching week-list row never repeats them
    /// (beslut 3). Lock lives in `DayDetailSheet` and the list's status icon
    /// only, not here.
    @ViewBuilder
    private func actionRow(day: WeekDayRowViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 8) {
                Button {
                    onViewRecipe(day)
                } label: {
                    Label("meal.openRecipe", systemImage: "book")
                }
                .buttonStyle(.bordered)
                .tint(VecklyDesign.Colors.inkMid)
                .accessibilityLabel(L10n.format("accessibility.viewRecipeFor", day.mealTitle))

                Button {
                    onSwap(day)
                } label: {
                    Label("meal.swap", systemImage: "arrow.2.squarepath")
                }
                .buttonStyle(.bordered)
                .tint(VecklyDesign.Colors.inkMid)
                .accessibilityLabel(L10n.format("accessibility.swapMealFor", day.weekdayLabel))
            }

            if day.recipe != nil {
                Button {
                    onEatExtra(day)
                } label: {
                    Label {
                        Text("prep.eatAgain")
                            .font(.caption)
                    } icon: {
                        Image(systemName: "arrow.3.trianglepath")
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(VecklyDesign.Colors.inkFaint)
                .padding(.top, 2)
            }
        }
    }

    // MARK: - Open tonight (mode 2)

    @ViewBuilder
    private func openTonightContent(day: WeekDayRowViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("meal.tonight")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VecklyDesign.Colors.hearthOrangeText)
                    .textCase(.uppercase)
                Spacer()
                todayBadge
            }

            Text("week.hero.open.title")
                .font(VecklyDesign.Typography.displayHeading(size: 22))
                .foregroundStyle(VecklyDesign.Colors.inkDeep)

            // Bordered, not `VecklyPrimaryButtonStyle()` — the status card's
            // "Plan the rest" is the page's one primary CTA (beslut 16, Fas 3
            // acceptance: "only one primary CTA per state"). Same bordered
            // vocabulary as the hero's other secondary actions below, just
            // tinted orange so it still reads as the important one here.
            Button("meal.planTonight") {
                onPlanTonight(day)
            }
            .buttonStyle(.bordered)
            .tint(VecklyDesign.Colors.hearthOrangeText)
            .padding(.top, 4)
        }
    }

    // MARK: - Week done (mode 4)

    private var weekDoneContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text("week.hero.done.title")
                    .font(VecklyDesign.Typography.displayHeading(size: 20))
                    .foregroundStyle(VecklyDesign.Colors.inkDeep)
            } icon: {
                Image(systemName: "checkmark.circle")
                    .font(.title3)
                    .foregroundStyle(VecklyDesign.Colors.hearthOrangeFill)
            }

            Text("week.hero.done.message")
                .font(.body)
                .foregroundStyle(VecklyDesign.Colors.inkMid)
        }
    }

    private var todayBadge: some View {
        Text("meal.today")
            .font(.caption.weight(.semibold))
            .foregroundStyle(VecklyDesign.Colors.hearthOrangeText)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .overlay(Capsule().stroke(VecklyDesign.Colors.hearthOrangeText, lineWidth: 1))
    }
}

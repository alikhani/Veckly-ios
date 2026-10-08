import Foundation

extension WeekScreenModel {
    // MARK: Loading

    /// Default trigger (`.sceneActive`) is a "make sure it's fresh" request —
    /// used when the tab reappears or the week picker re-selects the current
    /// week, both of which happen far more often than the data actually
    /// needs refetching. Explicit user actions (the toolbar refresh button,
    /// an error retry) pass `.pullToRefresh` instead, which always forces a
    /// real reload through `AppRefreshCoordinator`. Browsing to a different
    /// week (Last/Next) isn't a coordinator-owned resource — `loadWeek`
    /// still checks `usesSeededCoreReader` itself here, since nothing else
    /// on that path does — but it writes into the same `WeekStore.dayRows`
    /// slot `refreshWeek` tracks freshness for, so it must invalidate that
    /// tracking on the way out. Without this, browsing to Last/Next week and
    /// back to This week inside the coordinator's freshness window left the
    /// view stuck showing the browsed week's rows: the coordinator saw a
    /// recent "current week" fetch and no-op'd the `.sceneActive` return,
    /// never noticing `loadWeek` had overwritten the slot in between.
    func reloadViewedWeek(trigger: AppRefreshCoordinator.Trigger = .sceneActive) async {
        guard let household = householdStore.activeHousehold else { return }
        if isViewingCurrentWeek {
            await refreshCurrentWeek(household, trigger)
        } else {
            guard !usesSeededCoreReader else { return }
            await weekStore.loadWeek(household: household, weekStartDate: viewedWeekStartDate)
            invalidateWeekFreshness(household.id)
        }
    }

    /// Jumps to next week and loads it — the weekend nudge's CTA and the
    /// hero's "Plan next week".
    func planNextWeek() {
        viewedWeekOffset = .next
        lastTask = Task { await reloadViewedWeek() }
    }

    /// nil until checked. Populated by a lightweight prefetch only on
    /// weekend days while viewing the current week — it's not needed
    /// otherwise.
    func refreshNextWeekEmptyState() async {
        guard !usesSeededCoreReader else { return }
        guard isViewingCurrentWeek else { return }
        let weekday = Calendar.current.component(.weekday, from: Date())
        guard weekday == 1 || weekday == 7 else { return }
        guard let household = householdStore.activeHousehold else { return }
        let nextWeekStart = ViewedWeekOffset.next.weekStartDate
        let hasContent = await weekStore.peekHasContent(household: household, weekStartDate: nextWeekStart)
        nextWeekIsEmpty = !hasContent
    }

    /// Week/prep/household-details are core-reader resources —
    /// `RootView`'s `AppRefreshCoordinator.refreshCoreReader` (cold
    /// launch) and `AppModel.loadActiveHouseholdReaderData`
    /// (household switch/join/leave) already guarantee them fresh by
    /// the time this fires. Re-fetching them here too was Fas 7's
    /// core bug: a genuine second network call for the same data,
    /// not just a redundant guard. Retro and the next-week-empty peek
    /// aren't coordinator-owned resources (Retro is this screen's own
    /// `RetroCardViewModel`, reading *last* week; the peek is a
    /// cheap, weekend-only check — see `refreshNextWeekEmptyState`),
    /// so they stay here.
    ///
    /// The view runs this from `.task(id: activeHousehold?.id)`, i.e.
    /// whenever `activeHousehold?.id` actually changes (nil → set, or a
    /// household switch). That is also what `onAppear`'s own calls to these
    /// two can't reliably cover on cold launch: `onAppear` fires once, as
    /// soon as the tab mounts, which on cold launch can be *before*
    /// `householdStore.activeHousehold` is known — its own guards then
    /// silently no-op, and nothing re-tries until the next unrelated
    /// `scenePhase` change or tab reappearance. On a weekend day that left
    /// the "Plan next week" CTA (see `shouldOfferPlanNextWeekFromWeekDone`)
    /// waiting far longer than the actual network call took (2026-08-03 bug
    /// report) — this reliably firing the moment the household *is* known
    /// closes that gap.
    func activeHouseholdDidChange() async {
        guard !usesSeededCoreReader else { return }
        guard let household = householdStore.activeHousehold else { return }
        await refreshNextWeekEmptyState()
        await retro.load(household: household, weekStore: weekStore, outcomeStore: mealOutcomeStore, apiClient: retroClient)
    }

    func sceneDidBecomeActive() {
        // Handles the app being backgrounded over a week/day boundary
        // without needing a live timer.
        refreshWeekendNudgeDismissalState()
        // Week/shopping/prep/etc. are refreshed centrally by
        // `RootView`'s own scene-active handler through
        // `AppRefreshCoordinator` — this only covers what the
        // coordinator doesn't own: the weekend next-week peek and the
        // Sunday retro (see `activeHouseholdDidChange`).
        guard !usesSeededCoreReader, isViewingCurrentWeek,
              let household = householdStore.activeHousehold else { return }
        lastTask = Task {
            await refreshNextWeekEmptyState()
            await retro.load(household: household, weekStore: weekStore, outcomeStore: mealOutcomeStore, apiClient: retroClient)
        }
    }

    func retroResolved() {
        recordEvent(.retroCompleted, WeekCalendar.addWeeks(to: WeekCalendar.currentWeekStartDate(), offset: -1), [:])
        retro.clear()
    }

    func makeWeekBriefStore() -> WeekBriefStore {
        WeekBriefStore(apiClient: weekBriefClient)
    }

    // MARK: Deep links

    /// One-shot consumption of the "plan next week" deep link set by
    /// `AppNotificationDelegate` when the user tapped the Sunday planning
    /// reminder. Returns whether it actually fired, so callers can decide
    /// whether to fall back to their own default week selection.
    @discardableResult
    func consumePendingWeekPlanDeepLink() -> Bool {
        guard deepLinks.pendingWeekPlan() else { return false }
        deepLinks.clearPendingWeekPlan()
        viewedWeekOffset = .next
        return true
    }

    /// Consumes a pending widget/notification meal link: switches to its
    /// week, loads it, and opens that day's recipe — unless the link
    /// doesn't (or no longer) match a planned dinner. Either way the link is
    /// cleared, so it's acted on exactly once.
    func consumePendingMealDeepLink() async {
        guard case let .meal(date, recipeID) = deepLinks.pendingDeepLink() else { return }
        guard let targetDate = WeekCalendar.date(from: date) else {
            deepLinks.clearPendingDeepLink()
            return
        }
        let currentStart = WeekCalendar.date(from: WeekCalendar.currentWeekStartDate()) ?? targetDate
        let targetStartString = WeekCalendar.currentWeekStartDate(now: targetDate)
        let targetStart = WeekCalendar.date(from: targetStartString) ?? targetDate
        let days = WeekCalendar.calendar.dateComponents([.day], from: currentStart, to: targetStart).day ?? 0
        let weeks = days / 7
        guard let offset = ViewedWeekOffset(rawValue: weeks) else {
            deepLinks.clearPendingDeepLink()
            return
        }
        viewedWeekOffset = offset
        await reloadViewedWeek()
        guard let row = weekStore.dayRows.first(where: { $0.date == date }),
              let recipe = row.recipe,
              recipeID == nil || recipe.id == recipeID else {
            deepLinks.clearPendingDeepLink()
            return
        }
        sheet = .recipe(SelectedDayRecipe(day: row, recipe: recipe))
        deepLinks.clearPendingDeepLink()
    }

    // MARK: Weekend nudge

    var shouldShowWeekendNudge: Bool {
        guard isViewingCurrentWeek, !weekendNudgeDismissedToday, nextWeekIsEmpty == true else { return false }
        let weekday = Calendar.current.component(.weekday, from: Date())
        let isWeekend = weekday == 1 || weekday == 7 // Sunday = 1, Saturday = 7
        return isWeekend
    }

    /// Gate for the "Plan next week" CTA inside the hero's `.weekDone`
    /// state: only worth surfacing once the household is actually near the
    /// week boundary (Sat/Sun) or already knows next week is unplanned —
    /// not on an ordinary Tuesday when "the week is done" just means
    /// today's the last relevant planning day for a household that doesn't
    /// cook every night. Unlike the weekend nudge, this isn't
    /// per-day-dismissible: it's the one durable exit from an otherwise
    /// dead-end completion state (see the 2026-08-02 TestFlight bug report
    /// — a household landed here from the Sunday reminder notification
    /// with no visible way to start planning next week).
    var shouldOfferPlanNextWeekFromWeekDone: Bool {
        guard isViewingCurrentWeek, heroMode == .weekDone else { return false }
        let weekday = Calendar.current.component(.weekday, from: Date())
        let isLateInWeek = weekday == 1 || weekday == 7 // Sunday = 1, Saturday = 7
        return isLateInWeek || nextWeekIsEmpty == true
    }

    func refreshWeekendNudgeDismissalState() {
        guard let dismissedDate = defaults.object(forKey: Self.weekendNudgeDismissalKey) as? Date else {
            weekendNudgeDismissedToday = false
            return
        }
        weekendNudgeDismissedToday = Calendar.current.isDateInToday(dismissedDate)
    }

    func dismissWeekendNudgeForToday() {
        defaults.set(Date(), forKey: Self.weekendNudgeDismissalKey)
        weekendNudgeDismissedToday = true
    }
}

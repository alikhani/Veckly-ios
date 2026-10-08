import Foundation

/// Snapshot of the days a "Regenerate" run is about to overwrite, captured
/// just before the API call — restoring from it is how the undo banner puts
/// the previous plan back without the backend needing an undo endpoint.
struct RegenerateUndoContext: Identifiable {
    let rows: [WeekDayRowViewModel]
    let weekStartDate: String
    var id: String { weekStartDate }
}

extension WeekScreenModel {
    // MARK: Generate / regenerate

    /// Opens the Week Brief for the viewed week — the step every
    /// Generate/Regenerate goes through before `performGenerate`.
    func presentWeekBrief(regenerate: Bool) {
        guard session() != nil else { return }
        sheet = .weekBrief(WeekBriefPresentation(
            weekStartDate: viewedWeekStartDate,
            regenerate: regenerate
        ))
    }

    /// Runs Generate/Regenerate. When replacing an already-full week, snapshots
    /// the unlocked/unskipped rows first so a successful run can offer "Undo" —
    /// there's no backend undo endpoint, so restoring is just re-issuing the
    /// same assign/clear calls a user would make by hand.
    func performGenerate(
        regenerate: Bool,
        weekStartDate: String? = nil,
        pantryItemKeys: [String] = [],
        portionAdjustments: [WeekPortionAdjustment] = []
    ) async {
        guard weekStore.generatingWeekStartDate == nil else { return }
        guard let household = householdStore.activeHousehold else { return }
        guard let userID = authSessionStore.userID else {
            await onUnauthorized()
            return
        }

        // Captured once, up front — `viewedWeekStartDate` is a computed
        // property that tracks live navigation, and the API call below can
        // take long enough for the user to browse to a different week
        // before it resolves. Everything about *this* generate run (the
        // snapshot, the API call, and the undo banner it may offer) must
        // stay pinned to the week it was actually generated for.
        let targetWeekStartDate = weekStartDate ?? viewedWeekStartDate
        let rowsBeforeFill = weekStore.dayRows
        let preRegenerateSnapshot = regenerate
            ? weekStore.dayRows.filter { !$0.isPast && !$0.isLocked && !$0.isSkipped }
            : []
        let wasEmptyBefore = hasOpenRelevantDays
        let hadWeekContentBefore = weekStore.hasWeekContent

        if !regenerate {
            failedFillWeekStartDate = nil
            fillCompletionNotice = nil
        }

        shoppingListStore.invalidateCache()
        await weekStore.generateWeek(
            household: household,
            userID: userID,
            regenerate: regenerate,
            viewedWeekStartDate: targetWeekStartDate,
            pantryItemKeys: pantryItemKeys
        )
        let generateSucceeded = weekStore.mutationError == nil
        if !regenerate, viewedWeekStartDate == targetWeekStartDate {
            if weekStore.mutationError == nil {
                fillCompletionNotice = WeekFillCompletionNotice.make(
                    before: rowsBeforeFill,
                    after: weekStore.dayRows
                )
            } else {
                failedFillWeekStartDate = targetWeekStartDate
            }
        }
        // After generating, so only days that kept the suggestion's recipe
        // get the new portions (see `applyPortionAdjustments`).
        await weekStore.applyPortionAdjustments(
            portionAdjustments,
            household: household,
            userID: userID,
            weekStartDate: targetWeekStartDate
        )
        refreshShoppingListAfterWeekMutation(household: household, weekStartDate: targetWeekStartDate)
        if !regenerate, !hadWeekContentBefore, generateSucceeded {
            recordEvent(.firstWeekGenerated, targetWeekStartDate, [
                "plannedDinners": .int(plannedDinnerCount)
            ])
        }
        checkForSessionEnd(wasEmptyBefore: wasEmptyBefore)

        guard regenerate, generateSucceeded, !preRegenerateSnapshot.isEmpty else { return }
        // Only offer undo if the user is still looking at the week that was
        // just regenerated — otherwise there's nothing sensible to restore
        // into the currently-visible week, and no banner should appear for
        // a week that isn't on screen.
        guard viewedWeekStartDate == targetWeekStartDate else { return }
        presentRegenerateUndo(rows: preRegenerateSnapshot, weekStartDate: targetWeekStartDate)
    }

    private func presentRegenerateUndo(rows: [WeekDayRowViewModel], weekStartDate: String) {
        regenerateUndoDismissTask?.cancel()
        regenerateUndo = RegenerateUndoContext(rows: rows, weekStartDate: weekStartDate)
        let duration = regenerateUndoDuration
        regenerateUndoDismissTask = Task {
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            regenerateUndo = nil
        }
    }

    func undoRegenerate(_ context: RegenerateUndoContext) {
        regenerateUndoDismissTask?.cancel()
        regenerateUndo = nil
        guard let household = householdStore.activeHousehold,
              let userID = authSessionStore.userID else { return }
        // Defense in depth alongside the `viewedWeekDidChange` dismissal
        // below — never replay a snapshot into a week other than the one it
        // was taken from.
        guard context.weekStartDate == viewedWeekStartDate else { return }

        lastTask = Task {
            shoppingListStore.invalidateCache()
            for row in context.rows {
                if let recipe = row.recipe {
                    await weekStore.assignMeal(day: row, recipe: recipe, household: household, userID: userID, viewedWeekStartDate: context.weekStartDate)
                } else {
                    await weekStore.unassignMeal(day: row, household: household, userID: userID, viewedWeekStartDate: context.weekStartDate)
                }
            }
            refreshShoppingListAfterWeekMutation(household: household, weekStartDate: context.weekStartDate)
        }
    }

    /// Called by the view whenever the viewed week actually changes.
    ///
    /// The undo banner replays writes against `context.weekStartDate`
    /// by matching rows on weekday only, with no check that the
    /// currently-loaded `dayRows` still belong to that week — so if
    /// the user browses to a different week while the banner is still
    /// up, a tap on "Undo" would overwrite the *other* week's rows
    /// with the regenerated week's snapshot. Simplest safe fix: the
    /// banner only makes sense for the week it was generated for, so
    /// drop it the moment the user navigates away from that week.
    func viewedWeekDidChange() {
        regenerateUndoDismissTask?.cancel()
        regenerateUndo = nil
        failedFillWeekStartDate = nil
        fillCompletionNotice = nil
    }

    /// Dismissing the week error banner also forgets which fill failed, so
    /// its "Try again" doesn't outlive the message it belongs to.
    func dismissWeekMutationError() {
        failedFillWeekStartDate = nil
        weekStore.clearMutationError()
    }

    // MARK: Planning session end

    /// Fires the "Veckan är klar" beat the instant the last *relevant* open
    /// day gets filled or skipped by a real user action — never on merely
    /// browsing to an already-full week (only mutators that can close the
    /// last gap call this, each with `hasOpenRelevantDays` captured just
    /// before they ran).
    func checkForSessionEnd(wasEmptyBefore: Bool) {
        guard isViewingCurrentWeek else { return }
        let summary = weekSessionSummary
        guard SessionEndTrigger.shouldShow(
            wasEmptyBeforeMutation: wasEmptyBefore,
            isCompleteNow: !hasOpenRelevantDays,
            plannedDinnerCount: summary.plannedDinnerCount
        ) else { return }
        showSessionEndBeat = true
        recordEvent(.weekCompleted, viewedWeekStartDate, [
            "plannedDinners": .int(summary.plannedDinnerCount),
            "quickDinners": .int(summary.quickDinnerCount),
            "prepFriendlyDinners": .int(summary.prepFriendlyDinnerCount)
        ])
    }

    func dismissSessionEndBeat() {
        showSessionEndBeat = false
    }
}

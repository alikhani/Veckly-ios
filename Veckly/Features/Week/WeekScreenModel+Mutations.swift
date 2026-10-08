import Foundation

extension WeekScreenModel {
    // MARK: Week mutations

    /// Returns whether the skip was started (a session existed), so the
    /// caller can dismiss whatever sheet it came from. `checksSessionEnd`
    /// is set by the callers that can close the week's last open day.
    @discardableResult
    func toggleSkip(_ day: WeekDayRowViewModel, checksSessionEnd: Bool = false) -> Bool {
        guard let (household, userID) = session() else { return false }
        let wasEmptyBefore = hasOpenRelevantDays
        lastTask = Task {
            await weekStore.toggleSkip(day: day, household: household, userID: userID, viewedWeekStartDate: viewedWeekStartDate)
            if checksSessionEnd {
                checkForSessionEnd(wasEmptyBefore: wasEmptyBefore)
            }
        }
        return true
    }

    /// Clears any stale mutation error first, like the other lock entry
    /// points. Returns whether the toggle was started, so the view can show
    /// its one-time lock explanation.
    @discardableResult
    func toggleLock(_ day: WeekDayRowViewModel) -> Bool {
        guard let (household, userID) = session() else { return false }
        weekStore.clearMutationError()
        lastTask = Task {
            await weekStore.toggleLock(day: day, household: household, userID: userID)
        }
        return true
    }

    @discardableResult
    func assignMeal(_ day: WeekDayRowViewModel, recipe: WeekSummaryRecipe) -> Bool {
        guard let (household, userID) = session() else { return false }
        let wasEmptyBefore = hasOpenRelevantDays
        lastTask = Task {
            shoppingListStore.invalidateCache()
            await weekStore.assignMeal(day: day, recipe: recipe, household: household, userID: userID, viewedWeekStartDate: viewedWeekStartDate)
            await refreshShoppingListAfterWeekMutation(household: household, weekStartDate: viewedWeekStartDate)
            checkForSessionEnd(wasEmptyBefore: wasEmptyBefore)
        }
        return true
    }

    @discardableResult
    func unassignMeal(_ day: WeekDayRowViewModel) -> Bool {
        guard let (household, userID) = session() else { return false }
        lastTask = Task {
            shoppingListStore.invalidateCache()
            await weekStore.unassignMeal(day: day, household: household, userID: userID, viewedWeekStartDate: viewedWeekStartDate)
            await refreshShoppingListAfterWeekMutation(household: household, weekStartDate: viewedWeekStartDate)
        }
        return true
    }

    /// Silent `false` without a session (no unauthorized handling) — the
    /// portion-suggestion card just reports that the change didn't apply.
    func applyPortionSuggestion(_ day: WeekDayRowViewModel, servings: Int) async -> Bool {
        guard let household = householdStore.activeHousehold,
              let userID = authSessionStore.userID else { return false }
        do {
            try await weekStore.changeServings(
                day: day,
                servings: servings,
                household: household,
                userID: userID,
                viewedWeekStartDate: viewedWeekStartDate,
                consumesPortionSuggestion: true
            )
            shoppingListStore.invalidateCache()
            await refreshShoppingListAfterWeekMutation(household: household, weekStartDate: viewedWeekStartDate)
            return true
        } catch {
            return false
        }
    }

    func ignorePortionSuggestion(_ day: WeekDayRowViewModel) async -> Bool {
        guard let household = householdStore.activeHousehold,
              let recipeID = day.recipe?.id else { return false }
        return await weekStore.ignorePortionSuggestion(
            recipeID: recipeID,
            household: household,
            weekStartDate: viewedWeekStartDate
        )
    }

    func resetPortionMemory(_ day: WeekDayRowViewModel) async -> Bool {
        guard let household = householdStore.activeHousehold,
              let recipeID = day.recipe?.id else { return false }
        return await weekStore.resetPortionMemory(
            recipeID: recipeID,
            household: household,
            weekStartDate: viewedWeekStartDate
        )
    }

    /// Removes a leftovers assignment from a day. Returns whether it was
    /// started (an active household existed).
    @discardableResult
    func removeCoverage(_ day: WeekDayRowViewModel, coverage dayCoverage: PrepBatchCoverage) -> Bool {
        guard let household = householdStore.activeHousehold else { return false }
        lastTask = Task {
            try? await prepBatchStore.removeAssignment(
                householdID: household.id,
                batchID: dayCoverage.batchID,
                date: day.date,
                mealType: dayCoverage.mealType
            )
        }
        return true
    }

    /// For flows that change the week plan through their own sheet
    /// (rescue, reuse last week): the shopping list must follow.
    func weekPlanChangedElsewhere(household: Household) async {
        shoppingListStore.invalidateCache()
        await refreshShoppingListAfterWeekMutation(household: household, weekStartDate: viewedWeekStartDate)
    }

    func refreshShoppingListAfterWeekMutation(household: Household, weekStartDate: String) async {
        guard weekStore.mutationError == nil else { return }
        shoppingListStore.invalidateCache()
        await shoppingListStore.loadCurrentWeek(household: household, weekStartDate: weekStartDate, origin: .userInitiated)
    }
}

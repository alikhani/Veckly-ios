import Foundation

extension WeekScreenModel {
    // MARK: Quality suggestion

    var qualitySuggestion: WeekQualitySuggestion? {
        WeekQualitySuggestion.make(
            days: weekPlanningScope.relevantDays(in: weekStore.dayRows),
            recipes: recipeStore.recipes,
            prepCoveredDates: prepCoveredDates
        )
    }

    var visibleQualitySuggestion: WeekQualitySuggestion? {
        guard let suggestion = qualitySuggestion else { return nil }
        return dismissedQualitySuggestionKeys.contains(qualitySuggestionWeekKey) ? nil : suggestion
    }

    private var qualitySuggestionWeekKey: String {
        let householdID = householdStore.activeHousehold?.id ?? ""
        return "\(householdID):\(viewedWeekStartDate)"
    }

    func dismissQualitySuggestionsForViewedWeek() {
        var keys = dismissedQualitySuggestionKeys
        keys.insert(qualitySuggestionWeekKey)
        defaults.set(keys.sorted().joined(separator: "|"), forKey: Self.dismissedQualitySuggestionKeysKey)
        dismissedQualitySuggestionKeys = keys
    }

    /// A leftovers suggestion is reviewed in the prep-batch sheet; a
    /// replacement suggestion is applied right away (and only dismissed
    /// once the write succeeded).
    func applyQualitySuggestion(_ suggestion: WeekQualitySuggestion) {
        guard canMutateDay(suggestion.day) else { return }
        if suggestion.kind == .useLeftovers,
           let source = suggestion.sourceDay,
           let recipe = source.recipe {
            dismissQualitySuggestionsForViewedWeek()
            presentAfterDismiss {
                .prepBatch(PrepBatchSeed(
                    recipeID: recipe.id,
                    cookDate: source.date,
                    weekStartDate: self.viewedWeekStartDate,
                    assignedDate: suggestion.day.date
                ))
            }
            return
        }

        guard let recipe = suggestion.replacement else { return }
        guard let (household, userID) = session() else { return }
        let wasEmptyBefore = hasOpenRelevantDays
        lastTask = Task {
            shoppingListStore.invalidateCache()
            await weekStore.assignMeal(
                day: suggestion.day,
                recipe: WeekSummaryRecipe(fullRecipe: recipe),
                household: household,
                userID: userID,
                viewedWeekStartDate: viewedWeekStartDate
            )
            refreshShoppingListAfterWeekMutation(household: household, weekStartDate: viewedWeekStartDate)
            guard weekStore.mutationError == nil else { return }
            dismissQualitySuggestionsForViewedWeek()
            checkForSessionEnd(wasEmptyBefore: wasEmptyBefore)
        }
    }
}

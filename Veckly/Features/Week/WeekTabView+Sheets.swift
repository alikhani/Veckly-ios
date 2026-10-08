import SwiftUI

/// Sheet routing for the Week tab — the same `WeekTabView` type, kept in its
/// own file so the screen's composition stays readable.
extension WeekTabView {
    /// Routes `model.sheet` to its view. Each sheet's own close/dismiss
    /// callbacks go through `model.dismissSheet(sheet.id)`, so they can only
    /// ever close the sheet they belong to.
    @ViewBuilder
    func sheetContent(_ sheet: WeekSheet) -> some View {
        switch sheet {
        case let .recipe(pair):
            let interaction = model.weekListPresentation.interaction(for: pair.day)
            let allowsDayMutation = interaction == .editDay
            NavigationStack {
                RecipeDetailView(
                    recipe: pair.recipe,
                    householdID: appModel.householdStore.activeHousehold?.id ?? "",
                    isSkipped: allowsDayMutation ? pair.day.isSkipped : nil,
                    onSkip: allowsDayMutation ? {
                        guard model.canEditDay(pair.day) else { return }
                        if model.toggleSkip(pair.day) {
                            model.dismissSheet(sheet.id)
                        }
                    } : nil,
                    isReadOnly: !allowsDayMutation
                )
            }
        case let .mealPicker(day):
            MealPickerSheet(
                day: day,
                isSkipped: day.isSkipped,
                coverage: model.coverage(for: day),
                householdID: appModel.householdStore.activeHousehold?.id ?? "",
                weekStartDate: model.viewedWeekStartDate,
                onSelect: { recipe in
                    guard model.canMutateDay(day) else { return }
                    model.assignMeal(day, recipe: WeekSummaryRecipe(fullRecipe: recipe))
                },
                onClear: {
                    guard model.canMutateDay(day) else { return }
                    if model.unassignMeal(day) {
                        model.dismissSheet(sheet.id)
                    }
                },
                onSkip: {
                    guard model.canMutateDay(day) else { return }
                    model.toggleSkip(day, checksSessionEnd: true)
                },
                onMarkAsLeftover: { recipeID in
                    guard model.canMutateDay(day) else { return }
                    model.dismissSheet(sheet.id)
                    model.presentAfterDismiss {
                        .prepBatch(PrepBatchSeed(
                            recipeID: recipeID,
                            cookDate: day.date,
                            weekStartDate: model.viewedWeekStartDate
                        ))
                    }
                },
                onMarkAsLeftoverNoRecipe: {
                    guard model.canMutateDay(day) else { return }
                    guard let household = appModel.householdStore.activeHousehold else { return }
                    let profile = appModel.householdStore.cachedProfile(for: household.id)
                    model.dismissSheet(sheet.id)
                    model.presentAfterDismiss {
                        .leftoversWithoutRecipe(LeftoversWithoutRecipeSeed(
                            day: day,
                            defaultPortions: LeftoversWithoutRecipeFormModel.defaultPortions(profile: profile)
                        ))
                    }
                },
                onRemoveCoverage: {
                    guard model.canMutateDay(day) else { return }
                    guard let dayCoverage = model.coverage(for: day),
                          model.removeCoverage(day, coverage: dayCoverage) else { return }
                    model.dismissSheet(sheet.id)
                },
                onDismiss: { model.dismissSheet(sheet.id) }
            )
        case let .rescue(day):
            if let household = appModel.householdStore.activeHousehold {
                WeekRescueSheet(
                    day: day,
                    household: household,
                    weekStartDate: model.viewedWeekStartDate,
                    expectedUpdatedAt: appModel.weekStore.summary?.updatedAt,
                    onApplied: {
                        await model.weekPlanChangedElsewhere(household: household)
                    }
                )
            }
        case .previousWeekProposal:
            if let household = appModel.householdStore.activeHousehold {
                PreviousWeekProposalSheet(
                    household: household,
                    weekStartDate: model.viewedWeekStartDate,
                    expectedUpdatedAt: appModel.weekStore.summary?.updatedAt,
                    onApplied: {
                        await model.weekPlanChangedElsewhere(household: household)
                    },
                    onSwap: { date in
                        model.presentAfterDismiss {
                            appModel.weekStore.dayRows.first(where: { $0.date == date }).map(WeekSheet.mealPicker)
                        }
                    }
                )
            }
        case let .dayDetail(day):
            DayDetailSheet(
                day: day,
                householdID: appModel.householdStore.activeHousehold?.id ?? "",
                onViewRecipe: {
                    model.dismissSheet(sheet.id)
                    model.presentAfterDismiss {
                        day.recipe.map { .recipe(SelectedDayRecipe(day: day, recipe: $0)) }
                    }
                },
                onSwap: {
                    guard model.canEditDay(day) else { return }
                    model.dismissSheet(sheet.id)
                    model.presentAfterDismiss { .mealPicker(day) }
                },
                onSkip: {
                    guard model.canEditDay(day) else { return }
                    model.toggleSkip(day)
                },
                onClear: {
                    guard model.canEditDay(day) else { return }
                    if model.unassignMeal(day) {
                        model.dismissSheet(sheet.id)
                    }
                },
                onMarkAsLeftover: {
                    guard model.canEditDay(day) else { return }
                    model.dismissSheet(sheet.id)
                    if let recipe = day.recipe {
                        model.presentAfterDismiss {
                            .prepBatch(PrepBatchSeed(
                                recipeID: recipe.id,
                                cookDate: day.date,
                                weekStartDate: model.viewedWeekStartDate
                            ))
                        }
                    }
                },
                isLocked: day.isLocked,
                onToggleLock: {
                    guard model.canEditDay(day) else { return }
                    guard model.toggleLock(day) else { return }
                    if !hasSeenLockExplanation {
                        showLockExplanation = true
                    }
                },
                onApplyPortionSuggestion: { servings in
                    await model.applyPortionSuggestion(day, servings: servings)
                },
                onIgnorePortionSuggestion: {
                    await model.ignorePortionSuggestion(day)
                },
                onResetPortionMemory: {
                    await model.resetPortionMemory(day)
                },
                onDismiss: { model.dismissSheet(sheet.id) }
            )
        case let .prepBatch(seed):
            PrepBatchFormSheet(
                initialRecipeID: seed.recipeID,
                initialCookDate: WeekCalendar.date(from: seed.cookDate) ?? Date(),
                weekStartDate: seed.weekStartDate,
                initialAssignedDate: seed.assignedDate
            )
        case let .leftoversWithoutRecipe(seed):
            LeftoversWithoutRecipeSheet(
                day: seed.day,
                initialPortions: seed.defaultPortions,
                weekStartDate: model.viewedWeekStartDate
            )
        case let .weekBrief(presentation):
            if let household = appModel.householdStore.activeHousehold,
               let userID = appModel.authSessionStore.userID {
                WeekBriefSheet(
                    store: model.makeWeekBriefStore(),
                    householdID: household.id,
                    weekStartDate: presentation.weekStartDate,
                    userID: userID,
                    rows: appModel.weekStore.dayRows,
                    profile: appModel.householdStore.cachedProfile(for: household.id),
                    isRegenerating: presentation.regenerate,
                    pantryItems: PantryPlanningItem.suggestions(from: appModel.shoppingListStore.pantryStock),
                    onGenerate: { pantryItemKeys, portionAdjustments in
                        await model.performGenerate(
                            regenerate: presentation.regenerate,
                            weekStartDate: presentation.weekStartDate,
                            pantryItemKeys: pantryItemKeys,
                            portionAdjustments: portionAdjustments
                        )
                    }
                )
            }
        }
    }
}

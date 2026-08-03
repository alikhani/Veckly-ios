import Foundation
import Testing
@testable import Veckly

/// Regression coverage for the 2026-08-03 cold-launch loading-flash bug:
/// `HouseholdStore.isLoading` only flips `true` inside the unstructured
/// `Task` `AppRefreshCoordinator.run` spawns for the household bootstrap, so
/// there's a real window on cold launch where `WeekTabView` is mounted with
/// `isLoading == false` on both stores and no active household yet. Without
/// `WeekTabView.shouldShowLoadingPanel` treating "no active household, no
/// error" as loading too, that window rendered the empty-week/hero content
/// for a frame before the bootstrap `Task` started and flipped `isLoading`
/// back — the "loads, something appears briefly, then loads again" flash.
struct WeekTabViewTests {
    @Test func showsLoadingWhileHouseholdOrWeekStoreIsLoading() {
        #expect(WeekTabView.shouldShowLoadingPanel(
            isLoadingHouseholds: true,
            isLoadingWeek: false,
            hasActiveHousehold: true,
            householdErrorMessage: nil
        ))
        #expect(WeekTabView.shouldShowLoadingPanel(
            isLoadingHouseholds: false,
            isLoadingWeek: true,
            hasActiveHousehold: true,
            householdErrorMessage: nil
        ))
    }

    /// The exact cold-launch gap: neither store has started loading yet
    /// (the bootstrap `Task` hasn't run its first line), but there's also no
    /// active household to show real content for. Must still read as
    /// loading, not as an empty-week/hero state.
    @Test func showsLoadingWhenNoActiveHouseholdYetEvenIfNeitherStoreHasStartedLoading() {
        #expect(WeekTabView.shouldShowLoadingPanel(
            isLoadingHouseholds: false,
            isLoadingWeek: false,
            hasActiveHousehold: false,
            householdErrorMessage: nil
        ))
    }

    /// A genuine bootstrap failure must fall through to the `ErrorPanel`
    /// branch instead of spinning forever — `bootstrapAndLoadHouseholds`
    /// always ends with either an active household or `errorMessage` set,
    /// so this is the one legitimate case where "no active household" isn't
    /// "still loading."
    @Test func doesNotShowLoadingWhenHouseholdBootstrapFailed() {
        #expect(!WeekTabView.shouldShowLoadingPanel(
            isLoadingHouseholds: false,
            isLoadingWeek: false,
            hasActiveHousehold: false,
            householdErrorMessage: "Something went wrong"
        ))
    }

    @Test func doesNotShowLoadingOnceHouseholdIsActiveAndNeitherStoreIsLoading() {
        #expect(!WeekTabView.shouldShowLoadingPanel(
            isLoadingHouseholds: false,
            isLoadingWeek: false,
            hasActiveHousehold: true,
            householdErrorMessage: nil
        ))
    }
}

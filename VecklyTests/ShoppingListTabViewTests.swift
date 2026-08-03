import Foundation
import Testing
@testable import Veckly

/// Regression coverage for `ShoppingListTabView`'s cold-launch loading-flash
/// bug, found 2026-08-03 as the same underlying gap already fixed in
/// `WeekTabView` (see `WeekTabViewTests.swift` and `CoreLoadingGate`'s doc
/// comment in `StatePanels.swift`): `ShoppingListTabView`'s loading gate
/// used to check only `shoppingListStore.isLoading`, not
/// `householdStore.isLoading` or whether a household was active yet, so on
/// cold launch it fell through both the loading and error branches straight
/// into the "No week plan at all" empty-state card — a third visible state,
/// not just the loading/content flash `WeekTabView` had — before flipping to
/// the loading panel and then to real content once the bootstrap `Task`
/// actually ran.
struct ShoppingListTabViewTests {
    @Test func showsLoadingWhileHouseholdOrShoppingListStoreIsLoading() {
        #expect(CoreLoadingGate.shouldShowLoadingPanel(
            isLoadingHouseholds: true,
            isLoadingContent: false,
            hasActiveHousehold: true,
            householdErrorMessage: nil
        ))
        #expect(CoreLoadingGate.shouldShowLoadingPanel(
            isLoadingHouseholds: false,
            isLoadingContent: true,
            hasActiveHousehold: true,
            householdErrorMessage: nil
        ))
    }

    /// The exact cold-launch gap: neither store has started loading yet
    /// (the bootstrap `Task` hasn't run its first line), but there's also no
    /// active household to show real content for. Must still read as
    /// loading, not fall through to the empty-state card.
    @Test func showsLoadingWhenNoActiveHouseholdYetEvenIfNeitherStoreHasStartedLoading() {
        #expect(CoreLoadingGate.shouldShowLoadingPanel(
            isLoadingHouseholds: false,
            isLoadingContent: false,
            hasActiveHousehold: false,
            householdErrorMessage: nil
        ))
    }

    /// A genuine bootstrap failure must fall through to the `ErrorPanel`
    /// branch instead of spinning forever or showing the empty-state card.
    @Test func doesNotShowLoadingWhenHouseholdBootstrapFailed() {
        #expect(!CoreLoadingGate.shouldShowLoadingPanel(
            isLoadingHouseholds: false,
            isLoadingContent: false,
            hasActiveHousehold: false,
            householdErrorMessage: "Something went wrong"
        ))
    }

    @Test func doesNotShowLoadingOnceHouseholdIsActiveAndNeitherStoreIsLoading() {
        #expect(!CoreLoadingGate.shouldShowLoadingPanel(
            isLoadingHouseholds: false,
            isLoadingContent: false,
            hasActiveHousehold: true,
            householdErrorMessage: nil
        ))
    }
}

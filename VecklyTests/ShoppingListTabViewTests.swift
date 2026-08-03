import Foundation
import Testing
@testable import Veckly

/// Regression coverage for `ShoppingListTabView`'s cold-launch loading-flash
/// bug, found 2026-08-03 as the same underlying gap already fixed in
/// `WeekTabView` (see `WeekTabViewTests.swift` and `CoreLoadingGate`'s doc
/// comment in `StatePanels.swift`). There are two layers: `ShoppingListTabView`'s
/// loading gate used to check only `shoppingListStore.isLoading`, not
/// `householdStore.isLoading` or whether a household was active yet, so on
/// cold launch it fell through both the loading and error branches straight
/// into the "No week plan at all" empty-state card. Closing that gap alone
/// wasn't enough either: once the household is known, `ShoppingListStore`'s
/// own fetch `Task` still hasn't necessarily started, so `isLoadingContent`
/// can read `false` with nothing real loaded yet — the same second-layer gap
/// `WeekTabView` had, closed here the same way via `hasLoadedOnce`.
struct ShoppingListTabViewTests {
    @Test func showsLoadingWhileHouseholdOrShoppingListStoreIsLoading() {
        #expect(CoreLoadingGate.shouldShowLoadingPanel(
            isLoadingHouseholds: true,
            isLoadingContent: false,
            hasActiveHousehold: true,
            householdErrorMessage: nil,
            hasLoadedContentOnce: false,
            contentErrorMessage: nil
        ))
        #expect(CoreLoadingGate.shouldShowLoadingPanel(
            isLoadingHouseholds: false,
            isLoadingContent: true,
            hasActiveHousehold: true,
            householdErrorMessage: nil,
            hasLoadedContentOnce: false,
            contentErrorMessage: nil
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
            householdErrorMessage: nil,
            hasLoadedContentOnce: false,
            contentErrorMessage: nil
        ))
    }

    /// A genuine bootstrap failure must fall through to the `ErrorPanel`
    /// branch instead of spinning forever or showing the empty-state card.
    @Test func doesNotShowLoadingWhenHouseholdBootstrapFailed() {
        #expect(!CoreLoadingGate.shouldShowLoadingPanel(
            isLoadingHouseholds: false,
            isLoadingContent: false,
            hasActiveHousehold: false,
            householdErrorMessage: "Something went wrong",
            hasLoadedContentOnce: false,
            contentErrorMessage: nil
        ))
    }

    /// The second-layer gap: household is known, but `ShoppingListStore`'s
    /// own fetch `Task` hasn't run its first line yet — `isLoadingContent`
    /// reads `false` with nothing real to show. Must still read as loading,
    /// not fall through to the "No week plan at all" empty-state card.
    @Test func showsLoadingWhenHouseholdIsActiveButContentHasNeverLoaded() {
        #expect(CoreLoadingGate.shouldShowLoadingPanel(
            isLoadingHouseholds: false,
            isLoadingContent: false,
            hasActiveHousehold: true,
            householdErrorMessage: nil,
            hasLoadedContentOnce: false,
            contentErrorMessage: nil
        ))
    }

    /// A genuine content-load failure on the very first attempt must fall
    /// through to the `ErrorPanel` branch instead of spinning forever.
    @Test func doesNotShowLoadingWhenContentLoadFailedOnFirstAttempt() {
        #expect(!CoreLoadingGate.shouldShowLoadingPanel(
            isLoadingHouseholds: false,
            isLoadingContent: false,
            hasActiveHousehold: true,
            householdErrorMessage: nil,
            hasLoadedContentOnce: false,
            contentErrorMessage: "Something went wrong"
        ))
    }

    @Test func doesNotShowLoadingOnceHouseholdIsActiveAndContentHasLoaded() {
        #expect(!CoreLoadingGate.shouldShowLoadingPanel(
            isLoadingHouseholds: false,
            isLoadingContent: false,
            hasActiveHousehold: true,
            householdErrorMessage: nil,
            hasLoadedContentOnce: true,
            contentErrorMessage: nil
        ))
    }
}

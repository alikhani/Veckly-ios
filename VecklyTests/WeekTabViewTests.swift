import Foundation
import Testing
@testable import Veckly

/// Regression coverage for the 2026-08-03 cold-launch loading-flash bug, as
/// exercised through `WeekTabView`'s call site of the shared
/// `CoreLoadingGate.shouldShowLoadingPanel` (see its doc comment in
/// `StatePanels.swift` for the full mechanism). There are two layers to this
/// bug: `HouseholdStore.isLoading` only flips `true` inside the unstructured
/// `Task` `AppRefreshCoordinator.run` spawns for the household bootstrap, so
/// there's a real window on cold launch where `WeekTabView` is mounted with
/// `isLoading == false` on both stores and no active household yet — and,
/// one layer down, a second window once the household *is* known but
/// `WeekStore`'s own fetch `Task` hasn't started yet either. Without the gate
/// treating both gaps as "still loading," each window rendered real content
/// for a frame before the relevant `Task` started and flipped `isLoading`
/// back — the "loads, something appears briefly, then loads again" flash.
struct WeekTabViewTests {
    @Test func showsLoadingWhileHouseholdOrWeekStoreIsLoading() {
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
    /// loading, not as an empty-week/hero state.
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
    /// branch instead of spinning forever — `bootstrapAndLoadHouseholds`
    /// always ends with either an active household or `errorMessage` set,
    /// so this is the one legitimate case where "no active household" isn't
    /// "still loading."
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

    /// The second-layer gap (2026-08-03 follow-up): the household is already
    /// known, but `WeekStore`'s own fetch `Task` hasn't run its first line
    /// yet, so `isLoadingContent` is still `false` even though there's
    /// nothing real to show. Must still read as loading, not fall through to
    /// the empty-week/hero content.
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
    /// through to the `ErrorPanel` branch instead of spinning forever —
    /// `hasLoadedContentOnce` alone would stay `false` forever in this case.
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

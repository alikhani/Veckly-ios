import Testing
@testable import Veckly

/// Content restored from the disk cache stays on screen while the household
/// list loads, and a household-list failure doesn't replace it with an error.
struct CoreLoadingGateRestoredContentTests {
    @Test func restoredContentIsNotCoveredByTheLoadingPanelWhileHouseholdsLoad() {
        #expect(!CoreLoadingGate.shouldShowLoadingPanel(
            isLoadingHouseholds: true,
            isLoadingContent: false,
            hasActiveHousehold: true,
            householdErrorMessage: nil,
            hasLoadedContentOnce: true,
            contentErrorMessage: nil,
            hasRestoredContent: true
        ))
    }

    @Test func withoutRestoredContentHouseholdLoadingStillShowsTheLoadingPanel() {
        #expect(CoreLoadingGate.shouldShowLoadingPanel(
            isLoadingHouseholds: true,
            isLoadingContent: false,
            hasActiveHousehold: true,
            householdErrorMessage: nil,
            hasLoadedContentOnce: true,
            contentErrorMessage: nil
        ))
    }

    @Test func aHouseholdErrorDoesNotBlockRestoredContent() {
        #expect(CoreLoadingGate.blockingErrorMessage(contentError: nil, householdError: "household", hasRestoredContent: true) == nil)
    }

    @Test func aHouseholdErrorStillBlocksWhenNothingWasRestored() {
        #expect(CoreLoadingGate.blockingErrorMessage(contentError: nil, householdError: "household", hasRestoredContent: false) == "household")
    }

    @Test func aContentErrorIsAlwaysReported() {
        #expect(CoreLoadingGate.blockingErrorMessage(contentError: "content", householdError: "household", hasRestoredContent: true) == "content")
        #expect(CoreLoadingGate.blockingErrorMessage(contentError: "content", householdError: nil, hasRestoredContent: false) == "content")
    }
}

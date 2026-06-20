import Foundation
import Testing
@testable import Veckly

struct AppModelTests {
    private static let householdID = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"

    @Test func doesNotNeedOnboardingWhileDetailsAreStillLoading() {
        // The exact race: bootstrap finished (so the household is active) but
        // loadHouseholdDetails() hasn't resolved yet, so there's no profile to check.
        let result = AppModel.needsOnboarding(
            isSignedIn: true,
            isLoadingHouseholds: false,
            isLoadingDetails: true,
            activeHouseholdID: Self.householdID,
            detailsHouseholdID: nil,
            hasProfile: false
        )
        #expect(result == false)
    }

    @Test func doesNotNeedOnboardingBeforeDetailsHaveEverBeenFetchedForActiveHousehold() {
        // detailsHouseholdID hasn't caught up to activeHouseholdID yet, even though
        // isLoadingDetails has already flipped back to false (e.g. between awaits).
        let result = AppModel.needsOnboarding(
            isSignedIn: true,
            isLoadingHouseholds: false,
            isLoadingDetails: false,
            activeHouseholdID: Self.householdID,
            detailsHouseholdID: nil,
            hasProfile: false
        )
        #expect(result == false)
    }

    @Test func needsOnboardingOnceDetailsHaveLoadedAndThereIsNoProfile() {
        let result = AppModel.needsOnboarding(
            isSignedIn: true,
            isLoadingHouseholds: false,
            isLoadingDetails: false,
            activeHouseholdID: Self.householdID,
            detailsHouseholdID: Self.householdID,
            hasProfile: false
        )
        #expect(result == true)
    }

    @Test func doesNotNeedOnboardingOnceProfileExists() {
        let result = AppModel.needsOnboarding(
            isSignedIn: true,
            isLoadingHouseholds: false,
            isLoadingDetails: false,
            activeHouseholdID: Self.householdID,
            detailsHouseholdID: Self.householdID,
            hasProfile: true
        )
        #expect(result == false)
    }

    @Test func doesNotNeedOnboardingWhenSignedOut() {
        let result = AppModel.needsOnboarding(
            isSignedIn: false,
            isLoadingHouseholds: false,
            isLoadingDetails: false,
            activeHouseholdID: Self.householdID,
            detailsHouseholdID: Self.householdID,
            hasProfile: false
        )
        #expect(result == false)
    }
}

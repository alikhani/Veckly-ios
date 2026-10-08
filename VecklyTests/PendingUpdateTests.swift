import Testing
@testable import Veckly

/// The rule behind the "updates available" banner, one test per row of the
/// behavior table.
struct PendingUpdateTests {
    @Test func noCacheShownAppliesTheResponseDirectly() {
        #expect(PendingUpdate<Int>.decide(displayed: nil, fetched: 1, origin: .background) == .applyNow)
    }

    @Test func anEqualResponseDoesNothing() {
        #expect(PendingUpdate<Int>.decide(displayed: 1, fetched: 1, origin: .background) == .ignore)
    }

    @Test func aDifferingResponseIsDeferredBehindTheBanner() {
        #expect(PendingUpdate<Int>.decide(displayed: 1, fetched: 2, origin: .background) == .deferBehindBanner)
    }

    @Test func aUserInitiatedLoadAlwaysAppliesDirectly() {
        #expect(PendingUpdate<Int>.decide(displayed: 1, fetched: 2, origin: .userInitiated) == .applyNow)
        #expect(PendingUpdate<Int>.decide(displayed: 1, fetched: 1, origin: .userInitiated) == .applyNow)
        #expect(PendingUpdate<Int>.decide(displayed: nil, fetched: 1, origin: .userInitiated) == .applyNow)
    }
}

struct RefreshTriggerLoadOriginTests {
    @Test func onlyAnExplicitPullAppliesDirectly() {
        #expect(AppRefreshCoordinator.Trigger.pullToRefresh.loadOrigin == .userInitiated)
        #expect(AppRefreshCoordinator.Trigger.coldLaunch.loadOrigin == .background)
        #expect(AppRefreshCoordinator.Trigger.sceneActive.loadOrigin == .background)
        #expect(AppRefreshCoordinator.Trigger.householdChanged.loadOrigin == .background)
    }
}

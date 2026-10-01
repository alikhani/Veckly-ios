import Foundation
import Testing
@testable import Veckly

struct WidgetSnapshotStoreTests {
    @Test func snapshotBecomesStaleAfterTwelveHours() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let snapshot = WidgetSnapshot(updatedAt: now, meals: [], shoppingRemainingCount: 0)

        #expect(!snapshot.isStale(at: now.addingTimeInterval(12 * 60 * 60)))
        #expect(snapshot.isStale(at: now.addingTimeInterval(12 * 60 * 60 + 1)))
    }

    @Test func parsesMealDeepLink() {
        let link = AppDeepLink(url: URL(string: "veckly://meal?date=2026-10-01&recipe=recipe-1")!)

        #expect(link == .meal(date: "2026-10-01", recipeID: "recipe-1"))
    }

    @Test func parsesShoppingDeepLinkWithoutExposingItems() {
        #expect(AppDeepLink(url: URL(string: "veckly://shopping")!) == .shopping)
    }

    @Test func rejectsInvalidMealDateAndForeignScheme() {
        #expect(AppDeepLink(url: URL(string: "veckly://meal?date=not-a-date")!) == nil)
        #expect(AppDeepLink(url: URL(string: "https://example.com/shopping")!) == nil)
    }
}

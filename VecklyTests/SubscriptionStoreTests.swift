import Foundation
import StoreKit
import StoreKitTest
import Testing
@testable import Veckly

@Suite(.serialized)
struct SubscriptionStoreTests {
    private struct StoreKitConfiguration: Decodable {
        struct Group: Decodable {
            struct Subscription: Decodable {
                let displayPrice: String
                let productID: String
                let recurringSubscriptionPeriod: String
                let type: String
            }

            let subscriptions: [Subscription]
        }

        let subscriptionGroups: [Group]
    }

    @Test func premiumProductIdentifiersStayStable() {
        #expect(PremiumProductID.all == [
            "com.nimaalikhani.Veckly.premium.monthly",
            "com.nimaalikhani.Veckly.premium.yearly",
        ])
    }

    @Test func createsAppAccountTokenFromSupabaseUserID() {
        let userID = "11111111-1111-1111-1111-111111111111"
        #expect(SubscriptionStore.appAccountToken(userID: userID)?.uuidString.lowercased() == userID)
    }

    @Test func rejectsMissingOrMalformedAppAccountToken() {
        #expect(SubscriptionStore.appAccountToken(userID: nil) == nil)
        #expect(SubscriptionStore.appAccountToken(userID: "not-a-uuid") == nil)
    }

    @Test func localCatalogDefinesTheLockedProductsAndPrices() throws {
        let configurationURL = try #require(Bundle.main.url(forResource: "Veckly", withExtension: "storekit"))
        let configuration = try JSONDecoder().decode(
            StoreKitConfiguration.self,
            from: Data(contentsOf: configurationURL)
        )
        let subscriptions = configuration.subscriptionGroups.flatMap(\.subscriptions)

        #expect(Dictionary(uniqueKeysWithValues: subscriptions.map { ($0.productID, $0.displayPrice) }) == [
            PremiumProductID.monthly.rawValue: "69",
            PremiumProductID.yearly.rawValue: "549",
        ])
        #expect(Set(subscriptions.map(\.recurringSubscriptionPeriod)) == ["P1M", "P1Y"])
        #expect(Set(subscriptions.map(\.type)) == ["RecurringSubscription"])
    }

    // Xcode 26.6 (17F113) currently fails to sync StoreKit configurations to
    // storekitd when tests run through xcodebuild, producing an empty product
    // list and `.notEntitled`. Keep the real StoreKit chain ready to re-enable
    // when Apple's CLI regression is fixed; run it from Xcode's IDE meanwhile.
    @Test(.disabled("Xcode 26.6 xcodebuild StoreKitTest configuration-sync regression")) @MainActor
    func localStoreKitCatalogLoadsAndProducesPremiumEntitlement() async throws {
        let configurationURL = try #require(Bundle.main.url(forResource: "Veckly", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: configurationURL)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        defer { session.clearTransactions() }

        let products = try await Product.products(for: PremiumProductID.all)
        #expect(Set(products.map(\.id)) == PremiumProductID.all)

        _ = try await session.buyProduct(identifier: PremiumProductID.yearly.rawValue)
        let store = SubscriptionStore()
        await store.refreshEntitlements()

        #expect(store.hasActivePremiumSubscription)
        #expect(store.activeProductIDs == [PremiumProductID.yearly.rawValue])
    }
}

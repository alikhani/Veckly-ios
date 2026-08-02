import Foundation
import Observation
import StoreKit

enum PremiumProductID: String, CaseIterable, Sendable {
    case monthly = "com.nimaalikhani.Veckly.premium.monthly"
    case yearly = "com.nimaalikhani.Veckly.premium.yearly"

    static let all = Set(allCases.map(\.rawValue))

    fileprivate var sortOrder: Int {
        switch self {
        case .yearly: 0
        case .monthly: 1
        }
    }
}

enum SubscriptionPurchaseOutcome: Equatable, Sendable {
    case purchased
    case pending
    case cancelled
}

enum SubscriptionStoreFailure: Error, Equatable, Sendable {
    case verificationFailed
    case unknownProduct
}

/// StoreKit is an immediate, device-local view of Premium. The backend remains
/// authoritative for household access and will ingest the verified transaction
/// in the next slice; no product gate reads this store directly yet.
@MainActor
@Observable
final class SubscriptionStore {
    private(set) var products: [Product] = []
    private(set) var activeProductIDs: Set<String> = []
    private(set) var isLoadingProducts = false
    private(set) var isPurchasing = false
    private(set) var lastError: Error?

    @ObservationIgnored private var transactionUpdatesTask: Task<Void, Never>?

    var hasActivePremiumSubscription: Bool {
        !activeProductIDs.isDisjoint(with: PremiumProductID.all)
    }

    init() {
        transactionUpdatesTask = Task { [weak self] in
            await self?.observeTransactionUpdates()
        }
    }

    deinit {
        transactionUpdatesTask?.cancel()
    }

    func prepare() async {
        async let loadProducts: Void = loadProducts()
        async let refreshEntitlements: Void = refreshEntitlements()
        _ = await (loadProducts, refreshEntitlements)
    }

    func loadProducts() async {
        guard !isLoadingProducts else { return }
        isLoadingProducts = true
        lastError = nil
        defer { isLoadingProducts = false }

        do {
            let loadedProducts = try await Product.products(for: PremiumProductID.all)
            products = loadedProducts.sorted { lhs, rhs in
                Self.sortOrder(for: lhs.id) < Self.sortOrder(for: rhs.id)
            }
        } catch {
            lastError = error
        }
    }

    func purchase(_ product: Product, userID: String?) async throws -> SubscriptionPurchaseOutcome {
        guard PremiumProductID(rawValue: product.id) != nil else {
            throw SubscriptionStoreFailure.unknownProduct
        }

        isPurchasing = true
        lastError = nil
        defer { isPurchasing = false }

        do {
            let options = Self.appAccountToken(userID: userID)
                .map { Set([Product.PurchaseOption.appAccountToken($0)]) } ?? []
            let result = try await product.purchase(options: options)

            switch result {
            case .success(let verification):
                let transaction = try Self.verified(verification)
                await transaction.finish()
                await refreshEntitlements()
                return .purchased
            case .pending:
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                return .pending
            }
        } catch {
            lastError = error
            throw error
        }
    }

    func restorePurchases() async throws {
        lastError = nil
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            lastError = error
            throw error
        }
    }

    func refreshEntitlements() async {
        var currentProductIDs: Set<String> = []

        for await verification in Transaction.currentEntitlements {
            do {
                let transaction = try Self.verified(verification)
                if PremiumProductID(rawValue: transaction.productID) != nil {
                    currentProductIDs.insert(transaction.productID)
                }
            } catch {
                lastError = error
            }
        }

        activeProductIDs = currentProductIDs
    }

    nonisolated static func appAccountToken(userID: String?) -> UUID? {
        guard let userID else { return nil }
        return UUID(uuidString: userID)
    }

    private func observeTransactionUpdates() async {
        for await verification in Transaction.updates {
            guard !Task.isCancelled else { return }

            do {
                let transaction = try Self.verified(verification)
                await transaction.finish()
                await refreshEntitlements()
            } catch {
                lastError = error
            }
        }
    }

    nonisolated private static func verified<T>(_ verification: VerificationResult<T>) throws -> T {
        switch verification {
        case .verified(let value):
            return value
        case .unverified:
            throw SubscriptionStoreFailure.verificationFailed
        }
    }

    nonisolated private static func sortOrder(for productID: String) -> Int {
        PremiumProductID(rawValue: productID)?.sortOrder ?? .max
    }
}

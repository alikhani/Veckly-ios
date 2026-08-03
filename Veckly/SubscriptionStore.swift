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
    case missingPurchaseContext
}

protocol SubscriptionTransactionSubmitting {
    func submitAppStoreTransaction(householdID: String, signedTransaction: String) async throws
}

extension VecklyAPIClient: SubscriptionTransactionSubmitting {}

/// StoreKit is an immediate, device-local view of Premium. Verified sandbox
/// transactions are submitted to the backend before they are finished, while
/// the backend remains authoritative for household access. No product gate
/// reads this store directly yet.
@MainActor
@Observable
final class SubscriptionStore {
    private(set) var products: [Product] = []
    private(set) var activeProductIDs: Set<String> = []
    private(set) var isLoadingProducts = false
    private(set) var isPurchasing = false
    private(set) var lastError: Error?

    @ObservationIgnored private var transactionUpdatesTask: Task<Void, Never>?
    @ObservationIgnored private let transactionSubmitter: (any SubscriptionTransactionSubmitting)?
    @ObservationIgnored private let currentUserID: () -> String?
    @ObservationIgnored private let currentHouseholdID: () -> String?
    @ObservationIgnored private var submittedTransactionIDs: Set<UInt64> = []

    var hasActivePremiumSubscription: Bool {
        !activeProductIDs.isDisjoint(with: PremiumProductID.all)
    }

    init(
        transactionSubmitter: (any SubscriptionTransactionSubmitting)? = nil,
        currentUserID: @escaping () -> String? = { nil },
        currentHouseholdID: @escaping () -> String? = { nil }
    ) {
        self.transactionSubmitter = transactionSubmitter
        self.currentUserID = currentUserID
        self.currentHouseholdID = currentHouseholdID
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

    func purchase(_ product: Product, userID: String?, householdID: String?) async throws -> SubscriptionPurchaseOutcome {
        guard PremiumProductID(rawValue: product.id) != nil else {
            throw SubscriptionStoreFailure.unknownProduct
        }
        guard let appAccountToken = Self.appAccountToken(userID: userID),
              let householdID, !householdID.isEmpty else {
            throw SubscriptionStoreFailure.missingPurchaseContext
        }

        isPurchasing = true
        lastError = nil
        defer { isPurchasing = false }

        do {
            let options = Set([Product.PurchaseOption.appAccountToken(appAccountToken)])
            let result = try await product.purchase(options: options)

            switch result {
            case .success(let verification):
                try await synchronize(verification, userID: userID, householdID: householdID)
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
                    try await synchronize(verification)
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
                try await synchronize(verification)
                await refreshEntitlements()
            } catch {
                lastError = error
            }
        }
    }

    private func synchronize(
        _ verification: VerificationResult<Transaction>,
        userID: String? = nil,
        householdID: String? = nil
    ) async throws {
        let transaction = try Self.verified(verification)
        guard PremiumProductID(rawValue: transaction.productID) != nil else {
            await transaction.finish()
            return
        }
        guard !submittedTransactionIDs.contains(transaction.id) else {
            await transaction.finish()
            return
        }

        if let transactionSubmitter {
            guard let ownerUserID = userID ?? currentUserID(),
                  Self.appAccountToken(userID: ownerUserID) != nil,
                  let sponsoredHouseholdID = householdID ?? currentHouseholdID() else {
                // Keep the transaction unfinished so Transaction.updates can
                // retry after session/household restoration completes.
                return
            }
            try await transactionSubmitter.submitAppStoreTransaction(
                householdID: sponsoredHouseholdID,
                signedTransaction: verification.jwsRepresentation
            )
        }

        submittedTransactionIDs.insert(transaction.id)
        await transaction.finish()
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

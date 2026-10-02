import Foundation
import Observation
import StoreKit

/// StoreKit 2: one non-consumable "SpoolDry Lifetime" product. No subscription.
/// Prices are always the localized StoreKit price (`Product.displayPrice`), never hard-coded.
@MainActor
@Observable
final class StoreManager {
    enum PurchaseState: Equatable {
        case idle
        case purchasing
        case pending
        case failed(String)
        case purchased
    }

    private(set) var product: Product?
    private(set) var hasLifetime = false
    private(set) var purchaseState: PurchaseState = .idle
    private(set) var isLoadingProduct = false
    private(set) var productLoadFailed = false

    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(result)
            }
        }
    }

    func start() async {
        await refreshEntitlements()
        await loadProduct()
    }

    func loadProduct() async {
        isLoadingProduct = true
        defer { isLoadingProduct = false }
        do {
            product = try await Product.products(for: [SharedConstants.lifetimeProductID]).first
            productLoadFailed = product == nil
        } catch {
            productLoadFailed = true
        }
    }

    /// Reads verified entitlements (works offline from the on-device StoreKit cache).
    func refreshEntitlements() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case let .verified(t) = result, t.productID == SharedConstants.lifetimeProductID, t.revocationDate == nil {
                owned = true
            }
        }
        hasLifetime = owned
        if owned { purchaseState = .purchased }
    }

    func purchase() async {
        guard let product else {
            await loadProduct()
            if self.product == nil {
                purchaseState = .failed(String(localized: "The App Store is not reachable right now. Please try again later."))
            }
            return
        }
        purchaseState = .purchasing
        do {
            let result = try await product.purchase()
            switch result {
            case let .success(verification):
                switch verification {
                case let .verified(transaction):
                    await transaction.finish()
                    hasLifetime = true
                    purchaseState = .purchased
                case .unverified:
                    purchaseState = .failed(String(localized: "The purchase could not be verified."))
                }
            case .pending:
                purchaseState = .pending
            case .userCancelled:
                purchaseState = .idle
            @unknown default:
                purchaseState = .idle
            }
        } catch {
            purchaseState = .failed(error.localizedDescription)
        }
    }

    /// Restore = sync with the App Store, then re-read entitlements.
    func restore() async {
        purchaseState = .purchasing
        do {
            try await AppStore.sync()
        } catch {
            purchaseState = .failed(error.localizedDescription)
        }
        await refreshEntitlements()
        if !hasLifetime, case .purchasing = purchaseState {
            purchaseState = .failed(String(localized: "No previous purchase was found for this Apple Account."))
        }
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case let .verified(t) = result else { return }
        if t.productID == SharedConstants.lifetimeProductID {
            await t.finish()
        }
        await refreshEntitlements()
    }
}

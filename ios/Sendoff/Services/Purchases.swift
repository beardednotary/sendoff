import Foundation
import Observation
import StoreKit

/// StoreKit 2. Per-Sendoff purchases are consumables that become credits in the store
/// (`entitlements` rows); premium papers are non-consumables read from StoreKit itself.
///
/// A consumable is recorded in our store *before* `finish()` is called, so a crash in between
/// replays the transaction on next launch and the credit is never lost (the store is idempotent
/// on the transaction id).
///
/// Local testing: the `Sendoff` scheme runs with `ios/Sendoff.storekit`, so purchases work in
/// the simulator with no App Store Connect setup.
@Observable @MainActor
final class PurchaseManager {
    private(set) var products: [ProductID: Product] = [:]
    /// Unconsumed Sendoff credits, oldest first.
    private(set) var credits: [Entitlement] = []
    private(set) var ownedThemes: Set<ThemeID> = []
    private(set) var loaded = false
    var lastError: String?

    private let store: any SendoffStore
    private var updates: Task<Void, Never>?

    init(store: any SendoffStore) {
        self.store = store
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self, case .verified(let t) = result else { continue }
                await self.handle(t)
            }
        }
    }

    // MARK: Catalog

    func load() async {
        do {
            let all = try await Product.products(for: ProductID.allCases.map(\.rawValue))
            products = Dictionary(uniqueKeysWithValues: all.compactMap { p in ProductID(rawValue: p.id).map { ($0, p) } })
        } catch {
            lastError = error.localizedDescription
        }
        await refreshOwnedThemes()
        await refreshCredits()
        loaded = true
    }

    func product(_ id: ProductID) -> Product? { products[id] }
    func price(_ id: ProductID) -> String? { products[id]?.displayPrice }
    func credit(for plan: Plan) -> Entitlement? { credits.first { $0.product?.plan == plan } }
    func owns(_ theme: ThemeID) -> Bool { !ThemeCatalog.theme(theme).premium || ownedThemes.contains(theme) }

    func refreshCredits() async {
        let all = (try? await store.entitlements()) ?? []
        credits = all.filter { $0.isAvailable && $0.product?.plan != nil }.sorted { $0.createdAt < $1.createdAt }
    }

    func refreshOwnedThemes() async {
        var owned: Set<ThemeID> = []
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.revocationDate == nil, let theme = ProductID(rawValue: t.productID)?.themeID {
                owned.insert(theme)
            }
        }
        ownedThemes = owned
    }

    // MARK: Buying

    enum Outcome { case completed, cancelled, pending }

    func buy(_ id: ProductID) async throws -> Outcome {
        guard let product = products[id] else { throw PurchaseError.unavailable }
        switch try await product.purchase() {
        case .success(let verification):
            let transaction = try verification.payloadValue
            await handle(transaction)
            return .completed
        case .userCancelled:
            return .cancelled
        case .pending:
            return .pending
        @unknown default:
            return .cancelled
        }
    }

    /// Raises a Sendoff to `plan`: spends a credit if there is one, otherwise buys one first.
    /// Returns nil when the person cancels.
    func upgrade(_ sendoff: Sendoff, to plan: Plan) async throws -> Sendoff? {
        if credit(for: plan) == nil {
            guard let productID = ProductID.credit(for: plan) else { throw PurchaseError.unavailable }
            switch try await buy(productID) {
            case .completed: break
            case .cancelled: return nil
            case .pending: throw PurchaseError.pending
            }
        }
        guard let credit = credit(for: plan) else { throw PurchaseError.noCredit }
        let updated = try await store.redeem(credit.id, for: sendoff.id)
        await refreshCredits()
        return updated
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshOwnedThemes()
        await refreshCredits()
    }

    // MARK: Transactions

    private func handle(_ t: Transaction) async {
        guard let id = ProductID(rawValue: t.productID) else { await t.finish(); return }
        if t.revocationDate != nil {
            // Refunded. Credits already spent stay spent; unspent ones are reconciled server-side later.
            await t.finish()
            return
        }
        if id.isConsumable {
            do {
                try await store.recordPurchase(id, transactionID: String(t.id))
            } catch {
                // Leave unfinished; StoreKit delivers it again on next launch.
                lastError = error.localizedDescription
                return
            }
            await refreshCredits()
        } else if let theme = id.themeID {
            ownedThemes.insert(theme)
        }
        await t.finish()
    }
}

enum PurchaseError: LocalizedError {
    case unavailable, pending, noCredit

    var errorDescription: String? {
        switch self {
        case .unavailable: "The App Store isn't available right now. Try again in a moment."
        case .pending: "Your purchase needs approval before it goes through. Come back once it's confirmed."
        case .noCredit: "That credit has already been used."
        }
    }
}

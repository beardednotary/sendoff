import SwiftUI

@main
struct SendoffApp: App {
    @State private var router = AppRouter()
    @State private var store: any SendoffStore
    @State private var purchases: PurchaseManager

    init() {
        let store: any SendoffStore = SupabaseStore.fromInfoPlist() ?? MockStore()
        _store = State(initialValue: store)
        _purchases = State(initialValue: PurchaseManager(store: store))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .environment(purchases)
                .environment(\.store, store)
                .task { await purchases.load() }
                .onOpenURL { router.handle(url: $0) }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { router.handle(url: url) }
                }
        }
    }
}

// MARK: - Root

struct RootView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        HomeView()
            .appTheme()
            .sheet(item: Binding(get: { router.pending.flatMap { $0.isReveal ? nil : $0 } }, set: { router.pending = $0 })) { dest in
                if case .contribute(let slug) = dest { ContributeFlow(slug: slug) }
            }
            .fullScreenCover(item: Binding(get: { router.pending.flatMap { $0.isReveal ? $0 : nil } }, set: { router.pending = $0 })) { dest in
                if case .reveal(let slug) = dest { RevealLoader(slug: slug) }
            }
    }
}

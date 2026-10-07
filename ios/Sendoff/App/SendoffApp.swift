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
            .sheet(item: Binding(get: { router.pending }, set: { router.pending = $0 })) { dest in
                switch dest {
                case .contribute(let slug): ContributeFlow(slug: slug)
                case .reveal(let slug): RevealLoader(slug: slug)
                }
            }
    }
}

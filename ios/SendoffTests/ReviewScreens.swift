import StoreKitTest
import SwiftUI
import XCTest
@testable import Sendoff

/// The screens App Review asks to see for each in-app purchase: the paywall with real StoreKit
/// products from `Sendoff.storekit`, saved as PNGs at the simulator's screen size. Skipped
/// unless a folder is given:
///   TEST_RUNNER_REVIEW_SCREENS_DIR=/path xcodebuild test ... -only-testing:SendoffTests/ReviewScreens
@MainActor
final class ReviewScreens: XCTestCase {
    func testPaywallScreens() async throws {
        guard let dir = ProcessInfo.processInfo.environment["REVIEW_SCREENS_DIR"] else { throw XCTSkip("REVIEW_SCREENS_DIR not set") }
        let session = try SKTestSession(configurationFileNamed: "Sendoff")
        session.disableDialogs = true
        session.clearTransactions()
        let store = MockStore()
        let purchases = PurchaseManager(store: store)
        await purchases.load()
        XCTAssertEqual(purchases.price(.single), "$8.99", "StoreKit test products loaded")

        // The top shows Sendoff and Plus; the bottom shows a look on its own and the packs.
        try await capture(.letterpress, scrolledToEnd: false, purchases: purchases, store: store, to: dir, as: "plans")
        try await capture(.letterpress, scrolledToEnd: true, purchases: purchases, store: store, to: dir, as: "packs")
        for (theme, name) in [(ThemeID.goldLeaf, "gold_leaf"), (.darkroom, "darkroom"), (.fieldDay, "field_day")] {
            try await capture(theme, scrolledToEnd: true, purchases: purchases, store: store, to: dir, as: name)
        }
    }

    private func capture(_ theme: ThemeID, scrolledToEnd: Bool, purchases: PurchaseManager, store: MockStore,
                         to dir: String, as name: String) async throws {
        var s = MockStore.sampleCollecting
        s.themeID = theme
        s.plan = .free
        let window = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.windows.first)
        window.rootViewController = UIHostingController(rootView:
            PaywallView(sendoff: s, entryCount: 7) { _ in }
                .environment(\.store, store)
                .environment(purchases)
                .appTheme())
        window.makeKeyAndVisible()
        try await Task.sleep(for: .seconds(2))
        if scrolledToEnd, let scroll = Self.firstScrollView(in: window) {
            let end = CGPoint(x: 0, y: max(0, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom))
            scroll.setContentOffset(end, animated: false)
            try await Task.sleep(for: .seconds(1))
        }
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try XCTUnwrap(image.pngData()).write(to: URL(fileURLWithPath: dir).appendingPathComponent("review-\(name).png"))
    }

    private static func firstScrollView(in view: UIView) -> UIScrollView? {
        if let s = view as? UIScrollView { return s }
        for sub in view.subviews { if let s = firstScrollView(in: sub) { return s } }
        return nil
    }
}

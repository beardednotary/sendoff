import XCTest
@testable import Sendoff

/// The payment rules the app and the database both enforce. Mirrors 0003_payments.sql.
final class PaymentsTests: XCTestCase {

    func testPlanLimitsMatchDatabase() {
        XCTAssertEqual(Plan.free.entryLimit, 10)
        XCTAssertEqual(Plan.single.entryLimit, 100)
        XCTAssertEqual(Plan.plus.entryLimit, 100_000)
        XCTAssertTrue(Plan.free < .single && Plan.single < .plus && Plan.plus < .org)
        XCTAssertTrue(Plan.free.showsFooter)
        XCTAssertFalse(Plan.single.showsFooter)
        XCTAssertTrue(Plan.plus.includesPremiumThemes)
    }

    func testProductsMapToPlansAndCredits() {
        XCTAssertEqual(ProductID.single.plan, .single)
        XCTAssertEqual(ProductID.pack5.plan, .single)
        XCTAssertEqual(ProductID.pack5.credits, 5)
        XCTAssertEqual(ProductID.pack10.credits, 10)
        XCTAssertEqual(ProductID.plus.plan, .plus)
        XCTAssertNil(ProductID.themeGoldLeaf.plan)
        XCTAssertEqual(ProductID.themeGoldLeaf.themeID, .goldLeaf)
        XCTAssertEqual(ProductID.theme(.fieldDay), .themeFieldDay)
        XCTAssertNil(ProductID.theme(.letterpress), "included papers are not for sale")
        XCTAssertEqual(ProductID.credit(for: .plus), .plus)
        XCTAssertNil(ProductID.credit(for: .free))
    }

    func testNewSendoffsStartFree() async throws {
        let store = MockStore()
        var d = SendoffDraft(); d.recipientName = "Test Person"
        let s = try await store.create(d)
        XCTAssertEqual(s.plan, .free)
        XCTAssertEqual(s.contributorLimit, Plan.free.entryLimit)
    }

    func testRecordingAPurchaseIsIdempotentAndPacksSplit() async throws {
        let store = MockStore()
        let first = try await store.recordPurchase(.pack5, transactionID: "tx-1")
        XCTAssertEqual(first.count, 5)
        XCTAssertTrue(first.allSatisfy { $0.product == .single })
        let again = try await store.recordPurchase(.pack5, transactionID: "tx-1")
        XCTAssertEqual(again.count, 5)
        let all = try await store.entitlements()
        XCTAssertEqual(all.count, 5, "replaying a transaction must not mint more credits")
    }

    func testRedeemRaisesPlanAndConsumesCredit() async throws {
        let store = MockStore()
        var d = SendoffDraft(); d.recipientName = "Test Person"
        let s = try await store.create(d)
        let credit = try await store.recordPurchase(.plus, transactionID: "tx-2").first!

        let upgraded = try await store.redeem(credit.id, for: s.id)
        XCTAssertEqual(upgraded.plan, .plus)
        XCTAssertEqual(upgraded.contributorLimit, Plan.plus.entryLimit)
        let spent = try await store.entitlements()
        XCTAssertEqual(spent.first?.consumedBy, s.id)

        do {
            _ = try await store.redeem(credit.id, for: s.id)
            XCTFail("a credit can be spent once")
        } catch StoreError.noCredit { } catch { XCTFail("wrong error: \(error)") }
    }

    func testRedeemNeverLowersAPlan() async throws {
        let store = MockStore()
        var d = SendoffDraft(); d.recipientName = "Test Person"
        let s = try await store.create(d)
        let plus = try await store.recordPurchase(.plus, transactionID: "tx-3").first!
        let single = try await store.recordPurchase(.single, transactionID: "tx-4").first!
        _ = try await store.redeem(plus.id, for: s.id)
        let after = try await store.redeem(single.id, for: s.id)
        XCTAssertEqual(after.plan, .plus)
    }

    func testFreeSendoffStopsAtItsLimit() async throws {
        let store = MockStore()
        var d = SendoffDraft(); d.recipientName = "Test Person"
        let s = try await store.create(d)
        for i in 0..<Plan.free.entryLimit {
            var cd = ContributionDraft(); cd.authorName = "Person \(i)"; cd.body = "Hi"
            _ = try await store.submit(cd, to: s.id)
        }
        var cd = ContributionDraft(); cd.authorName = "One more"; cd.body = "Hi"
        do {
            _ = try await store.submit(cd, to: s.id)
            XCTFail("the eleventh entry must be refused on Free")
        } catch StoreError.full { } catch { XCTFail("wrong error: \(error)") }

        let credit = try await store.recordPurchase(.single, transactionID: "tx-5").first!
        _ = try await store.redeem(credit.id, for: s.id)
        _ = try await store.submit(cd, to: s.id)
    }
}

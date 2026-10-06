import XCTest
@testable import Sendoff

final class SendoffThemeTests: XCTestCase {

    /// Every theme's body text must meet WCAG AA (4.5:1) on its paper.
    func testInkOnPaperMeetsAA() {
        for t in ThemeCatalog.all {
            let ratio = t.ink.contrast(with: t.paper)
            XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(t.name): ink on paper is \(String(format: "%.2f", ratio)):1")
        }
    }

    /// Muted ink is for captions; large-text AA (3:1) is the floor.
    func testMutedInkOnPaperMeetsLargeTextAA() {
        for t in ThemeCatalog.all {
            let ratio = t.mutedInk.contrast(with: t.paper)
            XCTAssertGreaterThanOrEqual(ratio, 3.0, "\(t.name): muted ink on paper is \(String(format: "%.2f", ratio)):1")
        }
    }

    /// Text on the seal (buttons) must be readable.
    func testLabelOnSealMeetsAA() {
        for t in ThemeCatalog.all {
            let label = t.seal.luminance > 0.5 ? t.ink : t.paper
            let ratio = label.contrast(with: t.seal)
            XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(t.name): label on seal is \(String(format: "%.2f", ratio)):1")
        }
    }

    func testThemesRoundTripThroughJSON() throws {
        for t in ThemeCatalog.all {
            let data = try JSONEncoder().encode(t)
            let back = try JSONDecoder().decode(SendoffTheme.self, from: data)
            XCTAssertEqual(back, t)
        }
    }

    func testHexParsing() {
        let c = HexColor("#FFFFFF")
        XCTAssertEqual(c.luminance, 1, accuracy: 0.001)
        XCTAssertEqual(HexColor("#000000").luminance, 0, accuracy: 0.001)
        XCTAssertEqual(HexColor("#FFFFFF").contrast(with: HexColor("#000000")), 21, accuracy: 0.01)
    }
}

final class ModelTests: XCTestCase {

    func testSlugAlphabetAvoidsAmbiguousCharacters() {
        for _ in 0..<200 {
            let s = Slug.make()
            XCTAssertEqual(s.count, 8)
            XCTAssertFalse(s.contains { "01lioO".contains($0) })
        }
    }

    func testRevealOrderPinnedFirstThenSortThenDate() {
        let sid = UUID()
        func c(pinned: Bool, order: Int?, daysAgo: Double) -> Contribution {
            Contribution(id: UUID(), sendoffID: sid, authorID: nil, authorName: "x", authorRelationship: nil, body: nil,
                         promptUsed: nil, status: .approved, sharedWithGroup: false, pinned: pinned, sortOrder: order,
                         media: [], createdAt: Date(timeIntervalSinceNow: -86400 * daysAgo))
        }
        let a = c(pinned: false, order: nil, daysAgo: 3)
        let b = c(pinned: true, order: nil, daysAgo: 1)
        let d = c(pinned: false, order: 0, daysAgo: 2)
        let sorted = [a, b, d].sorted(by: Contribution.revealOrder)
        XCTAssertEqual(sorted.map(\.id), [b.id, d.id, a.id])
    }

    func testMockStoreReviewModeStartsPending() async throws {
        let store = MockStore()
        var draft = SendoffDraft()
        draft.recipientName = "Test Person"
        draft.moderation = .review
        let s = try await store.create(draft)
        var cd = ContributionDraft()
        cd.authorName = "A"
        cd.body = "Hello"
        let c = try await store.submit(cd, to: s.id)
        XCTAssertEqual(c.status, .pending)
        let reveal = try await store.revealContributions(for: s.id)
        XCTAssertTrue(reveal.isEmpty, "pending entries must never reach the recipient")
    }

    func testMockStoreRejectsAfterSeal() async throws {
        let store = MockStore()
        var draft = SendoffDraft()
        draft.recipientName = "Test Person"
        let s = try await store.create(draft)
        try await store.setState(s.id, .sealed)
        var cd = ContributionDraft(); cd.authorName = "A"; cd.body = "Late"
        do {
            _ = try await store.submit(cd, to: s.id)
            XCTFail("should throw")
        } catch { }
    }

    func testOccasionPromptsExist() {
        for o in Occasion.allCases { XCTAssertGreaterThanOrEqual(o.prompts.count, 3, o.title) }
    }
}

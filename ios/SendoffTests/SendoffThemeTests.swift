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
            let ratio = t.onSealInk.contrast(with: t.seal)
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
        try await store.setState(s.id, .open)
        let reveal = try await store.revealContributions(slug: s.slug, key: "")
        XCTAssertTrue(reveal.isEmpty, "pending entries must never reach the recipient")
    }

    /// The recipient's link breaks the seal only when it is due, and entries arrive only after.
    func testMockStoreOpensOnlyWhenDue() async throws {
        let store = MockStore()
        var draft = SendoffDraft()
        draft.recipientName = "Test Person"
        draft.reveal = .onDate
        draft.opensAt = .now.addingTimeInterval(86_400)
        let s = try await store.create(draft)
        var cd = ContributionDraft(); cd.authorName = "A"; cd.body = "Hello"
        _ = try await store.submit(cd, to: s.id)

        let sealed = try await store.reveal(slug: s.slug, key: "")
        XCTAssertEqual(sealed.contributorCount, 1)
        let early = try await store.revealContributions(slug: s.slug, key: "")
        XCTAssertTrue(early.isEmpty, "nothing before it opens")
        do {
            _ = try await store.open(slug: s.slug, key: "")
            XCTFail("opened before it was due")
        } catch StoreError.sealed { }

        try await store.setState(s.id, .open)
        let opened = try await store.open(slug: s.slug, key: "")
        XCTAssertTrue(opened.isOpen)
        let entries = try await store.revealContributions(slug: s.slug, key: "")
        XCTAssertEqual(entries.count, 1)
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

    func testRecipientFirstNameKeepsTitles() {
        var s = MockStore.sampleSendoff
        s.recipientName = "Maria Reyes"
        XCTAssertEqual(s.recipientFirstName, "Maria")
        s.recipientName = "Mr. Patel"
        XCTAssertEqual(s.recipientFirstName, "Mr. Patel")
        s.recipientName = "Coach Rivera"
        XCTAssertEqual(s.recipientFirstName, "Coach Rivera")
        s.recipientName = "Cher"
        XCTAssertEqual(s.recipientFirstName, "Cher")
    }

    func testSealInitialSkipsTitles() {
        var s = MockStore.sampleSendoff
        s.recipientName = "Maria Reyes"
        XCTAssertEqual(s.recipientInitial, "M")
        s.recipientName = "Mr. Patel"
        XCTAssertEqual(s.recipientInitial, "P")
        s.recipientName = " ana"
        XCTAssertEqual(s.recipientInitial, "A")
    }

    /// The storage policies only recognise lowercase ids, and the cover must sit in its own folder.
    func testStoragePathsMatchTheDatabaseRules() throws {
        let id = try XCTUnwrap(UUID(uuidString: "ABCDEF01-2345-6789-ABCD-EF0123456789"))
        let uuid = "[0-9a-f-]{36}"
        let cover = StoragePath.cover(id)
        XCTAssertNotNil(cover.range(of: "^abcdef01-2345-6789-abcd-ef0123456789/cover/\(uuid)\\.jpg$", options: .regularExpression), cover)
        let media = StoragePath.media(id, id, id, ext: "m4a")
        XCTAssertNotNil(media.range(of: "^\(uuid)/\(uuid)/\(uuid)\\.m4a$", options: .regularExpression), media)
    }

    func testOccasionPromptsExist() {
        for o in Occasion.allCases { XCTAssertGreaterThanOrEqual(o.prompts.count, 3, o.title) }
    }

    func testFramerCropsWhatTheFrameShows() {
        // A 1000×2000 photo filling a 300×400 frame: 0.3 points per pixel, 600 points tall.
        let size = CGSize(width: 1000, height: 2000), frame = CGSize(width: 300, height: 400)
        XCTAssertEqual(PhotoFramer.cropRect(imageSize: size, frame: frame, zoom: 1, offset: .zero),
                       CGRect(x: 0, y: 333, width: 1000, height: 1334), "centred")
        XCTAssertEqual(PhotoFramer.cropRect(imageSize: size, frame: frame, zoom: 1, offset: CGSize(width: 0, height: 100)),
                       CGRect(x: 0, y: 0, width: 1000, height: 1334), "dragged down to the top edge")
        let zoomed = PhotoFramer.cropRect(imageSize: size, frame: frame, zoom: 2, offset: CGSize(width: 150, height: 0))
        XCTAssertEqual(zoomed, CGRect(x: 0, y: 666, width: 500, height: 668), "zoomed in and dragged to the left edge")
        XCTAssertEqual(zoomed.width / zoomed.height, 3 / 4, accuracy: 0.01, "always the frame's shape")
    }

    func testEveryPlusLookFallsBackToAnIncludedOne() {
        for t in ThemeCatalog.premium { XCTAssertFalse(ThemeCatalog.theme(t.id.freeAlternative).premium, t.name) }
        for t in ThemeCatalog.included { XCTAssertEqual(t.id.freeAlternative, t.id, t.name) }
    }

    @MainActor
    func testRecipientSeesAPlusLookOnlyOncePaidFor() {
        let purchases = PurchaseManager(store: MockStore())
        var s = MockStore.sampleSendoff
        s.themeID = .darkroom
        s.plan = .free
        XCTAssertFalse(purchases.covers(s))
        XCTAssertEqual(purchases.look(for: s), .midnightToast, "unpaid Darkroom shows as Evening")
        s.plan = .plus
        XCTAssertEqual(purchases.look(for: s), .darkroom, "Plus covers every Plus look")
        s.themeID = .letterpress
        s.plan = .free
        XCTAssertTrue(purchases.covers(s), "included looks are always covered")
    }
}

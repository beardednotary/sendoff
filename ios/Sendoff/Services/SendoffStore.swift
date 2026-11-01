import Foundation
import Observation

// MARK: - Store protocol

/// Everything the UI needs from the backend. `MockStore` implements it fully so the app runs
/// without Supabase; `SupabaseStore` implements it against the real schema.
protocol SendoffStore: AnyObject, Observable {
    var currentUserID: UUID? { get }
    var currentUserName: String { get }

    // Organizer account. Contributors and recipients never sign in; organizers use Apple.
    /// True when an organizer is signed in, as opposed to no session or an anonymous one.
    var isSignedIn: Bool { get }
    /// Signs an organizer in with Apple's ID token. `name` is what Apple shares, on the first
    /// sign-in only. Returns false when the account still has no name people would recognise.
    func signInWithApple(idToken: String, nonce: String, name: String?) async throws -> Bool
    /// The name contributors see: "Only Jo and Dan will see this".
    func setDisplayName(_ name: String) async throws
    func signOut() async throws

    // Organizer
    func mySendoffs() async throws -> [Sendoff]
    func create(_ draft: SendoffDraft) async throws -> Sendoff
    func update(_ sendoff: Sendoff) async throws -> Sendoff
    /// Replaces the cover with a framed JPEG on disk, while the Sendoff has not opened.
    func setCover(_ jpeg: URL, for sendoffID: UUID) async throws
    /// Links a song from Apple Music, or removes it with nil, while the Sendoff has not opened.
    func setSong(_ song: LinkedSong?, for sendoffID: UUID) async throws
    func setState(_ id: UUID, _ state: SendoffState) async throws
    func contributions(for sendoffID: UUID) async throws -> [Contribution]
    func setStatus(_ contributionID: UUID, _ status: ContributionStatus) async throws
    func reorder(_ sendoffID: UUID, orderedIDs: [UUID]) async throws
    func delete(contribution id: UUID) async throws

    // Contributor (via shared link)
    func sendoff(slug: String) async throws -> Sendoff
    func myContribution(for sendoffID: UUID) async throws -> Contribution?
    func submit(_ draft: ContributionDraft, to sendoffID: UUID) async throws -> Contribution

    // Recipient, from their link: slug + recipient key, no account
    /// The Sendoff as the recipient may see it, sealed or open, with the cover signed.
    func reveal(slug: String, key: String) async throws -> Sendoff
    /// Breaks the seal. Returns the Sendoff once it is open; throws `.sealed` when it is not due.
    func open(slug: String, key: String) async throws -> Sendoff
    /// The approved entries with playable media. Empty until the Sendoff is open.
    func revealContributions(slug: String, key: String) async throws -> [Contribution]
    /// Apple's 30-second preview of the Sendoff's song, for a listener MusicKit can't play it for.
    /// Nil without a song, without Plus, or before MusicKit is set up on the server.
    func songPreview(slug: String, key: String) async -> URL?

    // Catalog
    func tracks() async throws -> [MusicTrack]

    // Payments
    func entitlements() async throws -> [Entitlement]
    /// Records a finished StoreKit purchase as credits. Idempotent on `transactionID`; a pack
    /// becomes several single credits.
    @discardableResult
    func recordPurchase(_ product: ProductID, transactionID: String) async throws -> [Entitlement]
    /// Applies a credit to a Sendoff: raises its plan and entry limit, marks the credit consumed.
    func redeem(_ entitlementID: UUID, for sendoffID: UUID) async throws -> Sendoff
}

struct SendoffDraft {
    var occasion: Occasion = .farewell
    var recipientName: String = ""
    var fromLine: String = ""
    var coverMessage: String = ""
    /// A photo of them for the cover, picked on device. Optional.
    var recipientPhoto: URL? = nil
    /// A song from Apple Music instead of a stock track. Plus.
    var song: LinkedSong? = nil
    var themeID: ThemeID = .letterpress
    var musicTrackID: String? = nil
    var reveal: RevealPolicy = .onDate
    var opensAt: Date = Calendar.current.date(byAdding: .day, value: 14, to: .now) ?? .now
    var closesAt: Date = Calendar.current.date(byAdding: .day, value: 13, to: .now) ?? .now
    var moderation: ModerationMode = .trust
    var goal: Int = 25

    var isValid: Bool { recipientName.trimmingCharacters(in: .whitespaces).count >= 2 }
}

struct ContributionDraft {
    var authorName: String = ""
    var authorRelationship: String = ""
    var body: String = ""
    var promptUsed: String? = nil
    var sharedWithGroup: Bool = false
    var media: [Media] = []

    var hasContent: Bool {
        !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !media.isEmpty
    }
    var isValid: Bool { hasContent && authorName.trimmingCharacters(in: .whitespaces).count >= 1 }
}

enum StoreError: LocalizedError {
    case notFound, notAllowed, closed, full, noCredit, sealed, network(String)

    var errorDescription: String? {
        switch self {
        case .notFound: "We couldn't find that Sendoff."
        case .notAllowed: "You don't have access to that."
        case .closed: "This Sendoff is no longer collecting."
        case .full: "This Sendoff is full. The organizer can make room."
        case .noCredit: "That credit has already been used."
        case .sealed: "It's sealed. Not yet."
        case .network(let s): s
        }
    }
}

// MARK: - Mock store

/// In-memory store seeded with a believable Sendoff. Drives previews, tests and the offline demo.
@Observable
final class MockStore: SendoffStore {
    private(set) var currentUserID: UUID? = MockStore.me
    private(set) var currentUserName = "Dan Okafor"
    var isSignedIn: Bool { currentUserID != nil }

    private(set) var sendoffs: [Sendoff]
    private(set) var contributionsByID: [UUID: [Contribution]]
    private var mine: [UUID: Contribution] = [:]
    private var grants: [Entitlement] = []

    static let me = UUID(uuidString: "00000000-0000-0000-0000-00000000AAAA")!

    init(seeded: Bool = true) {
        if seeded {
            let s = MockStore.sampleSendoff
            sendoffs = [s, MockStore.sampleSealed, MockStore.sampleCollecting]
            contributionsByID = [s.id: MockStore.sampleContributions(for: s.id)]
        } else {
            sendoffs = []
            contributionsByID = [:]
        }
    }

    func mySendoffs() async throws -> [Sendoff] {
        sendoffs.filter { $0.organizerID == currentUserID }.sorted { $0.createdAt > $1.createdAt }
    }

    // The demo starts signed in as Dan, so every screen is reachable without an Apple Account.
    func signInWithApple(idToken: String, nonce: String, name: String?) async throws -> Bool {
        currentUserID = MockStore.me
        if let name, !name.isEmpty { currentUserName = name }
        return !currentUserName.isEmpty
    }

    func setDisplayName(_ name: String) async throws { currentUserName = name }

    func signOut() async throws { currentUserID = nil }

    func create(_ d: SendoffDraft) async throws -> Sendoff {
        let s = Sendoff(
            id: UUID(), slug: Slug.make(), organizerID: MockStore.me, organizerName: currentUserName,
            occasion: d.occasion, recipientName: d.recipientName.trimmingCharacters(in: .whitespaces),
            recipientPhotoURL: d.recipientPhoto,
            fromLine: d.fromLine.isEmpty ? nil : d.fromLine,
            coverMessage: d.coverMessage.isEmpty ? nil : d.coverMessage,
            themeID: d.themeID, musicTrackID: d.musicTrackID ?? d.occasion.defaultTrack,
            state: .collecting, moderation: d.moderation, reveal: d.reveal,
            closesAt: d.closesAt, opensAt: d.reveal == .onDate ? d.opensAt : nil, openedAt: nil,
            plan: .free, contributorLimit: Plan.free.entryLimit, createdAt: .now, contributorGoal: d.goal,
            contributeToken: Slug.token(bytes: 16), recipientKey: Slug.token(bytes: 24), song: d.song
        )
        sendoffs.insert(s, at: 0)
        contributionsByID[s.id] = []
        return s
    }

    func setCover(_ jpeg: URL, for sendoffID: UUID) async throws {
        guard let i = sendoffs.firstIndex(where: { $0.id == sendoffID }), sendoffs[i].state != .open else { throw StoreError.notAllowed }
        sendoffs[i].recipientPhotoURL = jpeg
    }

    func setSong(_ song: LinkedSong?, for sendoffID: UUID) async throws {
        guard let i = sendoffs.firstIndex(where: { $0.id == sendoffID }), sendoffs[i].state != .open else { throw StoreError.notAllowed }
        sendoffs[i].song = song
    }

    func songPreview(slug: String, key: String) async -> URL? { nil }

    func update(_ sendoff: Sendoff) async throws -> Sendoff {
        guard let i = sendoffs.firstIndex(where: { $0.id == sendoff.id }) else { throw StoreError.notFound }
        sendoffs[i] = sendoff
        return sendoff
    }

    func setState(_ id: UUID, _ state: SendoffState) async throws {
        guard let i = sendoffs.firstIndex(where: { $0.id == id }) else { throw StoreError.notFound }
        sendoffs[i].state = state
        if state == .open { sendoffs[i].openedAt = .now }
    }

    func contributions(for sendoffID: UUID) async throws -> [Contribution] {
        (contributionsByID[sendoffID] ?? []).sorted(by: Contribution.revealOrder)
    }

    func setStatus(_ contributionID: UUID, _ status: ContributionStatus) async throws {
        for (k, list) in contributionsByID {
            if let i = list.firstIndex(where: { $0.id == contributionID }) {
                contributionsByID[k]?[i].status = status
            }
        }
    }

    func reorder(_ sendoffID: UUID, orderedIDs: [UUID]) async throws {
        guard var list = contributionsByID[sendoffID] else { return }
        for (order, id) in orderedIDs.enumerated() {
            if let i = list.firstIndex(where: { $0.id == id }) { list[i].sortOrder = order }
        }
        contributionsByID[sendoffID] = list
    }

    func delete(contribution id: UUID) async throws {
        for k in contributionsByID.keys { contributionsByID[k]?.removeAll { $0.id == id } }
    }

    func sendoff(slug: String) async throws -> Sendoff {
        guard let s = sendoffs.first(where: { $0.slug == slug }) else { throw StoreError.notFound }
        return s
    }

    func myContribution(for sendoffID: UUID) async throws -> Contribution? { mine[sendoffID] }

    func submit(_ d: ContributionDraft, to sendoffID: UUID) async throws -> Contribution {
        guard let s = sendoffs.first(where: { $0.id == sendoffID }) else { throw StoreError.notFound }
        guard s.isCollecting else { throw StoreError.closed }
        let live = (contributionsByID[sendoffID] ?? []).filter { $0.status != .hidden }.count
        guard live < s.contributorLimit else { throw StoreError.full }
        let c = Contribution(
            id: UUID(), sendoffID: sendoffID, authorID: UUID(),
            authorName: d.authorName.trimmingCharacters(in: .whitespaces),
            authorRelationship: d.authorRelationship.isEmpty ? nil : d.authorRelationship,
            body: d.body, promptUsed: d.promptUsed,
            status: s.moderation == .review ? .pending : .approved,
            sharedWithGroup: d.sharedWithGroup, pinned: false, sortOrder: nil,
            media: d.media, createdAt: .now
        )
        contributionsByID[sendoffID, default: []].append(c)
        mine[sendoffID] = c
        return c
    }

    // Any key opens a mock Sendoff, as on the web.
    func reveal(slug: String, key: String) async throws -> Sendoff {
        var s = try await sendoff(slug: slug)
        s.contributorCount = (contributionsByID[s.id] ?? []).filter { $0.status != .hidden }.count
        return s
    }

    func open(slug: String, key: String) async throws -> Sendoff {
        var s = try await reveal(slug: slug, key: key)
        let due = s.isOpen || (s.reveal == .onDate && (s.opensAt.map { $0 <= .now } ?? false))
        guard due else { throw StoreError.sealed }
        if !s.isOpen {
            try await setState(s.id, .open)
            s.state = .open
        }
        return s
    }

    func revealContributions(slug: String, key: String) async throws -> [Contribution] {
        let s = try await sendoff(slug: slug)
        guard s.isOpen else { return [] }
        return try await contributions(for: s.id).filter { $0.status == .approved }
    }

    func tracks() async throws -> [MusicTrack] { MockStore.sampleTracks }

    // MARK: Payments

    func entitlements() async throws -> [Entitlement] { grants }

    func recordPurchase(_ product: ProductID, transactionID: String) async throws -> [Entitlement] {
        let existing = grants.filter { $0.externalID?.hasPrefix(transactionID) == true }
        if !existing.isEmpty { return existing }
        guard let plan = product.plan, let creditProduct = ProductID.credit(for: plan) else { return [] }
        let new = (0..<product.credits).map { i in
            Entitlement(id: UUID(), productID: creditProduct.rawValue, source: "storekit",
                        externalID: product.credits == 1 ? transactionID : "\(transactionID)#\(i)",
                        consumedBy: nil, expiresAt: nil, createdAt: .now)
        }
        grants.append(contentsOf: new)
        return new
    }

    func redeem(_ entitlementID: UUID, for sendoffID: UUID) async throws -> Sendoff {
        guard let gi = grants.firstIndex(where: { $0.id == entitlementID }), grants[gi].isAvailable else { throw StoreError.noCredit }
        guard let si = sendoffs.firstIndex(where: { $0.id == sendoffID }), sendoffs[si].organizerID == currentUserID else { throw StoreError.notFound }
        guard let plan = grants[gi].product?.plan else { throw StoreError.noCredit }
        grants[gi].consumedBy = sendoffID
        if plan > sendoffs[si].plan {
            sendoffs[si].plan = plan
            sendoffs[si].contributorLimit = plan.entryLimit
        }
        return sendoffs[si]
    }
}

extension Contribution {
    static func revealOrder(_ a: Contribution, _ b: Contribution) -> Bool {
        if a.pinned != b.pinned { return a.pinned }
        switch (a.sortOrder, b.sortOrder) {
        case let (x?, y?): return x < y
        case (_?, nil): return true
        case (nil, _?): return false
        default: return a.createdAt < b.createdAt
        }
    }
}

enum Slug {
    /// Short, unambiguous, URL safe. 8 chars from a 31-symbol alphabet.
    static func make() -> String {
        let alphabet = Array("abcdefghjkmnpqrstuvwxyz23456789")
        return String((0..<8).map { _ in alphabet.randomElement()! })
    }

    /// Hex token, same shape as the database default (`encode(gen_random_bytes(n), 'hex')`).
    static func token(bytes: Int) -> String {
        (0..<bytes).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }
}

// MARK: - Sample data

extension MockStore {
    /// Demo photography from Unsplash (free licence), standing in for what people upload.
    static func photo(_ id: String) -> URL? {
        URL(string: "https://images.unsplash.com/\(id)?w=1200&q=80&auto=format&fit=crop")
    }

    static let sampleSendoff: Sendoff = Sendoff(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        slug: "maria-r", organizerID: me, organizerName: "Dan Okafor",
        occasion: .retirement, recipientName: "Maria Reyes", recipientPhotoURL: MockStore.photo("photo-1695556746253-ab635cedac50"),
        fromLine: "From the whole fourth floor", coverMessage: "Thirty-one years. We tried to fit it in here.",
        themeID: .midnightToast, musicTrackID: "warm_piano",
        state: .open, moderation: .trust, reveal: .onDate,
        closesAt: Date(timeIntervalSinceNow: -86400 * 2), opensAt: Date(timeIntervalSinceNow: -3600),
        openedAt: nil, plan: .plus, contributorLimit: 1000,
        createdAt: Date(timeIntervalSinceNow: -86400 * 20), contributorGoal: 40,
        contributeToken: "demo", recipientKey: "demo"
    )

    static let sampleSealed: Sendoff = Sendoff(
        id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        slug: "mr-patel", organizerID: me, organizerName: "Dan Okafor",
        occasion: .teacher, recipientName: "Mr. Patel", recipientPhotoURL: MockStore.photo("photo-1578593139939-cccb1e98698c"),
        fromLine: "Room 14", coverMessage: nil,
        themeID: .chalk, musicTrackID: "reflective_guitar",
        state: .sealed, moderation: .review, reveal: .onDate,
        closesAt: Date(timeIntervalSinceNow: 86400 * 3), opensAt: Date(timeIntervalSinceNow: 86400 * 5),
        openedAt: nil, plan: .single, contributorLimit: 100,
        createdAt: Date(timeIntervalSinceNow: -86400 * 6),
        contributeToken: "demo", recipientKey: "demo"
    )

    static let sampleCollecting: Sendoff = Sendoff(
        id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
        slug: "jo-moves", organizerID: me, organizerName: "Dan Okafor",
        occasion: .newJob, recipientName: "Jo Lindqvist", recipientPhotoURL: MockStore.photo("photo-1631885627929-0ea00ff4bf06"),
        fromLine: "Platform team", coverMessage: nil,
        themeID: .letterpress, musicTrackID: "bright_strings",
        state: .collecting, moderation: .trust, reveal: .manual,
        closesAt: Date(timeIntervalSinceNow: 86400 * 9), opensAt: nil,
        openedAt: nil, plan: .free, contributorLimit: Plan.free.entryLimit,
        createdAt: Date(timeIntervalSinceNow: -86400 * 1), contributorGoal: 12,
        contributeToken: "demo", recipientKey: "demo"
    )

    static func sampleContributions(for sendoffID: UUID) -> [Contribution] {
        func c(_ name: String, _ rel: String?, _ body: String?, media: [Media] = [], pinned: Bool = false, status: ContributionStatus = .approved, daysAgo: Double) -> Contribution {
            Contribution(id: UUID(), sendoffID: sendoffID, authorID: UUID(), authorName: name,
                         authorRelationship: rel, body: body, promptUsed: nil, status: status,
                         sharedWithGroup: false, pinned: pinned, sortOrder: nil, media: media,
                         createdAt: Date(timeIntervalSinceNow: -86400 * daysAgo))
        }
        return [
            c("Dan Okafor", "Your manager, somehow", "Maria. You hired me when I had no business being hired. You spent the first year quietly fixing what I broke and the next nine teaching me not to break it. Every good habit I have at work is one of yours.\n\nEnjoy the mornings.", pinned: true, daysAgo: 18),
            c("Priya N.", "Your 2019 intern", "You said \u{201C}the deadline is real, the panic is optional.\u{201D} I have it on a sticky note. Still.", daysAgo: 12),
            c("Tom Alvarez", "Facilities", nil,
              media: [Media(id: UUID(), kind: .voice, url: nil, posterURL: nil, durationSeconds: 48, transcript: "Hey Maria, it's Tom. I just wanted to say... you were the only one who learned my kids\u{2019} names.", width: nil, height: nil, localURL: nil)],
              daysAgo: 10),
            c("The Wednesday lunch crew", nil, "We are not going to survive Wednesdays.",
              media: [Media(id: UUID(), kind: .photo, url: MockStore.photo("photo-1670899460364-ebc917bac09a"), posterURL: nil, durationSeconds: nil, transcript: nil, width: 1200, height: 900, localURL: nil),
                      Media(id: UUID(), kind: .photo, url: MockStore.photo("photo-1554902748-feaf536fc594"), posterURL: nil, durationSeconds: nil, transcript: nil, width: 1200, height: 900, localURL: nil)],
              daysAgo: 7),
            c("Lena Fischer", "Finance", nil,
              media: [Media(id: UUID(), kind: .video, url: nil, posterURL: MockStore.photo("photo-1568992688065-536aad8a12f6"), durationSeconds: 41, transcript: nil, width: 1280, height: 720, localURL: nil)],
              daysAgo: 5),
            c("Sam", "The new guy", "I've been here six weeks. You still made time. That told me everything about this place.", daysAgo: 3),
        ]
    }

    static let sampleTracks: [MusicTrack] = [
        MusicTrack(id: "warm_piano", title: "Last Light", artist: "Stock", durationSeconds: 182, storagePath: "stock-music/warm_piano.m4a", appleMusicID: nil, premium: false, mood: "warm"),
        MusicTrack(id: "bright_strings", title: "Open Windows", artist: "Stock", durationSeconds: 164, storagePath: "stock-music/bright_strings.m4a", appleMusicID: nil, premium: false, mood: "bright"),
        MusicTrack(id: "reflective_guitar", title: "Long Hallway", artist: "Stock", durationSeconds: 201, storagePath: "stock-music/reflective_guitar.m4a", appleMusicID: nil, premium: false, mood: "reflective"),
        MusicTrack(id: "triumphant_brass", title: "Final Whistle", artist: "Stock", durationSeconds: 158, storagePath: "stock-music/triumphant_brass.m4a", appleMusicID: nil, premium: false, mood: "triumphant"),
    ]
}

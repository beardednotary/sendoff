import Foundation

// MARK: - Occasion

enum Occasion: String, Codable, CaseIterable, Identifiable {
    case retirement
    case newJob = "new_job"
    case graduation
    case teacher
    case seasonEnd = "season_end"
    case military
    case farewell

    var id: String { rawValue }

    var title: String {
        switch self {
        case .retirement: "Retirement"
        case .newJob: "New job"
        case .graduation: "Graduation"
        case .teacher: "Thank a teacher"
        case .seasonEnd: "End of season"
        case .military: "Military sendoff"
        case .farewell: "Leaving a team"
        }
    }

    /// Short line under the title on the occasion picker.
    var blurb: String {
        switch self {
        case .retirement: "For a career worth more than a cake in the break room."
        case .newJob: "They're moving on. Send them off properly."
        case .graduation: "For the one who made it."
        case .teacher: "End of the year. Say what the kids can't."
        case .seasonEnd: "For the coach who showed up every Saturday."
        case .military: "PCS, separation, retirement, change of command."
        case .farewell: "Relocating, a reorg, a sabbatical, or just goodbye."
        }
    }

    /// Prompts offered to contributors as chips to get past the blank page.
    var prompts: [String] {
        switch self {
        case .retirement:
            ["What did they teach you?", "A moment you'll never forget", "What the place will miss", "Advice for the first Monday off"]
        case .newJob:
            ["What the next team is lucky to get", "The thing you'll miss most", "A project you survived together", "One piece of advice"]
        case .graduation:
            ["Proudest moment", "Advice for what's next", "What you noticed about them", "Something to remember on a hard day"]
        case .teacher:
            ["Something they said that stuck", "A day that changed things", "What my kid says at dinner", "Thank you for..."]
        case .seasonEnd:
            ["Best game", "What you learned beyond the sport", "A practice you'll never forget", "Thank you, coach"]
        case .military:
            ["Best memory from the unit", "Something you taught us", "A story from the field", "What we'll miss", "Final words before you move on"]
        case .farewell:
            ["What you'll miss", "A story only you two know", "Something you never got to say", "What the next place is getting"]
        }
    }

    var defaultTheme: ThemeID {
        switch self {
        case .retirement: .midnightToast
        case .teacher, .graduation: .chalk
        case .seasonEnd: .chalk
        case .military: .midnightToast
        case .newJob, .farewell: .letterpress
        }
    }

    var defaultTrack: String {
        switch self {
        case .retirement: "warm_piano"
        case .graduation, .newJob: "bright_strings"
        case .teacher, .farewell: "reflective_guitar"
        case .seasonEnd, .military: "triumphant_brass"
        }
    }

    var symbol: String {
        switch self {
        case .retirement: "sun.horizon"
        case .newJob: "arrow.turn.up.right"
        case .graduation: "graduationcap"
        case .teacher: "book"
        case .seasonEnd: "sportscourt"
        case .military: "flag"
        case .farewell: "hand.wave"
        }
    }
}

// MARK: - Sendoff

enum SendoffState: String, Codable {
    case draft, collecting, sealed, open
}

enum ModerationMode: String, Codable, CaseIterable, Identifiable {
    case trust, review
    var id: String { rawValue }

    var title: String {
        switch self {
        case .trust: "Trust"
        case .review: "Review first"
        }
    }

    var detail: String {
        switch self {
        case .trust: "Everything goes in. You can remove anything later."
        case .review: "You approve each entry before the reveal."
        }
    }
}

enum RevealPolicy: String, Codable, CaseIterable, Identifiable {
    case onDate = "on_date"
    case manual
    var id: String { rawValue }

    var title: String {
        switch self {
        case .onDate: "Open on a date"
        case .manual: "Open when I say"
        }
    }
}

enum Plan: String, Codable, Comparable {
    case free, single, plus, org

    var title: String {
        switch self {
        case .free: "Free"
        case .single: "Sendoff"
        case .plus: "Sendoff Plus"
        case .org: "Organization"
        }
    }

    /// How many entries the envelope holds. Mirrors `plan_entry_limit()` in 0003_payments.sql.
    var entryLimit: Int {
        switch self {
        case .free: 10
        case .single: 100
        case .plus, .org: 100_000
        }
    }

    var includesPremiumThemes: Bool { self >= .plus }
    /// Free shows "Made with Sendoff" on the last page.
    var showsFooter: Bool { self == .free }

    private var rank: Int { Plan.order.firstIndex(of: self) ?? 0 }
    private static let order: [Plan] = [.free, .single, .plus, .org]
    static func < (a: Plan, b: Plan) -> Bool { a.rank < b.rank }
}

// MARK: - Payments

/// App Store product identifiers. Mirrors the StoreKit configuration in `ios/Sendoff.storekit`
/// and the `product_id` column of `entitlements`.
enum ProductID: String, CaseIterable, Identifiable {
    case single = "sendoff.single"          // consumable: one Sendoff
    case plus = "sendoff.plus"              // consumable: one Sendoff Plus
    case pack5 = "sendoff.pack5"            // consumable: five Sendoff credits
    case pack10 = "sendoff.pack10"          // consumable: ten Sendoff credits
    case themeGoldLeaf = "theme.gold_leaf"  // non-consumable
    case themeDarkroom = "theme.darkroom"
    case themeFieldDay = "theme.field_day"

    var id: String { rawValue }

    /// The plan a credit from this product unlocks. Nil for theme add-ons.
    var plan: Plan? {
        switch self {
        case .single, .pack5, .pack10: .single
        case .plus: .plus
        case .themeGoldLeaf, .themeDarkroom, .themeFieldDay: nil
        }
    }

    /// Credits one purchase yields. Each credit is one `entitlements` row.
    var credits: Int {
        switch self {
        case .pack5: 5
        case .pack10: 10
        case .single, .plus: 1
        case .themeGoldLeaf, .themeDarkroom, .themeFieldDay: 0
        }
    }

    var isConsumable: Bool { plan != nil }

    var themeID: ThemeID? {
        switch self {
        case .themeGoldLeaf: .goldLeaf
        case .themeDarkroom: .darkroom
        case .themeFieldDay: .fieldDay
        default: nil
        }
    }

    static func theme(_ id: ThemeID) -> ProductID? {
        allCases.first { $0.themeID == id }
    }

    static func credit(for plan: Plan) -> ProductID? {
        switch plan {
        case .single: .single
        case .plus: .plus
        case .free, .org: nil
        }
    }
}

/// Something the organizer has paid for. A Sendoff credit is consumed when applied to a Sendoff.
struct Entitlement: Identifiable, Codable, Hashable {
    var id: UUID
    var productID: String
    var source: String              // "storekit", "stripe", "grant"
    var externalID: String?         // StoreKit transaction id (packs: "{id}#{n}")
    var consumedBy: UUID?
    var expiresAt: Date?
    var createdAt: Date

    var product: ProductID? { ProductID(rawValue: productID) }
    var isAvailable: Bool { consumedBy == nil && (expiresAt.map { $0 > .now } ?? true) }
}

struct Sendoff: Identifiable, Codable, Hashable {
    var id: UUID
    var slug: String
    var organizerID: UUID
    var organizerName: String
    var occasion: Occasion
    var recipientName: String
    var recipientPhotoURL: URL?
    var fromLine: String?
    var coverMessage: String?
    var themeID: ThemeID
    var musicTrackID: String?
    var state: SendoffState
    var moderation: ModerationMode
    var reveal: RevealPolicy
    var closesAt: Date?
    var opensAt: Date?
    var openedAt: Date?
    var plan: Plan
    var contributorLimit: Int
    var createdAt: Date
    /// Organizer's own target, shown as progress on their dashboard. Not a cap.
    var contributorGoal: Int? = nil
    /// In the shared link as `?t=`. Only the organizer ever holds it; contributors receive it in the URL.
    var contributeToken: String? = nil
    /// In the recipient's link as `?k=`. Long and random so it cannot be derived from the slug.
    var recipientKey: String? = nil

    /// `https://{host}/s/{slug}?t={token}`: the link everyone who contributes receives.
    var shareURL: URL {
        var c = URLComponents(url: AppConfig.publicOrigin.appending(path: "s/\(slug)"), resolvingAgainstBaseURL: false)!
        if let contributeToken { c.queryItems = [URLQueryItem(name: "t", value: contributeToken)] }
        return c.url!
    }

    /// `https://{host}/s/{slug}/open?k={key}`: the recipient's link. Sealed until the reveal.
    var revealURL: URL {
        var c = URLComponents(url: AppConfig.publicOrigin.appending(path: "s/\(slug)/open"), resolvingAgainstBaseURL: false)!
        if let recipientKey { c.queryItems = [URLQueryItem(name: "k", value: recipientKey)] }
        return c.url!
    }

    var isCollecting: Bool { state == .collecting }
    var isOpen: Bool { state == .open }

    var recipientInitial: String {
        String(recipientName.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }

    var recipientFirstName: String {
        recipientName.split(separator: " ").first.map(String.init) ?? recipientName
    }

    /// "Sealed until Friday, June 12" / "Open" / "Collecting until ..."
    var statusLine: String {
        switch state {
        case .draft: return "Draft"
        case .collecting:
            if let closesAt { return "Collecting until \(closesAt.formatted(.dateTime.weekday(.wide).month(.wide).day()))" }
            return "Collecting"
        case .sealed:
            if let opensAt { return "Sealed until \(opensAt.formatted(.dateTime.weekday(.wide).month(.wide).day()))" }
            return "Sealed"
        case .open: return "Open"
        }
    }
}

// MARK: - Contribution

enum ContributionStatus: String, Codable {
    case pending, approved, hidden
}

enum MediaKind: String, Codable {
    case photo, voice, video
}

struct Media: Identifiable, Codable, Hashable {
    var id: UUID
    var kind: MediaKind
    var url: URL?               // signed URL when fetched; nil until ready
    var posterURL: URL?
    var durationSeconds: Double?
    var transcript: String?
    var width: Int?
    var height: Int?

    /// Local-only, before upload.
    var localURL: URL?
}

struct Contribution: Identifiable, Codable, Hashable {
    var id: UUID
    var sendoffID: UUID
    var authorID: UUID?
    var authorName: String
    var authorRelationship: String?
    var body: String?
    var promptUsed: String?
    var status: ContributionStatus
    var sharedWithGroup: Bool
    var pinned: Bool
    var sortOrder: Int?
    var media: [Media]
    var createdAt: Date

    var hasText: Bool { !(body?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) }
    var photos: [Media] { media.filter { $0.kind == .photo } }
    var voice: Media? { media.first { $0.kind == .voice } }
    var video: Media? { media.first { $0.kind == .video } }

    /// "Dana · Your 2019 intern"
    var signature: String {
        if let rel = authorRelationship, !rel.isEmpty { return "\(authorName) · \(rel)" }
        return authorName
    }
}

// MARK: - Music

struct MusicTrack: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var artist: String?
    var durationSeconds: Int?
    var storagePath: String?
    var appleMusicID: String?
    var premium: Bool
    var mood: String?

    var isLinked: Bool { appleMusicID != nil }
}

// MARK: - Limits

enum Limits {
    static let videoSeconds: TimeInterval = 60
    static let voiceSeconds: TimeInterval = 120
    static let photosPerEntry = 6
    static let bodyCharacters = 2000
}

import Foundation
import Observation
import Supabase

/// The real store. Mirrors `supabase/migrations/0001_init.sql`.
///
/// Configure with `SUPABASE_URL` and `SUPABASE_ANON_KEY` in `Config/Local.xcconfig`
/// (gitignored) which flow into Info.plist as `SupabaseURL` / `SupabaseAnonKey`.
@Observable
final class SupabaseStore: SendoffStore {
    private let client: SupabaseClient

    private(set) var currentUserID: UUID?
    private(set) var currentUserName: String = ""

    init(client: SupabaseClient) {
        self.client = client
        Task { await refreshSession() }
    }

    static func fromInfoPlist() -> SupabaseStore? {
        guard let urlString = Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String,
              let url = URL(string: urlString),
              let key = Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String,
              !key.isEmpty else { return nil }
        return SupabaseStore(client: SupabaseClient(supabaseURL: url, supabaseKey: key))
    }

    private func refreshSession() async {
        if let session = try? await client.auth.session {
            currentUserID = session.user.id
            currentUserName = (session.user.userMetadata["display_name"]?.stringValue) ?? session.user.email ?? ""
        }
    }

    /// Contributors and recipients get an anonymous session so RLS has a `auth.uid()` to work with.
    func ensureSession() async throws {
        if (try? await client.auth.session) == nil {
            try await client.auth.signInAnonymously()
        }
        await refreshSession()
    }

    // MARK: Rows

    private struct SendoffRow: Codable {
        var id: UUID
        var slug: String
        var organizer_id: UUID
        var occasion: Occasion
        var recipient_name: String
        var recipient_photo_path: String?
        var from_line: String?
        var cover_message: String?
        var theme_id: ThemeID
        var music_track_id: String?
        var state: SendoffState
        var moderation: ModerationMode
        var reveal: RevealPolicy
        var closes_at: Date?
        var opens_at: Date?
        var opened_at: Date?
        var plan: Plan
        var contributor_limit: Int
        var contributor_goal: Int?
        var created_at: Date
        // Only present on rows the organizer reads (RLS "organizer full access").
        var contribute_token: String?
        var recipient_key: String?

        func model(organizerName: String) -> Sendoff {
            Sendoff(id: id, slug: slug, organizerID: organizer_id, organizerName: organizerName,
                    occasion: occasion, recipientName: recipient_name, recipientPhotoURL: nil,
                    fromLine: from_line, coverMessage: cover_message, themeID: theme_id,
                    musicTrackID: music_track_id, state: state, moderation: moderation, reveal: reveal,
                    closesAt: closes_at, opensAt: opens_at, openedAt: opened_at, plan: plan,
                    contributorLimit: contributor_limit, createdAt: created_at, contributorGoal: contributor_goal,
                    contributeToken: contribute_token, recipientKey: recipient_key)
        }
    }

    private struct ContributionRow: Codable {
        var id: UUID
        var sendoff_id: UUID
        var author_id: UUID?
        var author_name: String
        var author_relationship: String?
        var body: String?
        var prompt_used: String?
        var status: ContributionStatus
        var shared_with_group: Bool
        var pinned: Bool
        var sort_order: Int?
        var created_at: Date
        var media: [MediaRow]?

        func model() -> Contribution {
            Contribution(id: id, sendoffID: sendoff_id, authorID: author_id, authorName: author_name,
                         authorRelationship: author_relationship, body: body, promptUsed: prompt_used,
                         status: status, sharedWithGroup: shared_with_group, pinned: pinned,
                         sortOrder: sort_order, media: (media ?? []).map { $0.model() }, createdAt: created_at)
        }
    }

    private struct MediaRow: Codable {
        var id: UUID
        var kind: MediaKind
        var storage_path: String
        var processed_path: String?
        var poster_path: String?
        var duration_seconds: Double?
        var transcript: String?
        var width: Int?
        var height: Int?

        func model() -> Media {
            // Signed URLs are resolved lazily by MediaResolver; keep paths here.
            Media(id: id, kind: kind, url: nil, posterURL: nil, durationSeconds: duration_seconds,
                  transcript: transcript, width: width, height: height, localURL: nil)
        }
    }

    // MARK: Organizer

    func mySendoffs() async throws -> [Sendoff] {
        guard let uid = currentUserID else { return [] }
        let rows: [SendoffRow] = try await client.from("sendoffs")
            .select().eq("organizer_id", value: uid).order("created_at", ascending: false)
            .execute().value
        return rows.map { $0.model(organizerName: currentUserName) }
    }

    func create(_ d: SendoffDraft) async throws -> Sendoff {
        guard let uid = currentUserID else { throw StoreError.notAllowed }
        struct Insert: Encodable {
            var slug: String; var organizer_id: UUID; var occasion: Occasion; var recipient_name: String
            var from_line: String?; var cover_message: String?; var theme_id: ThemeID; var music_track_id: String?
            var state: SendoffState; var moderation: ModerationMode; var reveal: RevealPolicy
            var closes_at: Date?; var opens_at: Date?; var contributor_goal: Int
        }
        let ins = Insert(slug: Slug.make(), organizer_id: uid, occasion: d.occasion,
                         recipient_name: d.recipientName, from_line: d.fromLine.isEmpty ? nil : d.fromLine,
                         cover_message: d.coverMessage.isEmpty ? nil : d.coverMessage, theme_id: d.themeID,
                         music_track_id: d.musicTrackID ?? d.occasion.defaultTrack, state: .collecting,
                         moderation: d.moderation, reveal: d.reveal, closes_at: d.closesAt,
                         opens_at: d.reveal == .onDate ? d.opensAt : nil, contributor_goal: d.goal)
        let row: SendoffRow = try await client.from("sendoffs").insert(ins).select().single().execute().value
        return row.model(organizerName: currentUserName)
    }

    func update(_ s: Sendoff) async throws -> Sendoff {
        struct Patch: Encodable {
            var recipient_name: String; var from_line: String?; var cover_message: String?
            var theme_id: ThemeID; var music_track_id: String?; var moderation: ModerationMode
            var reveal: RevealPolicy; var closes_at: Date?; var opens_at: Date?
        }
        let p = Patch(recipient_name: s.recipientName, from_line: s.fromLine, cover_message: s.coverMessage,
                      theme_id: s.themeID, music_track_id: s.musicTrackID, moderation: s.moderation,
                      reveal: s.reveal, closes_at: s.closesAt, opens_at: s.opensAt)
        let row: SendoffRow = try await client.from("sendoffs").update(p).eq("id", value: s.id)
            .select().single().execute().value
        return row.model(organizerName: currentUserName)
    }

    func setState(_ id: UUID, _ state: SendoffState) async throws {
        try await client.from("sendoffs").update(["state": state.rawValue]).eq("id", value: id).execute()
    }

    func contributions(for sendoffID: UUID) async throws -> [Contribution] {
        let rows: [ContributionRow] = try await client.from("contributions")
            .select("*, media(*)").eq("sendoff_id", value: sendoffID).execute().value
        return rows.map { $0.model() }.sorted(by: Contribution.revealOrder)
    }

    func setStatus(_ contributionID: UUID, _ status: ContributionStatus) async throws {
        try await client.from("contributions").update(["status": status.rawValue])
            .eq("id", value: contributionID).execute()
    }

    func reorder(_ sendoffID: UUID, orderedIDs: [UUID]) async throws {
        for (i, id) in orderedIDs.enumerated() {
            try await client.from("contributions").update(["sort_order": i]).eq("id", value: id).execute()
        }
    }

    func delete(contribution id: UUID) async throws {
        try await client.from("contributions").delete().eq("id", value: id).execute()
    }

    // MARK: Contributor

    func sendoff(slug: String) async throws -> Sendoff {
        // The shared link carries slug + token; the token is kept by AppRouter.
        guard let token = AppRouter.pendingToken(for: slug) else { throw StoreError.notAllowed }
        try await ensureSession()
        struct Pub: Codable {
            var id: UUID; var recipient_name: String; var occasion: Occasion; var from_line: String?
            var theme_id: ThemeID; var closes_at: Date?; var state: SendoffState; var organizer_name: String?
        }
        let rows: [Pub] = try await client.rpc("sendoff_public", params: ["p_slug": slug, "p_token": token])
            .execute().value
        guard let r = rows.first else { throw StoreError.notFound }
        return Sendoff(id: r.id, slug: slug, organizerID: UUID(), organizerName: r.organizer_name ?? "the organizer",
                       occasion: r.occasion, recipientName: r.recipient_name, recipientPhotoURL: nil,
                       fromLine: r.from_line, coverMessage: nil, themeID: r.theme_id, musicTrackID: nil,
                       state: r.state, moderation: .trust, reveal: .onDate, closesAt: r.closes_at,
                       opensAt: nil, openedAt: nil, plan: .free, contributorLimit: 100, createdAt: .now)
    }

    func myContribution(for sendoffID: UUID) async throws -> Contribution? {
        guard let uid = currentUserID else { return nil }
        let rows: [ContributionRow] = try await client.from("contributions")
            .select("*, media(*)").eq("sendoff_id", value: sendoffID).eq("author_id", value: uid)
            .limit(1).execute().value
        return rows.first?.model()
    }

    func submit(_ d: ContributionDraft, to sendoffID: UUID) async throws -> Contribution {
        try await ensureSession()
        guard let uid = currentUserID else { throw StoreError.notAllowed }
        struct Insert: Encodable {
            var sendoff_id: UUID; var author_id: UUID; var author_name: String
            var author_relationship: String?; var body: String?; var prompt_used: String?; var shared_with_group: Bool
        }
        let ins = Insert(sendoff_id: sendoffID, author_id: uid, author_name: d.authorName,
                         author_relationship: d.authorRelationship.isEmpty ? nil : d.authorRelationship,
                         body: d.body.isEmpty ? nil : d.body, prompt_used: d.promptUsed,
                         shared_with_group: d.sharedWithGroup)
        let row: ContributionRow = try await client.from("contributions").insert(ins).select().single().execute().value

        // Upload media, then insert rows.
        for (i, m) in d.media.enumerated() {
            guard let local = m.localURL else { continue }
            let data = try Data(contentsOf: local)
            let path = "\(sendoffID)/\(row.id)/\(m.id).\(local.pathExtension)"
            try await client.storage.from("uploads").upload(path, data: data)
            struct MIns: Encodable {
                var contribution_id: UUID; var kind: MediaKind; var storage_path: String
                var duration_seconds: Double?; var sort_order: Int
            }
            try await client.from("media").insert(MIns(contribution_id: row.id, kind: m.kind, storage_path: path,
                                                       duration_seconds: m.durationSeconds, sort_order: i)).execute()
        }
        var model = row.model()
        model.media = d.media
        return model
    }

    // MARK: Recipient

    func revealContributions(for sendoffID: UUID) async throws -> [Contribution] {
        let rows: [ContributionRow] = try await client.from("contributions")
            .select("*, media(*)").eq("sendoff_id", value: sendoffID).eq("status", value: "approved")
            .execute().value
        return rows.map { $0.model() }.sorted(by: Contribution.revealOrder)
    }

    func markOpened(_ sendoffID: UUID) async throws {
        try await client.from("sendoffs").update(["opened_at": Date.now.ISO8601Format()])
            .eq("id", value: sendoffID).execute()
    }

    // MARK: Catalog

    func tracks() async throws -> [MusicTrack] {
        struct Row: Codable {
            var id: String; var title: String; var artist: String?; var duration_seconds: Int?
            var storage_path: String?; var apple_music_id: String?; var premium: Bool; var mood: String?
        }
        let rows: [Row] = try await client.from("music_tracks").select().order("sort_order").execute().value
        return rows.map { MusicTrack(id: $0.id, title: $0.title, artist: $0.artist, durationSeconds: $0.duration_seconds,
                                     storagePath: $0.storage_path, appleMusicID: $0.apple_music_id,
                                     premium: $0.premium, mood: $0.mood) }
    }
}

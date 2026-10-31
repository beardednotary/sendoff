import Foundation
import Observation
import Supabase

/// Paths in the `uploads` bucket. Ids are lowercase: the storage policies match them with
/// `^[0-9a-f-]{36}$` (0002_web.sql) and Swift prints UUIDs in uppercase.
enum StoragePath {
    /// {sendoff_id}/cover/{file}.jpg, the only shape `sendoffs_cover_is_own` (0005) accepts.
    static func cover(_ sendoff: UUID, file: UUID = UUID()) -> String {
        "\(id(sendoff))/cover/\(id(file)).jpg"
    }

    /// {sendoff_id}/{contribution_id}/{media_id}.{ext}
    static func media(_ sendoff: UUID, _ contribution: UUID, _ media: UUID, ext: String) -> String {
        "\(id(sendoff))/\(id(contribution))/\(id(media)).\(ext)"
    }

    private static func id(_ u: UUID) -> String { u.uuidString.lowercased() }
}

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

        func model(organizerName: String, photo: URL? = nil) -> Sendoff {
            Sendoff(id: id, slug: slug, organizerID: organizer_id, organizerName: organizerName,
                    occasion: occasion, recipientName: recipient_name, recipientPhotoURL: photo,
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

        func model(urls: [String: URL] = [:], media override: [MediaRow]? = nil) -> Contribution {
            Contribution(id: id, sendoffID: sendoff_id, authorID: author_id, authorName: author_name,
                         authorRelationship: author_relationship, body: body, promptUsed: prompt_used,
                         status: status, sharedWithGroup: shared_with_group, pinned: pinned, sortOrder: sort_order,
                         media: (override ?? media ?? []).sorted { ($0.sort_order ?? 0) < ($1.sort_order ?? 0) }.map { $0.model(urls: urls) },
                         createdAt: created_at)
        }
    }

    private struct MediaRow: Codable {
        var id: UUID
        var contribution_id: UUID?
        var sort_order: Int?
        var kind: MediaKind
        var storage_path: String
        var processed_path: String?
        var poster_path: String?
        var duration_seconds: Double?
        var transcript: String?
        var width: Int?
        var height: Int?

        /// Media is private: `urls` maps storage paths to signed URLs (see `signedMedia`).
        func model(urls: [String: URL] = [:]) -> Media {
            Media(id: id, kind: kind, url: urls[storage_path], posterURL: poster_path.flatMap { urls[$0] },
                  durationSeconds: duration_seconds, transcript: transcript, width: width, height: height, localURL: nil)
        }
    }

    // MARK: Organizer

    func mySendoffs() async throws -> [Sendoff] {
        guard let uid = currentUserID else { return [] }
        let rows: [SendoffRow] = try await client.from("sendoffs")
            .select().eq("organizer_id", value: uid).order("created_at", ascending: false)
            .execute().value
        let photos = await signedCovers(rows.compactMap(\.recipient_photo_path))
        return rows.map { $0.model(organizerName: currentUserName, photo: $0.recipient_photo_path.flatMap { photos[$0] }) }
    }

    /// Covers live in the private `uploads` bucket; the organizer's read policy lets them sign
    /// their own. Signed for a day, which outlasts any session in the library.
    private func signedCovers(_ paths: [String]) async -> [String: URL] {
        await signed(paths, in: "uploads")
    }

    private func signed(_ paths: [String], in bucket: String) async -> [String: URL] {
        guard !paths.isEmpty,
              let results = try? await client.storage.from(bucket).createSignedURLs(paths: paths, expiresIn: 86_400)
        else { return [:] }
        var urls: [String: URL] = [:]
        for r in results { if let u = r.signedURL { urls[r.path] = u } }
        return urls
    }

    /// Uploads the cover to {sendoff_id}/cover/ and records its path. A failed upload leaves the
    /// Sendoff without a photo rather than failing a creation that already happened.
    private func attachCover(_ local: URL, to sendoffID: UUID) async -> URL? {
        guard let data = try? Data(contentsOf: local) else { return nil }
        let path = StoragePath.cover(sendoffID)
        do {
            try await client.storage.from("uploads").upload(path, data: data, options: FileOptions(contentType: "image/jpeg"))
            try await client.from("sendoffs").update(["recipient_photo_path": path]).eq("id", value: sendoffID).execute()
            return local
        } catch {
            return nil
        }
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
        let photo: URL? = if let local = d.recipientPhoto { await attachCover(local, to: row.id) } else { nil }
        return row.model(organizerName: currentUserName, photo: photo)
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
        return row.model(organizerName: currentUserName, photo: s.recipientPhotoURL)
    }

    func setState(_ id: UUID, _ state: SendoffState) async throws {
        try await client.from("sendoffs").update(["state": state.rawValue]).eq("id", value: id).execute()
    }

    func contributions(for sendoffID: UUID) async throws -> [Contribution] {
        let rows: [ContributionRow] = try await client.from("contributions")
            .select("*, media(*)").eq("sendoff_id", value: sendoffID).execute().value
        let urls = await signedMedia(rows.flatMap { $0.media ?? [] })
        return rows.map { $0.model(urls: urls) }.sorted(by: Contribution.revealOrder)
    }

    /// The organizer reads `uploads` and `processed` under their Sendoff (0002_web.sql), so they
    /// sign their own: originals in `uploads`, posters in `processed`.
    private func signedMedia(_ media: [MediaRow]) async -> [String: URL] {
        let originals = await signed(media.map(\.storage_path), in: "uploads")
        let posters = await signed(media.compactMap(\.poster_path), in: "processed")
        return originals.merging(posters) { a, _ in a }
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
            let path = StoragePath.media(sendoffID, row.id, m.id, ext: local.pathExtension)
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

    /// What `sendoff_reveal` and `sendoff_open` return (0005_cover_photo.sql).
    private struct RevealRow: Codable {
        var id: UUID; var recipient_name: String; var occasion: Occasion; var from_line: String?
        var cover_message: String?; var theme_id: ThemeID; var music_track_id: String?
        var state: SendoffState; var reveal: RevealPolicy; var opens_at: Date?
        var organizer_name: String?; var contributor_count: Int?; var plan: Plan?
        var recipient_photo_path: String?
    }

    func reveal(slug: String, key: String) async throws -> Sendoff {
        try await ensureSession()
        let rows: [RevealRow] = try await client.rpc("sendoff_reveal", params: ["p_slug": slug, "p_key": key])
            .execute().value
        guard let r = rows.first else { throw StoreError.notFound }
        return await revealModel(r, slug: slug, key: key)
    }

    func open(slug: String, key: String) async throws -> Sendoff {
        try await ensureSession()
        let rows: [RevealRow] = try await client.rpc("sendoff_open", params: ["p_slug": slug, "p_key": key])
            .execute().value
        guard let r = rows.first else { throw StoreError.sealed }
        return await revealModel(r, slug: slug, key: key)
    }

    func revealContributions(slug: String, key: String) async throws -> [Contribution] {
        try await ensureSession()
        let params = ["p_slug": slug, "p_key": key]
        async let entries: [ContributionRow] = client.rpc("reveal_contributions", params: params).execute().value
        async let files: [MediaRow] = client.rpc("reveal_media", params: params).execute().value
        let (rows, media) = try await (entries, files)
        let urls = await signForRecipient(slug: slug, key: key,
                                          paths: media.flatMap { [$0.storage_path, $0.poster_path].compactMap { $0 } })
        let byEntry = Dictionary(grouping: media) { $0.contribution_id }
        return rows.map { $0.model(urls: urls, media: byEntry[$0.id] ?? []) }.sorted(by: Contribution.revealOrder)
    }

    private func revealModel(_ r: RevealRow, slug: String, key: String) async -> Sendoff {
        var photo: URL?
        if let path = r.recipient_photo_path { photo = await signForRecipient(slug: slug, key: key, paths: [path])[path] }
        var s = Sendoff(id: r.id, slug: slug, organizerID: UUID(), organizerName: r.organizer_name ?? "the organizer",
                        occasion: r.occasion, recipientName: r.recipient_name, recipientPhotoURL: photo,
                        fromLine: r.from_line, coverMessage: r.cover_message, themeID: r.theme_id,
                        musicTrackID: r.music_track_id, state: r.state, moderation: .trust, reveal: r.reveal,
                        closesAt: nil, opensAt: r.opens_at, openedAt: nil, plan: r.plan ?? .free,
                        contributorLimit: 0, createdAt: .now, recipientKey: key)
        s.contributorCount = r.contributor_count
        return s
    }

    /// The recipient holds no storage grant; `sign-media` checks the key and signs for them.
    private func signForRecipient(slug: String, key: String, paths: [String]) async -> [String: URL] {
        guard !paths.isEmpty else { return [:] }
        struct Body: Encodable { let slug: String; let key: String; let paths: [String] }
        struct Reply: Decodable { let urls: [String: String] }
        guard let reply: Reply = try? await client.functions.invoke(
            "sign-media", options: FunctionInvokeOptions(body: Body(slug: slug, key: key, paths: paths)))
        else { return [:] }
        return reply.urls.compactMapValues(URL.init(string:))
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

    // MARK: Payments (mirrors 0003_payments.sql)

    private struct EntitlementRow: Codable {
        var id: UUID; var product_id: String; var source: String; var external_id: String?
        var consumed_by: UUID?; var expires_at: Date?; var created_at: Date

        func model() -> Entitlement {
            Entitlement(id: id, productID: product_id, source: source, externalID: external_id,
                        consumedBy: consumed_by, expiresAt: expires_at, createdAt: created_at)
        }
    }

    func entitlements() async throws -> [Entitlement] {
        guard let uid = currentUserID else { return [] }
        let rows: [EntitlementRow] = try await client.from("entitlements").select()
            .eq("user_id", value: uid).order("created_at").execute().value
        return rows.map { $0.model() }
    }

    func recordPurchase(_ product: ProductID, transactionID: String) async throws -> [Entitlement] {
        guard let uid = currentUserID else { throw StoreError.notAllowed }
        guard let plan = product.plan, let creditProduct = ProductID.credit(for: plan) else { return [] }
        struct Insert: Encodable { var user_id: UUID; var product_id: String; var source: String; var external_id: String }
        let rows = (0..<product.credits).map { i in
            Insert(user_id: uid, product_id: creditProduct.rawValue, source: "storekit",
                   external_id: product.credits == 1 ? transactionID : "\(transactionID)#\(i)")
        }
        // `external_id` is unique, so replaying a transaction (app relaunch before finish()) is a no-op.
        try await client.from("entitlements").upsert(rows, onConflict: "external_id", ignoreDuplicates: true).execute()
        let saved: [EntitlementRow] = try await client.from("entitlements").select()
            .eq("user_id", value: uid).like("external_id", pattern: "\(transactionID)%").execute().value
        return saved.map { $0.model() }
    }

    func redeem(_ entitlementID: UUID, for sendoffID: UUID) async throws -> Sendoff {
        let rows: [SendoffRow] = try await client
            .rpc("redeem_entitlement", params: ["p_entitlement": entitlementID.uuidString, "p_sendoff": sendoffID.uuidString])
            .execute().value
        guard let row = rows.first else { throw StoreError.noCredit }
        let photos = await signedCovers([row.recipient_photo_path].compactMap { $0 })
        return row.model(organizerName: currentUserName, photo: row.recipient_photo_path.flatMap { photos[$0] })
    }
}

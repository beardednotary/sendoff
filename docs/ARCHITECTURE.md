# Sendoff — Architecture

## Shape

```
                 ┌──────────────────────────┐
  Organizer  ──► │  iOS app (SwiftUI)       │ ◄── Recipient with the app (optional,
  (create,       │  + App Clip (contribute) │     richer reveal, library, exports)
   tend, share)  └───────────┬──────────────┘
                             │  supabase-swift
 Contributor ──► web  /s/{slug}        (any device) ──┐
 Recipient   ──► web  /s/{slug}/open   (any device, ──┤
                 via link or QR code)                  ▼
                         ┌─────────────────────────────────────┐
                         │ Supabase                            │
                         │  Postgres + RLS   Auth (magic link) │
                         │  Storage (media)  Edge Functions    │
                         └─────────────────────────────────────┘
                                   │                 │
                        Transcode / transcripts    Stripe (org plans)
                        (Edge fn → Mux or ffmpeg)  StoreKit 2 (iOS)
```

### Why Supabase

### Who needs the app

Nobody but the organizer, and even they could use the web later. **Contributors and recipients
never need an iOS device or an install.** The shared link and the recipient's link (or a QR code
on a printed card) open generated web pages that carry the full experience: contribute, and the
sealed reveal with music and motion. The iOS app is the organizer's tool and the premium home for
recipients who do have it (library, offline keepsake, exports, Apple Music playback).

### Why Supabase

- Postgres with **row level security** is the right tool for "contributors see only their own
  entry, the organizer sees everything, the recipient sees approved entries after the reveal
  date". Those are three policies on one table, enforced in the database, not in app code.
- Magic-link auth gives contributors edit access to their own entry without a password or an
  account they will remember.
- Storage with signed URLs handles photos, voice and video without running a file server.
- A first-class Swift SDK (`supabase-swift`) and a JS SDK for the web page.
- Firebase would also work; Firestore's rules make the privacy model harder to express and
  harder to audit.

## iOS app

- **SwiftUI, iOS 17+**, `@Observable` models, Swift concurrency. No UIKit except where SwiftUI
  has no API (share sheet, video capture).
- **XcodeGen** generates the `.xcodeproj` from `ios/project.yml` so the project file is not
  hand-maintained and merges cleanly. On the Mac: `brew install xcodegen`, then
  `cd ios && xcodegen generate && open Sendoff.xcodeproj`.
- Targets: `Sendoff` (app), `SendoffClip` (App Clip, contribute flow only), `SendoffTests`.
- Bundle ID `com.dahvio.sendoff`; the App Clip is `com.dahvio.sendoff.Clip`.

### Layers

| Folder | Contents |
|---|---|
| `App/` | `SendoffApp` entry, `AppConfig` (domain, keys from xcconfig), `AppRouter` (deep links `sendoffapp.com/s/{slug}`), environment wiring |
| `Models/` | `Sendoff`, `Contribution`, `Occasion`, `MusicTrack`, `ModerationMode`, `RevealPolicy` |
| `Design/` | `SendoffTheme` (data), `ThemeCatalog`, `Typography`, `Motion`, and `Components/` (Seal, Flap, Stamp, Ribbon, Envelope, Waveform) |
| `Features/` | One folder per flow: `Home`, `Create`, `Contribute`, `Admin`, `Reveal`, `Share` |
| `Services/` | `SendoffStore` protocol with `MockStore` (previews, tests, offline demo) and `SupabaseStore` |

The UI depends only on `SendoffStore`. `MockStore` is complete enough to run the whole app
without a backend, which is how the app is demoed before Supabase is configured.

### Deep links

`https://sendoffapp.com/s/{slug}?t={token}` is a universal link. The app opens the contribute flow (or the
reveal, if the viewer is the recipient and the Sendoff is open). The App Clip handles the same
URL for people without the app. The web page is the fallback for everything else.

### Payments

- iOS: StoreKit 2 (`Services/Purchases.swift`). Consumables `sendoff.single`, `sendoff.plus`,
  `sendoff.pack5`, `sendoff.pack10`; non-consumables `theme.{id}`. A finished consumable is
  recorded as credits in `entitlements` (one row per credit, `external_id` = transaction id,
  unique) *before* `finish()`, so a crash cannot lose it. `redeem_entitlement()` spends a credit
  on a Sendoff: raises `plan` and `contributor_limit`, never lowers them. The paywall
  (`Features/Paywall`) appears on the organizer's dashboard after entries arrive, never before.
- Limits are enforced in the database: a trigger refuses the insert past `contributor_limit`
  (`sendoff_full`), Free holds 10, hidden entries do not count.
- `ios/Sendoff.storekit` lets the simulator buy without App Store Connect; the `Sendoff` scheme
  runs with it. In App Store Connect create the same product ids.
- v1 trusts the device's StoreKit verification when the client inserts entitlement rows.
  Server-side verification (App Store Server API, and refund reconciliation) is a follow-up.
- Web / org: Stripe Checkout via an Edge Function. Entitlements land in `entitlements` and the
  app reads them from the database, so a purchase on either side unlocks on both.

## Data model

See `supabase/migrations/0001_init.sql` for the authoritative schema. Summary:

| Table | Purpose |
|---|---|
| `profiles` | One per auth user. Display name, org membership. |
| `orgs` | HR / business accounts. Plan, branding, default moderation. |
| `sendoffs` | The envelope. Occasion, recipient, theme, music, reveal policy, moderation mode, slug, `recipient_key` for the reveal link, state (`collecting`, `sealed`, `open`). |
| `contributions` | One entry. Author (auth user or anonymous token), text, signature, relationship, status (`pending`, `approved`, `hidden`), order. |
| `media` | Photos / voice / video attached to a contribution. Storage path, kind, duration, transcript, transcode status. |
| `music_tracks` | Stock catalog plus linked external tracks (Apple Music IDs). |
| `themes` | Theme definitions as JSON so premium themes ship server-side. |
| `entitlements` | What a user or org has paid for. |
| `invites` | Optional roster for nudges and "who hasn't added". |

### The privacy model, as RLS

- `contributions` **select**: you are the organizer of the parent Sendoff, **or** you are the
  recipient and the Sendoff state is `open` and the row is `approved`, **or** you authored the
  row, **or** the row has `shared_with_group = true` and you have contributed to the same
  Sendoff.
- `contributions` **insert**: the parent Sendoff is `collecting` and you hold its contribute
  token (anonymous contributors get a Supabase anonymous session tied to the slug).
- `contributions` **update**: author (until `sealed`) or organizer.
- `media`: inherits from its contribution via a join policy; files are served by signed URL only.

## Web

`web/app` is a small Vite + TypeScript site (no framework), and it is a first-class surface, not
a fallback. It runs against Supabase, or against an in-memory mock when no keys are set, so the
design can be reviewed with `npm run dev` and nothing else. See `web/app/README.md`.

| Route | Who | What |
|---|---|---|
| `/s/{slug}` | Contributor | Add a note, photos, voice note or video. No account. |
| `/s/{slug}/open?k={recipient_key}` | Recipient | The sealed envelope. Breaks open at `opens_at`. Music, one entry at a time, keepsake at the end. |
| `/s/{slug}/qr?t={token}` | Organizer | Printable QR card for the party, the break room or inside a physical card. |

Web privacy, concretely: contributors get an anonymous Supabase session so RLS has an `auth.uid()`
for their own row. The token and key in the links are the real capabilities, checked by
`security definer` functions (`sendoff_public`, `sendoff_reveal`, `sendoff_open`,
`reveal_contributions`, `reveal_media`; see `0002_web.sql`). Media is private; contributors sign
their own uploads via storage RLS, recipients get URLs from the `sign-media` Edge Function.

The recipient link carries a long random key (`recipient_key`) so it cannot be guessed from the
contribute slug. The organizer gets both links and a QR code from the share screen. Recipients
can optionally sign in (magic link) to keep the Sendoff in a library across devices.

`web/prototype/` holds the static design prototype used to settle the visual language before the
app or the site is built. It renders both the contribute page and the reveal.

### Domain

**`sendoffapp.com`** (registered). It is never hardcoded: the iOS build reads `PUBLIC_HOST` from
`ios/Config/Local.xcconfig` (into Info.plist and the associated-domains entitlement) and the web
reads `VITE_PUBLIC_ORIGIN`. Three things must point at it:

1. DNS for the web host (Vercel, Netlify or Cloudflare Pages) serving `web/app/dist`.
2. `web/app/public/.well-known/apple-app-site-association`, with `TEAMID` replaced by the Apple
   team id, served as `application/json` with no redirect. Universal links and the App Clip
   depend on it.
3. Supabase Auth redirect URLs (magic links for organizers and recipients who sign in).

## Media pipeline

1. Client uploads to Storage bucket `uploads/{sendoff}/{contribution}/{uuid}` with a signed
   upload URL (60s video / 2 min voice caps enforced client-side and by an Edge Function that
   rejects over-length files).
2. A database webhook on `media` insert calls the `process-media` Edge Function
   (`supabase/functions/process-media`). It enforces the length caps server-side and moves status
   `uploaded → processing → ready`. Edge Functions cannot run ffmpeg, so transcoding is an
   adapter: `passthrough` (default, originals served as uploaded; enough to ship) or `mux`
   (H.264 720p, poster frame, loudness, via a signed URL to Mux). Transcripts come later.
3. Raw uploads are deleted 7 days after `ready`.

## Keepsake exports

- PDF: rendered on-device with `ImageRenderer` from the same SwiftUI views as the reveal.
- Video montage: Edge Function assembles clips, stills (Ken Burns) and the music track; output
  stored and emailed.
- Print: hand off the PDF to a print-on-demand API (Lulu or Blurb) in a later phase.

## Environments

| | Supabase project | Universal link host |
|---|---|---|
| dev | `sendoff-dev` | `dev.sendoffapp.com` |
| prod | `sendoff` | `sendoffapp.com` |

Secrets live in `ios/Config/*.xcconfig` (gitignored) and Supabase project settings. Nothing is
committed.

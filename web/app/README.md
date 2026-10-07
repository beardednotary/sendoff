# Sendoff web

The pages contributors and recipients land on. Vite + TypeScript, no framework. Supabase for
data, or an in-memory mock when no keys are configured.

| Route | Who | What |
|---|---|---|
| `/s/{slug}?t={token}` | Contributor | Add a note, photos, a voice note or a video. No account. Come back and change it until the seal. |
| `/s/{slug}/open?k={key}` | Recipient | The sealed envelope. Countdown until `opens_at`, then music, one entry at a time, keepsake, print to PDF. |
| `/s/{slug}/qr?t={token}` | Organizer | Printable QR card for the break room or inside a real card. |
| `/` | Anyone | One screen. In mock mode it links to the three demo Sendoffs. |

## Run

```bash
cd web/app
npm install
npm run dev          # http://localhost:5173, mock data
```

Without `.env.local` the site runs against `MockStore` with the same three Sendoffs as the iOS
`MockStore`: `maria-r` (opens now), `mr-patel` (sealed, countdown), `jo-moves` (collecting).
Any `t` or `k` value is accepted in mock mode. Add `?mock` to any URL to force the mock even
when keys are set.

To run against Supabase, copy `.env.example` to `.env.local`, fill in the URL and anon key, and
apply `supabase/migrations/0002_web.sql` (storage policies and the reveal/open functions) plus
deploy `supabase/functions/sign-media`.

```bash
npm run build        # typecheck + dist/
npm run preview
npm run e2e          # build, serve, run e2e/smoke.mjs in headless Chromium (needs `npx playwright install chromium`)
```

## Deploy

Static host with SPA rewrites (every path to `/index.html`): Vercel, Netlify, Cloudflare Pages.
Set `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`, `VITE_PUBLIC_ORIGIN` in the host's env.
Serve `/.well-known/apple-app-site-association` from the same origin for universal links and the
App Clip (`public/.well-known/` once the domain and team id are final).

## How privacy holds on the web

- Contributors get an anonymous Supabase session. Their row has `author_id = auth.uid()`, so
  RLS lets them read and edit only their own entry.
- The contribute token and recipient key in the link are the real capabilities. They are checked
  by `security definer` functions in Postgres (`sendoff_public`, `sendoff_reveal`,
  `sendoff_open`, `reveal_contributions`, `reveal_media`), never by client code.
- Media is in a private bucket. A contributor signs their own uploads through storage RLS. The
  recipient has no row grant, so the `sign-media` Edge Function checks slug + key and signs for
  them with the service role.

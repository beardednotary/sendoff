# Sendoff web

The pages contributors and recipients land on. Vite + TypeScript, no framework. Supabase for
data, or an in-memory mock when no keys are configured.

| Route | Who | What |
|---|---|---|
| `/s/{slug}?t={token}` | Contributor | Add a note, photos, a voice note or a video. No account. Come back and change it until the seal. |
| `/s/{slug}/open?k={key}` | Recipient | The seal over their photo. Countdown until `opens_at`, then press and hold (Enter from the keyboard), music, one entry at a time, keepsake, print to PDF. |
| `/s/{slug}/qr?t={token}` | Organizer | Printable QR card for the break room or inside a real card. |
| `/` | Anyone | The homepage: hero, how it works, why it is different, what goes in, the occasions, pricing, questions. In dev and the smoke test it also links to the three demo Sendoffs. |
| `/teams` | Companies, schools, teams | The annual plan: tiers, what it includes, personal prices to compare. “Talk to us” writes to support@sendoffapp.com. |
| `/retirement` and five more | Search | One page per occasion: what goes in, how it works, the app's prompts, cost, questions. |
| `/privacy`, `/support` | App Store Connect, anyone | What we keep and who can see it; help. |
| anything else | | A 404 page. |

## Two kinds of page

**The app** (`app.html`, `src/main.ts`, `src/pages`) serves only the private links, `/s/...`. On
Cloudflare, `public/_redirects` rewrites `/s/*` to it (to `/app`, not `/app.html`, which Cloudflare
would answer with a redirect that loses the path); in `npm run dev` and `vite preview` the plugin in
`vite.config.ts` does the same. It carries `noindex` and `no-referrer` itself, as well as from
`public/_headers`. The add-yours page, `/s/{slug}`, gets `add.html` instead, which the build writes
as `app.html` plus Apple's App Clip tag (`apple-itunes-app` with `app-clip-bundle-id`), so iPhones
offer the App Clip there and in Messages and QR codes for that link, but not on the reveal.

**The public pages** (the homepage, `/teams`, the occasions, `/privacy`, `/support`, the 404) are
prerendered, so they reach search engines and link previews as complete HTML with no script. The
words live in `src/site/content.ts` (privacy and support in `src/site/info.ts`), the markup in
`src/site/render.ts`, and the `sitePages` plugin writes each page to `dist/{name}.html` (the
homepage to `index.html`, the 404 to `404.html`), linked to the app's own stylesheet, along with
`sitemap.xml`. Cloudflare and `vite preview` serve them at `/{name}`; anything that matches no
file gets the 404 with a 404 status. In `npm run dev` the plugin renders them on request, so copy
edits show on reload. Every page carries its own title, description, canonical URL, Open Graph
tags and JSON-LD (Organization, MobileApplication, and FAQPage where it has questions).

- **App Store link:** `Site.appStoreUrl` and `Site.appStoreId` in `content.ts` point to the live
  listing; the download CTAs link to it and public pages show Safari's Smart App Banner.
- **Team plan checkout:** give a tier a `checkout` URL (a Stripe Payment Link or Checkout session
  URL) in `Tiers`, and its button buys the plan instead of opening an email.
- **Prices** are in `PersonalPrices`, `PlanTeasers` and `Tiers`, and in the support page's text;
  App Store Connect is the source of truth for the personal ones.
- **Privacy and support** say what the code does. Change `src/site/info.ts`, and its date, when the
  data or who can see it changes.
- **Pictures** are in `public/site`. The homepage opens on Maria's sealed screen, cover and a photo
  entry, over her photo blurred as the sealed screen blurs it. Each occasion opens on its cover, drawn in HTML over one photo
  in `photos/` (Unsplash, free licence; the source is noted beside each cover in `content.ts`).
  The steps and entries are real screens from the iOS app, in `app/`, made from
  `design/v2/app/*.jpg`. Every picture is an AVIF at full and half width plus a full-width JPEG,
  named `{name}-{width}`. To refresh a screen:

  ```bash
  sips -Z 1044 ../../design/v2/app/10-create.jpg -s format avif -s formatOptions 55 --out public/site/app/create-480.avif
  sips -Z 522 ../../design/v2/app/10-create.jpg -s format avif -s formatOptions 60 --out public/site/app/create-240.avif
  sips -Z 1044 ../../design/v2/app/10-create.jpg -s format jpeg -s formatOptions 70 --out public/site/app/create-480.jpg
  ```

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

Live on Cloudflare at sendoffapp.com (`npm run deploy`); the account and DNS are in the root
README ("The website"). `public/_redirects` sends `/s/*` to the app and `wrangler.jsonc` serves
`404.html` for any other path that matches no file. `public/_headers` sets the JSON type for
`/.well-known/apple-app-site-association` and `noindex` / `no-referrer` on every `/s/` link. `robots.txt`
points at the sitemap and keeps `/s/` out of search.
Newsreader is served from `public/fonts/` (SIL OFL) so no page calls a third party. The keys are
read at build time from `.env.local` (`VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`,
`VITE_PUBLIC_ORIGIN`).

## How privacy holds on the web

- Contributors get an anonymous Supabase session. Their row has `author_id = auth.uid()`, so
  RLS lets them read and edit only their own entry.
- The contribute token and recipient key in the link are the real capabilities. They are checked
  by `security definer` functions in Postgres (`sendoff_public`, `sendoff_reveal`,
  `sendoff_open`, `reveal_contributions`, `reveal_media`), never by client code.
- Media is in a private bucket. A contributor signs their own uploads through storage RLS. The
  recipient has no row grant, so the `sign-media` Edge Function checks slug + key and signs for
  them with the service role.

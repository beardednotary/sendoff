# Sendoff v2: Evening

Modeled on the owner's reference, Once (disposable camera for events): near-black ground, warm
white type, a quiet serif for what matters, no accent colour. The photographs and the words
people wrote are the only colour in the app. Replaces the wax seal proposal in `../`, which the
owner rejected.

## What carries over from Once, and what doesn't

| Taken | Not taken |
|---|---|
| Near-black ground, warm white ink, no accent hue | Their film-camera metaphor and grain |
| Sentence-case serif headlines on two lines ("Share the link. / Gather the words.") | Their asterisk mark (Sendoff keeps the Path) |
| Tiny tracked uppercase eyebrows above headlines | Photo grids as the main view: Sendoff is words first |
| White pill for the one main action, dark pills for the rest | |
| Photo cards with the name set on the image | |
| Step flow with dots and a "Next →" pill | |

## Tokens

| Role | Dark (default) | Light |
|---|---|---|
| Ground | `#0E0E0D` | `#F5F3EF` |
| Surface (fields, cards) | `#1A1A18` | `#FFFFFF` |
| Secondary control | `#262624` | `#E8E5DF` |
| Hairline | ink at 10% | ink at 10% |
| Ink | `#F3F1EC` | `#141413` |
| Secondary ink | `#ADAAA3` (8.6:1) | `#55524D` (7.0:1) |
| Tertiary ink | `#8A8781` (5.4:1) | `#6B6863` (5.0:1) |

Type: New York Regular for names, headlines and everything a contributor wrote; SF Pro for the
app. Nine sizes: 60 (seal initial), 48 (reveal cover), 40 (headlines), 28 (entries, card names),
20 (list names), 17 (controls), 15 (body), 13 (meta), 11 (tracked eyebrows). Display tracking
-0.02em. Pills 50pt tall, 44pt small; circles 44pt. Card radius 22 to 24, photo thumbnails 14.

## The seal

A blind-embossed monogram: the initial in New York inside two fine rings, no colour, no wax. On
the sealed reveal it sits over the recipient's photo, blurred and dimmed. Press and hold: the
outer ring draws itself closed around the initial (about a second, light haptic ticks), the blur
lifts, and the cover photo comes into focus as the music starts. Let go early and the ring
unwinds. Reduce Motion: a cross-fade after the hold. VoiceOver: one activation opens it.

## Screens

`mockup.html`, shot to `shots/` (3x) and `shots/small-phone/` (375 x 667). Scan: no FAILs at
either size. The small phone's two warnings are content passing the home indicator on screens
that scroll (the detail's entry list, the share sheet), as they do in the app.

1. Home: "Sendoffs", an "In progress" carousel of photo cards, an "Opened" list.
2. Detail (collecting): the recipient's photo fades into the page; state as three icon lines;
   Share the link + Preview; the entries as plain rows.
3. Create step 1: "Who are we sending off?" with their photo and two fields.
4. Share: QR (real, generated from the link) and two pills.
5. Contribute, in the light theme: the promise at the top, an open writing page, attach pills.
6. Reveal, sealed: blurred photo, the seal mid-hold.
7. Reveal, cover. 8. A written entry. 9. A photo entry. 10. Home, light. Icon: the Path in
   warm white on near-black.

Photos are from Unsplash (free licence), standing in for the recipient photo that
`Sendoff.recipientPhotoURL` already holds and for a contributor's photos.

## Built (30 October 2026)

The owner approved the direction; it is in the iOS app and the App Clip. Choices made on the open
decisions: the app follows the system appearance (Evening in dark, Paper in light); the three
included themes became Paper, Evening and Blackboard (ids unchanged, so stored Sendoffs keep
working; the paid themes and their StoreKit products are untouched); the recipient photo is an
optional cover with a large-initial fallback; the seal opens on a one-second hold; the icon is
the Path in warm white on near-black. Simulator screenshots of the built app are in `app/` (JPEG; `app/sheet.jpg` shows them together).

The web pages (contribute, reveal, QR card, landing) followed the same day: same tokens, the
seal held to open (Enter opens it from the keyboard), Newsreader standing in for New York off
Apple devices, the system sans instead of Inter.

The cover photo goes through Supabase (0005_cover_photo.sql): the app shrinks it to 1600 points
and uploads it to `uploads/{sendoff_id}/cover/`, the organizer's library signs it, and the
recipient's link gets it from `sign-media`, sealed or open, so it can sit blurred behind the seal.

## Decisions for the owner (as proposed)

1. **Dark by default.** The app follows the system setting, with dark designed first.
2. **The six per-Sendoff themes.** Chalk green, Field Day green and Gold Leaf's gold don't belong in
   this look. Proposal: two included looks, Evening (dark) and Paper (light), and retune the
   three paid themes (StoreKit ids `theme.gold_leaf`, `theme.darkroom`, `theme.field_day`) into
   quieter variants, or retire them. Themes stay JSON either way.
3. **The recipient's photo becomes the cover.** It is optional; the field already exists. A
   Sendoff without one needs a type-only card (not designed yet).
4. **Hold to open** instead of tap.
5. **Retired:** paper grain, the dashed stamp labels, the ribbon, the coloured wax seal, the navy
   and gold icon.
6. **Web fonts.** New York only exists on Apple devices. The site (now Fraunces and Inter) needs a
   serif that sits close to New York on Android and Windows.

## Not designed yet

A Sendoff without a photo, create steps 2 to 4 (occasion, date, music), the paywall, review
queue, voice and video entries, the recipient's "Not yet." screen, Kept for you, the empty home.

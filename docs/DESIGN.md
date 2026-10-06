# Sendoff — Design language

Not a template. The visual idea comes from the object we are replacing and the object we are
becoming: **a card passed around the office** becomes **a sealed envelope and a keepsake**.

## Principles

1. **Paper, ink, seal.** Every surface is a material. Backgrounds are paper (warm, slightly
   textured, never pure white). Text is ink (never pure black). Each theme has one *seal*
   color used sparingly for the single most important action or mark on screen.
2. **One thing at a time.** Entries are never shown as a grid of cards competing for attention.
   They are read one at a time, like turning pages. Grids appear only in the organizer's
   management views.
3. **Quiet until the reveal.** Creation and contribution screens are restrained. The reveal is
   where motion, music and color are spent.
4. **Serif for feeling, sans for doing.** Display and entry text use a serif (New York on iOS,
   Fraunces on web). Controls, metadata and admin UI use SF Pro / Inter. The serif is the
   voice of the people writing; the sans is the app getting out of the way.
5. **Never a stock illustration.** Imagery is the contributors' own photos and video. The app's
   own marks are typographic or geometric: the seal, the ribbon, the envelope flap, the stamp.

## The brand mark: the Path

The logo and app icon are a road that reads as an S: wide in the foreground at the bottom left,
winding and narrowing to a vanishing point up and to the right. Cream road, a gold edge where the
light catches it, deep navy sky. It is a sendoff: someone walking toward somewhere new, seen from
where the rest of us are standing. No book, no heart, no envelope, no card. Source of truth is
`brand/sendoff-icon.svg`; the SwiftUI version is `PathMark` and shares its geometry.

Usage: app icon, the home header, the final "Kept for you" screen, the web page footer. The
Path is the brand. The marks below are the product's furniture and take the theme's colors.

## The marks

- **The Seal**: a circle with the recipient's initial, slightly irregular edge, in the theme's
  seal color. Used on the envelope, as the app icon motif, and as the "Add yours" button
  background. Breaking the seal is the reveal gesture.
- **The Flap**: a shallow triangle that lifts. Used for the envelope and for expandable
  sections.
- **The Stamp**: a dashed-border rectangle with the occasion name in small caps. Marks
  occasion chips and entry headers ("From Dana · Your 2019 intern").
- **The Ribbon**: a thin band that wraps the cover of a Sendoff. Carries the count:
  "47 people".

## Themes

A theme is a `SendoffTheme`: paper, ink, muted ink, seal color, a secondary accent, a paper
texture hint, type pairing, a corner radius, a motion style and a music default. Themes are
data, not code, so premium ones can ship without an app update.

### Included (3)

| Theme | Paper | Ink | Seal | Feel | Default occasion |
|---|---|---|---|---|---|
| **Letterpress** | Warm cream `#F4EFE6` | Near-black `#1F1D1A` | Vermilion `#C8442B` | A hand-printed program. Deckled edges, generous margins. | New job, Farewell |
| **Midnight Toast** | Deep navy `#0F1B2D` | Ivory `#F2EBDD` | Antique gold `#C9A24A` | A dinner toast. Dark, warm, candle-lit. | Retirement |
| **Chalk** | Slate green `#2F4A3E` | Chalk white `#F7F3E8` | School yellow `#E9C46A` | A classroom board at the end of the year. | Teacher, Graduation |

### Premium (ship 3, add quarterly)

| Theme | Idea |
|---|---|
| **Gold Leaf** | Letterpress with animated foil: the seal color is a moving gradient that catches light on device tilt (CoreMotion). Retirement upsell. |
| **Darkroom** | Video-first. Letterboxed black, film grain, type in a condensed sans. For coaches and teams with lots of clips. |
| **Field Day** | End of season. Grass green paper, white chalk lines as dividers, numbers set like a jersey. |

## Type

| Role | iOS | Web |
|---|---|---|
| Display (recipient name, cover) | New York, Semibold, 40 to 56pt, tight tracking | Fraunces 600, optical size large |
| Entry body | New York, Regular, 19pt, 1.35 line height | Fraunces 400, 19 to 21px |
| Signature ("Dana") | New York Italic, 17pt | Fraunces Italic |
| UI | SF Pro Text, 15 to 17pt | Inter 15 to 16px |
| Stamp / small caps | SF Pro, 12pt, uppercase, +8% tracking | Inter 12px uppercase |

## Motion

- **Lift**: the envelope flap rotates on its top edge (rotation3DEffect, 0.6s, spring) when
  the seal is tapped. The seal "cracks": scales to 1.1 then fades.
- **Turn**: entries advance with a horizontal page turn with slight depth, 0.45s. Not a
  carousel snap.
- **Settle**: voice note waveform draws in from the left; photos drop in with a 2 degree
  rotation that settles to 0.
- Nothing bounces. Nothing is faster than 0.25s except taps.

## Sound

Music is part of the design. Each theme names a default stock track. Music ducks to 20% under a
voice note or video and recovers over 1.5s.

## Copy voice

Warm, plain, second person. Never corporate. No exclamation marks in system copy.
- "Add yours" not "Submit contribution".
- "Only Maria and Dan will see this." not "Private submission".
- "Sealed until Friday, June 12" not "Scheduled delivery".
- "Kept for you." on the final screen.

## Accessibility

- All type scales with Dynamic Type; display text caps at accessibility XL to protect layout.
- Every theme pair meets WCAG AA for body text (checked in `SendoffThemeTests`).
- Reduce Motion replaces lift and turn with crossfades.
- Voice notes get server-side transcripts so the recipient can read them.

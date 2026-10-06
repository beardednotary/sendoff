# Sendoff — Product

> A group keepsake for the moments people leave something behind: retirements, graduations,
> the last day of school, a move to a new job, the end of a season.

## App Store listing

| Field | Value | Limit |
|---|---|---|
| Name | `Memory Book & eCard - Sendoff` | 30 chars (29 used) |
| Subtitle | `Graduation, Retirement, Moving` | 30 chars (30 used) |
| On-device name (`CFBundleDisplayName`) | `Sendoff` | keep short for the home screen |
| Bundle ID | `com.dahvio.sendoff` | |
| Keywords (hypothesis) | `group card,farewell,retirement gift,teacher appreciation,goodbye card,memory book,kudoboard,ecard,graduation,voice note` | 100 chars |

The App Store name carries the search terms ("memory book", "ecard") while the brand sits at
the end. The subtitle carries the three highest-volume occasions. The home screen icon says
only "Sendoff". App Store Connect allows the two names to differ.

## The one-line pitch

**The card that gets passed around the office is broken.** It gets lost in someone's inbox tray,
half the team never sees it, and the people who do see it write "Good luck!!" because everyone
else will read what they wrote. Sendoff replaces it with a private, sealed, multimedia keepsake
that the recipient opens once, on the day, and keeps forever.

## Honest assessment of the idea

### What is strong

- **Moment-driven, high-emotion purchase.** Nobody price-shops a retirement gift for a colleague
  of 30 years. Willingness to pay is high and the purchase is rarely for yourself.
- **A built-in distribution loop.** Every Sendoff is sent to 10 to 200 contributors, each of whom
  experiences the product and then has their own retirement, graduation or teacher to thank.
  Kudoboard grew almost entirely on this loop.
- **Privacy is the real differentiator.** Every competitor (Kudoboard, GroupGreeting,
  GroupTogether, Punchbowl) is a *public board*. Everyone sees everyone's post, so posts become
  performative and short. "Only the recipient and the organizer will see this" changes what
  people write. This is the thesis of the product and should be on the landing page.
- **Voice notes are underrated.** Nobody else leads with them. Hearing a colleague's voice say
  "you were the reason I stayed" beats any photo. Low storage cost, high emotional yield.
- **The HR angle is a real business.** Companies run 20 to 200 of these a year. An unlimited
  annual plan for an HR or People team is recurring revenue with a champion inside the building.

### What to be careful about

1. **iOS-only cannot be the whole product.** The organizer can be on iPhone. The 60 contributors
   who get the link will not all be, and neither will the retiree opening it on a work laptop.
   **Decision:** the shared link and the recipient's link open generated web pages that carry the
   full experience on any device, including the sealed reveal. A QR code on a printed card points
   at the same page. The native iOS app is the organizer's tool and the premium home for
   recipients who have it (library, exports, Apple Music). An iOS **App Clip** gives iPhone
   contributors the native flow from the link without installing. See ARCHITECTURE.md.
2. **Approval is a burden if it is mandatory.** An organizer who has to approve 80 entries will
   stop. **Decision:** every Sendoff has a moderation mode: *Trust* (everything goes in, organizer
   can remove) or *Review* (organizer approves before the reveal). Default is Trust; HR accounts
   can default to Review.
3. **"Private" needs a precise definition or it will be broken by accident.**
   Contributors see only their own entry. The organizer sees everything (they are the editor).
   The recipient sees everything approved, at the reveal. Nobody else, ever. A contributor may
   optionally tick "others may see this" to opt in to a shared wall, but the default is private.
4. **Outside music is a licensing trap.** You cannot stream a Spotify or Apple Music track
   inside your app for a user who does not have that subscription. **Decision:** ship with
   licensed stock tracks (buy a perpetual royalty-free pack, 8 to 12 tracks). Premium "link your
   music" uses **MusicKit**: the recipient hears the full track if they are an Apple Music
   subscriber, otherwise a 30-second preview. Say so in the UI. Never host copyrighted audio.
5. **Video is your biggest cost line.** Cap video at 60 seconds and voice at 2 minutes, transcode
   server-side, and expire raw uploads. A 60-person Sendoff with video is still under 1 GB.
6. **The reveal is the product.** Most competitors treat "delivery" as sending a link. Sendoff
   should treat the reveal as an *event*: a sealed envelope, an open date, music, entries that
   unfold one at a time, then a keepsake that stays. Design and engineering budget should go
   here first.

### Positioning in one sentence

*Kudoboard is a bulletin board. Sendoff is a sealed envelope.*

## Who uses it

| Role | Who | Device | Needs |
|---|---|---|---|
| **Organizer** | The colleague, team lead, class parent or HR coordinator who sets it up | iPhone (app) or web | Create in under 3 minutes, share one link, see who has added, light moderation, schedule the reveal |
| **Contributor** | Anyone sent the link | Anything | Add a note, photo, voice note or video in under 2 minutes with no account and no app install required |
| **Recipient** | The person leaving | Any device via link or QR code (app optional) | A reveal that feels like a gift, then a keepsake they can revisit, export and keep |
| **Admin (HR)** | People/HR team on an org plan | Web + app | Unlimited Sendoffs, branding, roster, default moderation policy, billing |

## Occasions (launch set)

Each occasion seeds the copy, the default theme, the default music and the suggested prompts
that get shy contributors writing.

- **Retirement**: "What did they teach you?" "A moment you'll never forget."
- **New job / moving on**: "What will the next team be lucky to get?"
- **Graduation**: "Advice for what's next." "Proudest moment."
- **Thank a teacher** (end of year): "Something they said that stuck." Parents write for kids.
- **End of season** (coach): "Best game." "What you learned beyond the sport."
- **Military sendoff** (PCS, separation, retirement, change of command): "Best memory from the
  unit." "Something you taught us." Your Navy PRT and Army AFT apps already reach this audience;
  a unit sendoff is a natural cross-promotion.
- **Leaving a team** (relocation, reorg, layoff, sabbatical, end of contract). This is the
  occasion that quietly covers layoffs. Never say "layoff" in the product. The copy is
  *"When someone is leaving a team, give them something human to take with them."*

## Core flows

### Organizer: create (target under 3 minutes)
1. Pick the occasion.
2. Who is it for? Name, optional photo, their relationship to the group.
3. Pick a theme (3 included, more as premium).
4. Pick music (stock included, link your own as premium).
5. Set the reveal: *Open on a date* or *Open when I say*. Set a goal ("aim for 25 people"),
   which drives a progress bar on the dashboard and nudges the organizer to share again.
6. Moderation: Trust or Review.
7. Get the link. **No payment yet.** Creating and collecting are free.
8. Share sheet: link, QR code for a break room poster, pre-written message.

### Where the paywall sits
Never before anything exists. The organizer pays after entries have arrived and the thing has
emotional weight. Triggers, in order of strength:
- After the 5th entry: *"Maria's Sendoff is coming together. 5 people have added. Unlock it to
  remove the limit and open it on the day."*
- When the free entry cap (10) is reached.
- When the organizer taps *Preview the reveal*, *Export*, a premium theme, or *Link a song*.
The purchase line is **"Make this something they can keep,"** not "Upgrade to premium."

### Contributor: add (target under 2 minutes, no account)
1. Open link. See the recipient's name, the occasion, the close date, and the privacy promise:
   *"Only [Recipient] and [Organizer] will see this."*
2. Choose: write, photo(s), voice note, video. Can combine.
3. Prompts offered as chips to overcome blank-page shyness.
4. Sign with a name (and optional relationship: "Your 2019 intern").
5. Submit. Magic link to email so they can edit until the Sendoff closes.

### Organizer: tend
- Live count of entries against the goal, who has not added (if a roster was given), one-tap
  nudge with pre-written copy: *"Don't forget to add yours for Maria before Friday."*
- Review queue if in Review mode; hide/remove in Trust mode.
- Reorder entries, pin a "first" entry (usually the boss or the organizer).
- Change the reveal date, close early, add a cover message.

### Recipient: reveal
1. Receives their link (email, text, or a QR code inside a physical card) at the reveal time.
   The page shows a sealed envelope in the theme. One tap breaks the seal. Works on any device;
   the iOS app offers the same reveal plus a library and exports.
2. Cover: name, occasion, how many people, from whom, music starts.
3. Entries unfold one at a time with the theme's motion. Voice and video play inline.
4. End: "Kept for you." The Sendoff lives in their library forever. Export options.

### Slideshow mode (the party)
The reveal, auto-advancing, on a laptop plugged into the TV at the retirement lunch or the
graduation party. Each entry full screen with the music. Voice notes play aloud. This is the
web reveal page with `?mode=slideshow` and a timing control. Included in Plus.

### Keepsake exports (upsell)
- **Video montage** rendered server-side with the music (share to family).
- **Printed book** via print-on-demand partner (retirements especially). This is where the
  App Store name "Memory Book" becomes literal.
- **PDF** always included.

## Monetization

| Tier | Price (hypothesis) | What |
|---|---|---|
| Free | $0 | Create, share, collect up to 10 entries, basic preview with a "Made with Sendoff" line on the last page |
| Sendoff | $9.99 per Sendoff | Up to 100 entries, no footer, 3 included themes, stock music, scheduled reveal, PDF |
| Sendoff Plus | $19.99 per Sendoff | Unlimited entries, all premium themes, link your music, slideshow mode, video montage |
| Packs | $39 for 5, $69 for 10 | For office managers and team leads who do this often. Avoids subscription fatigue. |
| Org plan | from $499/yr | Unlimited Sendoffs for a company, branding, roster, Review default, admin seats, Stripe billing |
| Add-ons | $4.99 to $7.99 | Single premium theme, printed book (cost plus margin) |

The per-Sendoff purchase is the main one. Packs come second. The org plan is sold by hand to
begin with. Contributors and recipients never pay.

Anchors: Kudoboard charges $5.99 to $19.99 per board and sells business plans by seat.
Price slightly above because the product is a gift and the reveal is a better experience.

Pay once per Sendoff via **StoreKit 2** on iOS (consumables, and a subscription for Plus if
wanted). Org plans bill via Stripe on the web, outside the App Store, which Apple permits for
business purchases that the purchaser does not consume in-app.

## Kept from the earlier brainstorm

The ChatGPT thread that shaped the idea had several things worth keeping, now reflected above:
free-to-create with a late paywall; the "Make it something they can keep" purchase line; a goal
and progress bar for the organizer; military and "leaving a team" occasions; credit packs;
slideshow mode for parties; a printable QR sign; the positioning line *"Collect the words people
never get around to saying."* Two things it suggested that we deliberately do differently:
the final book is read one entry at a time rather than as a grid of cards (a grid is a board,
and the one-at-a-time reveal is the product), and the default moderation mode is Trust rather
than Review so organizers are not buried in approvals (org accounts can default to Review).

## Non-goals for v1

- No social feed, no discovery, no public Sendoffs.
- No Android native app (web contribution covers Android).
- No AI-generated messages. Prompts, yes. Writing for people, no. It undermines the point.
- No comments or reactions between contributors (that is a board; this is an envelope).

## Success metrics

- Organizer time-to-link under 3 minutes.
- Contributor completion rate above 70% of link opens.
- Share of contributions that include voice or video above 30% (proof the format works).
- Second Sendoff created by a former contributor within 90 days (the loop).

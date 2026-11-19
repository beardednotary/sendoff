import { Occasions } from '../lib/themes';
import type { Occasion } from '../lib/types';

// What the public pages say: one page per occasion and one for teams. render.ts turns this into
// HTML and the sitePages plugin in vite.config.ts writes it out at build time, so search engines
// and link previews get real pages with no script. Plain data, no DOM: it runs in Node at build
// time and in the browser (the landing page's footer reads the links).

export const Site = {
  origin: 'https://sendoffapp.com',
  email: 'support@sendoffapp.com',
  /** The name in App Store Connect. */
  appName: 'Sendoff - Group Memory Book',
  /** The live App Store listing, used by download links and Safari's Smart App Banner. */
  appStoreUrl: 'https://apps.apple.com/us/app/sendoff-group-memory-book/id6770213680',
  appStoreId: '6770213680',
};

export interface Faq { q: string; a: string }

/** One Sendoff, bought in the app by the organizer. US prices; App Store Connect is the source
 *  of truth (ios/Sendoff.storekit mirrors it), so change both together. */
export const PersonalPrices: { name: string; price: string; detail: string }[] = [
  { name: 'Free', price: '$0', detail: 'Up to 10 entries.' },
  { name: 'Sendoff', price: '$8.99', detail: 'Up to 100 entries.' },
  { name: 'Sendoff Plus', price: '$14.99', detail: 'Unlimited entries, every Plus look, and a song from Apple Music.' },
  { name: 'Pack of 5', price: '$34.99', detail: 'Five Sendoffs bought ahead, $7 each, for people who run a few a year.' },
  { name: 'Pack of 10', price: '$59.99', detail: 'Ten at $6 each, for the office manager who runs them all.' },
  { name: 'A Plus look', price: '$4.99', detail: 'Gold Leaf, Darkroom or Field Day, yours for every Sendoff.' },
];

export interface Tier {
  name: string;
  price: string;
  per?: string;
  size: string;
  detail: string;
  /** A Stripe Payment Link or Checkout URL for this tier. While it is unset the button writes to
   *  us instead; set it and the button buys the plan. */
  checkout?: string;
}

/** The annual plan for companies, schools and teams, sold here rather than in the app.
 *  Launch prices, set by the owner on 1 November 2026. */
export const Tiers: Tier[] = [
  { name: 'Team', price: '$169', per: 'a year', size: 'Up to 50 people', detail: 'A department, a school, a club or a unit.' },
  { name: 'Organization', price: '$399', per: 'a year', size: 'Up to 500 people', detail: 'A company, a district or a large school.' },
  { name: 'Larger', price: 'Custom', size: 'More than 500 people', detail: 'Several sites or brands under one plan.' },
];

export const TeamIncludes: [string, string][] = [
  ['Unlimited Sendoffs at the Plus level', 'Unlimited entries in each one, every Plus look, and a song from Apple Music.'],
  ['Your logo on the cover', 'Every Sendoff your team starts carries your name and logo.'],
  ['A roster', 'Anyone on it can start a Sendoff from the iPhone app, with nothing to buy or expense.'],
  ['Admins', 'They see every Sendoff your team has running and who started it. What people wrote stays between the organizer and the person it is for.'],
  ['Review mode by default', 'Organizers approve each entry before the day. They can switch a Sendoff to Trust when they would rather not.'],
  ['One invoice a year', 'Paid by your finance team, not put on someone’s card.'],
];

export const TeamFaq: Faq[] = [
  { q: 'Who counts toward the team size?',
    a: 'The people on your roster, who can start a Sendoff. Everyone who adds to one, and the person it is for, is free and never counted.' },
  { q: 'Can we try it first?',
    a: 'Yes. Anyone can start a Sendoff free with up to 10 entries and see it through to the day before you write to us.' },
  { q: 'How does billing work?',
    a: 'We send an invoice for the year. There is nothing to buy in the app: once your roster is set up, people on it start Sendoffs at the Plus level.' },
  { q: 'Can admins read what people wrote?',
    a: 'No. Admins see which Sendoffs are running and who started them. The entries are read only by the organizer and the person it is for, the same as on any Sendoff.' },
  { q: 'Does everyone need an iPhone?',
    a: 'Only the organizer, who starts it in the iPhone app. Everyone else adds from a link in any browser, with no account, and the person it is for opens it on any phone or computer.' },
];

export interface OccasionPage {
  path: string;
  occasion: Occasion;
  /** Short name for links. */
  label: string;
  /** One line for its card on the homepage. */
  teaser: string;
  title: string;
  description: string;
  eyebrow: string;
  headline: [string, string];
  lede: string;
  /** Their cover, the first thing the person it is for sees once the seal opens. */
  cover: Cover;
  story: { heading: string; paragraphs: string[] }[];
  faq: Faq;
}

/** A cover drawn as the app draws it. `photo` names a picture in public/site/photos (640 by 800
 *  and half that), cut from Unsplash under its free licence; the source is noted beside each. */
export interface Cover { photo: string; alt: string; name: string; from: string; message: string; mark?: string }

/** Screens from the iOS app (design/v2/app, made with the mock store), in public/site/app at 480
 *  by 1044 and half that. Alt text says what each shows. */
export const Screens = {
  create: 'The Sendoff app asking “Who are we sending off?”, with a place for their photo, their name and who it is from.',
  share: 'The share screen: a QR code and a link for Jo, with Share link and Save QR buttons.',
  contribute: 'Adding to a Sendoff: “Write something only Jo will read”, with prompts, and Photo, Voice and Video buttons.',
  sealed: 'A sealed Sendoff for Maria Reyes: her photo blurred behind the seal, and “Press and hold the seal”.',
  note: 'A written entry, opened: a note to Maria from her manager, Dan Okafor.',
  voice: 'A voice note, opened: a waveform, a play button and the words “you were the only one who learned my kids’ names.”',
  photo: 'A photo entry, opened: the Wednesday lunch crew around a long table.',
} as const;
export type Screen = keyof typeof Screens;

/** The same four steps on every occasion page, each beside its screen. */
export const Steps: [name: string, detail: string, screen: Screen][] = [
  ['Start it in the app', 'Who it is for, a photo if you like, and when it opens: on a date, or when you say. It takes a couple of minutes on iPhone.', 'create'],
  ['Share one link', 'Send it wherever your group talks, or print the QR card for the break room or the inside of a real card.', 'share'],
  ['Everyone adds privately', 'A note, photos, a voice note or a video, from any phone or computer. No account, no app.', 'contribute'],
  ['They open it on the day', 'It stays sealed until then. They press and hold the seal, and the entries open one at a time.', 'sealed'],
];

/** What an entry can hold, each shown as it opens. */
export const Entries: [name: string, detail: string, screen: Screen][] = [
  ['A note', 'Written for one reader, not the room.', 'note'],
  ['A voice note', 'Up to two minutes. The part people replay.', 'voice'],
  ['Photos and video', 'Up to six photos with each entry, or a minute of video.', 'photo'],
];

/** Questions every occasion page answers, after its own. */
export const CommonFaq: Faq[] = [
  { q: 'Does everyone need the app?',
    a: 'No. Only the organizer uses the iPhone app, to start it and share the link. Everyone else adds from the link or a QR code in any browser, with no account. The person it is for opens it on any phone or computer.' },
  { q: 'Who can read what people write?',
    a: 'Only the person it is for and the organizer. People who add cannot read each other’s entries unless they choose to share theirs with the others who added.' },
  { q: 'What does it cost?',
    a: 'Starting one and collecting up to 10 entries is free. Sendoff ($8.99) holds up to 100 entries, and Sendoff Plus ($14.99) has no limit, every Plus look and a song from Apple Music. The organizer pays once, in the app; nobody who adds to it or opens it pays.' },
  { q: 'Can they keep it?',
    a: 'Yes. After the day it stays theirs to come back to, and they can print it or save it as a PDF, on every plan.' },
];

/** Said wherever Plus's song is, because a song is not always the whole song. */
export const SongNote = 'The song plays in full in the app for Apple Music subscribers, and as a 30-second preview everywhere else.';

export const OccasionPages: OccasionPage[] = [
  {
    path: '/retirement',
    teaser: 'A career’s worth of thank‑yous.',
    occasion: 'retirement',
    label: 'Retirement',
    title: 'Group retirement card and memory book · Sendoff',
    description: 'A group retirement card, sealed until their last day. Colleagues add notes, photos, voice notes and video privately, and they keep it for good.',
    eyebrow: 'Retirement',
    headline: ['Everyone’s thank-you,', 'sealed until the last day.'],
    lede: 'The card that goes round the office reaches half the building, and most of it says “Enjoy it!” Sendoff gathers what people actually want to say, from everyone who worked with them, and keeps it sealed until the day they leave.',
    // The app's demo photo for Maria (src/lib/mock.ts), so the cover matches the screens.
    cover: { photo: 'retirement', alt: 'Maria Reyes, sitting by a window in a patterned blouse.', name: 'Maria Reyes', from: 'From the whole fourth floor', message: 'Thirty-one years. We tried to fit it in here.' },
    story: [
      { heading: 'Everyone who worked with them', paragraphs: [
        'A retirement reaches further than the current team. Send the link to the people who trained them, the ones who moved on years ago, the client who always asked for them by name. They add from any phone or computer, with no account and no app.',
        'Hearing a voice is different. A voice note from the person who hired them in 1994 does what a signature cannot; so does a photo from the old office, or a minute of video from the team overseas.',
      ] },
      { heading: 'On the day', paragraphs: [
        'They press and hold the seal, and the entries open one at a time: each note, photo, voice and video on its own, not a wall of posts to scroll past. Open it together at the leaving lunch on a laptop, or let them read it alone that evening.',
      ] },
    ],
    faq: { q: 'When should we start one?',
      a: 'Two or three weeks before the last day gives people time to find a photo or record something. Set it to open on the day, or open it yourself when the moment comes.' },
  },
  {
    path: '/graduation',
    teaser: 'Advice for what’s next.',
    occasion: 'graduation',
    label: 'Graduation',
    title: 'Graduation memory book from family and friends · Sendoff',
    description: 'A sealed graduation gift from everyone who got them there. Family, teachers and friends add notes, photos, voice notes and video; it opens on the day.',
    eyebrow: 'Graduation',
    headline: ['Advice for what’s next,', 'from everyone behind them.'],
    lede: 'Grandparents three states away, the fourth-grade teacher, the coach, the friends they are about to leave behind. Each adds something privately, and the graduate opens it all on graduation day.',
    // Cole Keister, unsplash.com/photos/SRs7zDrj150
    cover: { photo: 'graduation', alt: 'Jordan in a black gown with a green hood, smiling, outdoors.', name: 'Jordan Ellis', from: 'From your family and friends', message: 'For the next chapter, from everyone who saw this one.' },
    story: [
      { heading: 'Before everyone scatters', paragraphs: [
        'Graduation sends people in every direction. Sendoff gathers them first: one link, sent to the family group chat and old teachers alike, and everyone adds a note, photos, a voice note or a minute of video from wherever they are.',
        'Grandparents who would rather talk than type can record a voice note. Friends can add the photos only they have.',
      ] },
      { heading: 'Something to take with them', paragraphs: [
        'They open it once, on the day, one entry at a time. Then it goes with them to the first apartment, the first job, the hard week in the second semester.',
      ] },
    ],
    faq: { q: 'Who usually starts one?',
      a: 'A parent, most often; sometimes a sibling, a teacher or a coach. Whoever starts it uses the iPhone app, and everyone else just needs the link.' },
  },
  {
    path: '/farewell',
    teaser: 'For a colleague moving on.',
    occasion: 'farewell',
    label: 'Leaving a job',
    title: 'Farewell card for a colleague who is leaving · Sendoff',
    description: 'A goodbye card from the whole team, sealed until their last day. Colleagues add notes, photos, voice notes and video privately, from anywhere.',
    eyebrow: 'Leaving a team',
    headline: ['Give them something', 'human to take with them.'],
    lede: 'A new job, a move, the end of a contract. The farewell thread scrolls away by Monday and the e-card gets signed “Good luck!!” forty times. Sendoff collects what people would say if no one else were reading, and keeps it sealed until the last day.',
    // The app's demo photo for Jo (src/lib/mock.ts), so the cover matches the screens.
    cover: { photo: 'farewell', alt: 'Jo in profile, wearing glasses, against green trees.', name: 'Jo Lindqvist', from: 'From the platform team', message: 'The standup will not be the same.' },
    story: [
      { heading: 'Written for one reader', paragraphs: [
        'On a shared board everyone reads everyone else, so people write for the room. In a Sendoff only the person leaving and the organizer read the entries. People who add cannot see each other’s unless they choose to, and what they write changes because of it.',
      ] },
      { heading: 'For teams that are not in one place', paragraphs: [
        'Remote and hybrid teams rarely get a leaving lunch. Post one link in the team channel; people add from a phone or laptop, across time zones, before the date you set.',
      ] },
    ],
    faq: { q: 'How quickly can we put one together?',
      a: 'Starting one takes a couple of minutes in the app. A few days is enough for most teams to add something. Set it to open on the last day, or open it yourself when the moment comes.' },
  },
  {
    path: '/teacher-appreciation',
    teaser: 'A year of thank‑yous from the class.',
    occasion: 'teacher',
    label: 'Teacher appreciation',
    title: 'Teacher appreciation gift from the whole class · Sendoff',
    description: 'A sealed thank-you for a teacher from the whole class. Parents and students add notes, photos, voice notes and video; it opens on the last day of school.',
    eyebrow: 'Teacher appreciation',
    headline: ['Thank a teacher', 'in their students’ words.'],
    lede: 'For Teacher Appreciation Week or the last day of school. A class parent starts it, every family adds something, and the teacher opens a year of thank-yous, one at a time.',
    // litoon dev, unsplash.com/photos/qF9e4EHGCVQ
    cover: { photo: 'teacher', alt: 'Mr. Patel, smiling, in his classroom with the children’s paintings behind him.', name: 'Mr. Patel', from: 'From Room 14 and their families', message: 'You made the hard days easy to come back to.' },
    story: [
      { heading: 'Easy for every family', paragraphs: [
        'Send one link in the class group chat, or print the QR card for the classroom door. Parents add from their phone in a couple of minutes, with no account and no app.',
        'Younger children can draw something for a parent to photograph, or say their thank-you as a voice note or a short video. It is the part teachers tend to replay.',
      ] },
      { heading: 'Better than another mug', paragraphs: [
        'Teachers keep the notes they are given. Sendoff keeps them in one place: sealed until the day, then theirs to come back to.',
      ] },
    ],
    faq: { q: 'Can children add to it?',
      a: 'A parent or carer adds the entry on their child’s behalf; Sendoff is not meant for children under 13 to use on their own. Many record their child reading what they wrote.' },
  },
  {
    path: '/military',
    teaser: 'From the whole unit, wherever they are.',
    occasion: 'military',
    label: 'Military farewell',
    title: 'Military farewell gift from the unit · Sendoff',
    description: 'A sealed farewell from the whole unit for a PCS, retirement or change of command. Add notes, photos, voice notes and video from wherever you are stationed.',
    eyebrow: 'Military sendoff',
    headline: ['From the whole unit,', 'wherever everyone is now.'],
    lede: 'A PCS, a separation, a retirement, a change of command. The people who served with them are spread across bases and time zones. Sendoff gives them one link to add to, and keeps it sealed until the day.',
    // Glenn Guiao, unsplash.com/photos/fmRr6IvLbv8
    cover: { photo: 'military', alt: 'Chief Rivera saluting in a white dress cap, seen from behind.', name: 'Chief Rivera', from: 'From the whole command', message: 'Fair winds and following seas.' },
    story: [
      { heading: 'Everyone who served with them', paragraphs: [
        'Send the link to the current unit and the ones before it. People add from their phone in a couple of minutes: a note, photos from the field, a voice note, a short video.',
        'Families can add too. The spouse who held things together through a deployment often has the best words.',
      ] },
      { heading: 'Private by design', paragraphs: [
        'Only the person it is for and the organizer read the entries. Nothing is posted publicly, and the link is the only way in, so share it the way you would share the envelope itself.',
      ] },
    ],
    faq: { q: 'Can people add from overseas?',
      a: 'Yes. Anyone with the link and a connection can add, on any phone or computer, wherever they are stationed.' },
  },
  {
    path: '/season-end',
    teaser: 'Thank you, coach.',
    occasion: 'season_end',
    label: 'End of season',
    title: 'End of season gift for a coach from the team · Sendoff',
    description: 'A sealed thank-you for a coach from every player and parent. Add notes, photos, voice notes and video; it opens at the end-of-season party.',
    eyebrow: 'End of season',
    headline: ['Thank you, coach,', 'from the whole team.'],
    lede: 'The best game, the worst bus ride, the halftime talk nobody forgot. Players and parents add their part privately, and the coach opens it at the end-of-season party.',
    // Will Colavito, unsplash.com/photos/O78ytdEmicY
    cover: { photo: 'season-end', alt: 'Coach Dana on the sideline in a cap and team shirt.', name: 'Coach Dana', from: 'From the team and their families', message: 'You taught us more than the playbook.' },
    story: [
      { heading: 'Every player, not just the captains', paragraphs: [
        'Send one link to the team chat. Players record a voice note or a short video, parents add the photos from the sideline, and nobody needs an account or the app.',
        'Because no one reads anyone else’s entry, the quiet player at the end of the bench writes as much as the captain.',
      ] },
      { heading: 'At the party', paragraphs: [
        'Open it on a laptop at the end-of-season dinner, one entry at a time, or let the coach read it alone afterwards.',
      ] },
    ],
    faq: { q: 'Can younger players add?',
      a: 'A parent adds the entry on their child’s behalf; Sendoff is not meant for children under 13 to use on their own. A voice note or a short video of them saying it works well.' },
  },
];

/** The prompts the app offers for this occasion (src/lib/themes.ts), set with curly apostrophes. */
export function promptsFor(o: Occasion): string[] {
  return Occasions[o].prompts.map((t) => t.replace(/'/g, '’'));
}

export const TeamsPage = {
  path: '/teams',
  label: 'For teams',
  title: 'Sendoff for teams · Group farewell and retirement cards',
  description: 'An annual plan for companies, schools and teams: unlimited Sendoffs, your logo on the cover, admins, a roster and one invoice. Group cards that stay private.',
};

export const HomePage = {
  path: '/',
  title: 'Sendoff · Group card and memory book, sealed until the day',
  description: 'Everyone adds a note, photos, a voice note or a video privately. One person opens it, on the day. For retirements, graduations, farewells and thank-yous.',
};

/** Why it is different, on the homepage. Icons are from src/lib/dom.ts. */
export const Benefits: [icon: 'lock' | 'envelope' | 'voice' | 'link' | 'music' | 'download', name: string, detail: string][] = [
  ['lock', 'Private by design', 'Only the person it is for and the organizer read the entries, so people write what they mean, not what reads well to the room.'],
  ['envelope', 'Sealed until the day', 'It opens on the date you set, or when you say. Until then it is an envelope, not a board everyone scrolls.'],
  ['voice', 'Voices, not just signatures', 'A voice note or a minute of video carries what a signature cannot.'],
  ['link', 'Nothing to install', 'Everyone adds from one link or a QR code, in any browser, with no account.'],
  ['music', 'Opened like a letter', 'One entry at a time, with a song from Apple Music on Plus.'],
  ['download', 'Theirs to keep', 'They can come back to it, print it or save it as a PDF, on every plan.'],
];

/** The three plans on the homepage; the rest (packs, Plus looks on their own) are in PersonalPrices. */
export const PlanTeasers: { name: string; price: string; per?: string; size: string; detail: string }[] = [
  { name: 'Free', price: '$0', size: 'Up to 10 entries', detail: 'Start one and see it through.' },
  { name: 'Sendoff', price: '$8.99', per: 'once', size: 'Up to 100 entries', detail: 'Enough for most teams and families.' },
  { name: 'Sendoff Plus', price: '$14.99', per: 'once', size: 'Unlimited entries', detail: 'Every Plus look, and a song from Apple Music.' },
];

export const HomeFaq: Faq[] = [
  CommonFaq[0]!,
  CommonFaq[1]!,
  CommonFaq[2]!,
  { q: 'Does it work on Android?',
    a: 'Everyone who adds to a Sendoff, and the person it is for, can use any phone or computer with a browser. Starting one takes the iPhone app.' },
  CommonFaq[3]!,
  { q: 'When can I start one?',
    a: 'You can start one now. Download Sendoff from the App Store for iPhone. Companies and schools can write to us about a team plan.' },
];

/** Every page in the sitemap, in order. All of them are prerendered from src/site. */
export const PublicPaths: string[] = [HomePage.path, TeamsPage.path, ...OccasionPages.map((p) => p.path), '/support', '/privacy'];

/** The links in every page's footer. */
export const FooterLinks = {
  occasions: OccasionPages.map((p) => ({ href: p.path, label: p.label })),
  more: [
    { href: TeamsPage.path, label: TeamsPage.label },
    { href: '/support', label: 'Support' },
    { href: '/privacy', label: 'Privacy' },
  ],
};

import { Site } from './content';

// /privacy and /support: the two URLs App Store Connect asks for. The privacy text describes what
// the code actually does; keep it in step with supabase/migrations and the clients when either
// changes, and move the date with it.

export const InfoUpdated = '1 November 2026';

/** A paragraph, or a heading with its paragraphs. */
export type Block = string | [heading: string, ...paragraphs: string[]];

export interface InfoPage { path: string; title: string; description: string; lead: string; blocks: Block[] }

export const PrivacyPage: InfoPage = {
  path: '/privacy',
  title: 'Privacy · Sendoff',
  description: 'What Sendoff keeps, who can see it, and how to remove it. Entries are read only by the person a Sendoff is for and the person who started it.',
  lead: 'Sendoff exists to keep words private until the day they are opened. This is what we keep, who can see it, and how to remove it.',
  blocks: [
    ['What we keep',
      'If you start a Sendoff: the name and email Apple shares when you sign in with Apple (it can be a private relay address), and what you enter: who it is for, who it is from, a cover line, the occasion, dates and settings, an optional photo of the person, and a song if you link one.',
      'If you add to one: the name you sign with, how you know them if you say, what you write, and any photo, voice note or video you attach. Your browser or the app gets an anonymous sign-in so you can come back and change your entry; it is not linked to your name or email.',
      'If you open one: nothing beyond the fact that it was opened and when.',
      'If your organization arranges a team plan: the name and email of whoever arranges it, and the invoices we send.'],
    ['Who can see it',
      'Only the person who started the Sendoff and the person it is for can read the entries. People who add to it see only their own entry, unless they choose to let the others who added read theirs. On a team plan, admins see which Sendoffs are running and who started them, not what anyone wrote.',
      'Photos, voice notes and video are stored privately. They are shown through links that expire within a day, and only to the people above.',
      'Links carry long random keys. Anyone holding a link can do what that link allows (add an entry, or open the Sendoff), so share them the way you would share the envelope itself.'],
    ['What we do not do',
      'No advertising, no tracking across apps or sites, no analytics, no selling or sharing your data. Sendoff does not read your contacts or your photo library beyond the items you pick.'],
    ['Who stores it',
      'Entries, media and accounts are stored with Supabase, our database and storage provider. The website is served by Cloudflare. Both process data only to run Sendoff. Purchases in the app are handled entirely by Apple; we receive a record that a purchase happened, not your payment details.',
      'If the organizer links a song, it plays from Apple Music, so the device opening the Sendoff fetches the song, or its 30-second preview, from Apple.'],
    ['Reporting an entry',
      `If something in a Sendoff made for you should not be there, tap Report on the entry in the app, or write to ${Site.email}. We read every report ourselves, and nobody else is told who reported it.`],
    ['How long we keep it, and deleting it',
      'A Sendoff is kept until the person who started it deletes it, so the person it is for can come back to it. You can change or remove your own entry until the Sendoff is sealed. The organizer can hide or delete any entry at any time.',
      `To have a Sendoff, an entry or an account deleted, or to ask what we hold about you, write to ${Site.email}.`],
    ['Children',
      'Sendoff is not directed to children under 13 and they should not use it on their own. A parent or teacher can add an entry on a child’s behalf.'],
    ['Changes',
      'When this policy changes, the date at the top changes with it.'],
  ],
};

export const SupportPage: InfoPage = {
  path: '/support',
  title: 'Support · Sendoff',
  description: 'Help with adding to a Sendoff, opening one made for you, starting one, payments and reporting an entry.',
  lead: 'Sendoff is a sealed group keepsake: everyone adds privately, and one person opens it, on the day.',
  blocks: [
    ['Adding to a Sendoff',
      'Open the link or scan the QR code you were sent. No account and no app needed; on an iPhone it may open the Sendoff App Clip. Write something, add a photo, a voice note or a video if you like, sign it, and tap Add yours.',
      'You can come back to the same link on the same device to change or remove your entry until the Sendoff is sealed.'],
    ['Who can read what I wrote?',
      'The person it is for, and the person who started it. Nobody else who adds to it can read yours, unless you switch on “Let the others who added read mine too.”'],
    ['Opening one that is for you',
      'Use the link or QR code you were given; it is different from the one everyone else used. If it says Not yet, it opens on the date shown. When it is time, press and hold the seal.',
      'Every Sendoff can be printed or saved as a PDF afterwards, on every plan.'],
    ['Reporting an entry',
      `If something in a Sendoff made for you should not be there, tap Report on the entry in the app, or write to ${Site.email} with the link. Nobody else is told who reported it.`],
    ['Starting a Sendoff',
      'Organizers start one in the Sendoff iPhone app, signing in with Apple, then share its link. Free holds 10 entries. For more, the organizer pays once for that Sendoff: Sendoff ($8.99) holds up to 100 entries, and Sendoff Plus ($14.99) has no limit, every Plus look and a song from Apple Music. Nobody who adds to it or opens it ever pays.'],
    ['Payments and refunds',
      'Purchases in the app go through Apple. For a refund, use reportaproblem.apple.com, or write to us and we will help. Team plans for companies and schools are invoiced by us; write to us about those.'],
    ['Music',
      'The music that plays when a Sendoff opens is used under Creative Commons licenses. Thank you to the composers.',
      '“Home Was You”, “Simplicity” and “Victor Lux” by Scott Buckley, released under CC BY 4.0. scottbuckley.com.au',
      '“Acoustic Meditation” by Jason Shaw, audionautix.com, licensed under CC BY 3.0 US.',
      'A song an organizer links from Apple Music plays from Apple Music, under its own terms.'],
    ['Something not working?',
      `Write to ${Site.email} with the link you were using (you can leave out everything after the question mark) and what happened.`],
  ],
};

import { h, mount, svg, Icons, setTitle } from '../lib/dom';
import { applyTheme } from '../lib/themes';
import { footer } from './landing';

// /privacy and /support: the two URLs App Store Connect asks for. Plain reading pages in the
// visitor's light or dark setting. The privacy text describes what the code actually does; keep it
// in step with supabase/migrations and the clients when either changes.

const SUPPORT_EMAIL = 'support@sendoffapp.com';
const UPDATED = '30 October 2026';

type Block = string | [heading: string, ...paragraphs: string[]];

function page(title: string, lead: string, blocks: Block[]): void {
  const dark = matchMedia('(prefers-color-scheme: dark)');
  applyTheme(dark.matches ? 'midnight_toast' : 'letterpress');
  setTitle(`${title} · Sendoff`);
  mount(h('main', { class: 'page', style: 'padding-bottom:48px' },
    h('div', { style: 'height:52px; display:flex; align-items:center' }, h('a', { href: '/', 'aria-label': 'Sendoff home' }, svg(Icons.pathmark))),
    h('p', { class: 'eyebrow', style: 'margin-top:36px' }, `Updated ${UPDATED}`),
    h('h1', { class: 'display', style: 'margin-top:10px' }, title),
    h('p', { class: 'ui', style: 'margin-top:16px; color:var(--muted)' }, lead),
    ...blocks.map((b) => typeof b === 'string'
      ? h('p', { class: 'body', style: 'margin-top:14px' }, b)
      : h('section', { style: 'margin-top:32px' },
          h('h2', { class: 'name' }, b[0]),
          ...b.slice(1).map((p) => h('p', { class: 'body', style: 'margin-top:10px' }, p)))),
    h('p', { class: 'body', style: 'margin-top:32px' }, 'Questions: ', h('a', { href: `mailto:${SUPPORT_EMAIL}` }, SUPPORT_EMAIL), '.'),
    footer(),
  ));
}

export function privacyPage(): void {
  page('Privacy', 'Sendoff exists to keep words private until the day they are opened. This is what we keep, who can see it, and how to remove it.', [
    ['What we keep',
      'If you start a Sendoff: the name and details you enter (who it is for, who it is from, a cover line, the occasion, dates and settings), an optional photo of the person, and the account your iPhone signs in with.',
      'If you add to one: the name you sign with, how you know them if you say, what you write, and any photo, voice note or video you attach. Your browser or the app gets an anonymous sign-in so you can come back and change your entry; it is not linked to your name or email.',
      'If you open one: nothing beyond the fact that it was opened and when.'],
    ['Who can see it',
      'Only the person who started the Sendoff and the person it is for can read the entries. People who add to it see only their own entry, unless they choose to let the others who added read theirs.',
      'Photos, voice notes and video are stored privately. They are shown through links that expire within a day, and only to the people above.',
      'Links carry long random keys. Anyone holding a link can do what that link allows (add an entry, or open the Sendoff), so share them the way you would share the envelope itself.'],
    ['What we do not do',
      'No advertising, no tracking across apps or sites, no analytics, no selling or sharing your data. Sendoff does not read your contacts or your photo library beyond the items you pick.'],
    ['Who stores it',
      'Entries, media and accounts are stored with Supabase, our database and storage provider. The website is served by Netlify. Both process data only to run Sendoff. Purchases are handled entirely by Apple; we receive a record that a purchase happened, not your payment details.'],
    ['How long we keep it, and deleting it',
      'A Sendoff is kept until the person who started it deletes it, so the person it is for can come back to it. You can change or remove your own entry until the Sendoff is sealed. The organizer can hide or delete any entry at any time.',
      `To have a Sendoff, an entry or an account deleted, or to ask what we hold about you, write to ${SUPPORT_EMAIL}.`],
    ['Children',
      'Sendoff is not directed to children under 13 and they should not use it on their own. A parent or teacher can add an entry on a child’s behalf.'],
    ['Changes',
      'When this policy changes, the date at the top changes with it.'],
  ]);
}

export function supportPage(): void {
  page('Support', 'Sendoff is a sealed group keepsake: everyone adds privately, and one person opens it, on the day.', [
    ['Adding to a Sendoff',
      'Open the link or scan the QR code you were sent. No account and no app needed; on an iPhone it may open the Sendoff App Clip. Write something, add a photo, a voice note or a video if you like, sign it, and tap Add yours.',
      'You can come back to the same link on the same device to change or remove your entry until the Sendoff is sealed.'],
    ['Who can read what I wrote?',
      'The person it is for, and the person who started it. Nobody else who adds to it can read yours, unless you switch on “Let the others who added read mine too.”'],
    ['Opening one that is for you',
      'Use the link or QR code you were given; it is different from the one everyone else used. If it says Not yet, it opens on the date shown. When it is time, press and hold the seal.'],
    ['Starting a Sendoff',
      'Organizers start one in the Sendoff iPhone app, then share its link. Free holds 10 entries; a single upgrade for that Sendoff raises the limit and is paid once, by the organizer. Nobody who adds to it or opens it ever pays.'],
    ['Payments and refunds',
      'Purchases go through Apple. For a refund, use reportaproblem.apple.com, or write to us and we will help.'],
    ['Something not working?',
      `Write to ${SUPPORT_EMAIL} with the link you were using (you can leave out everything after the question mark) and what happened.`],
  ]);
}

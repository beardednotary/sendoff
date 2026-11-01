import QRCode from 'qrcode';
import { h, mount, svg, Icons, setTitle, toast, seal } from '../lib/dom';
import { getStore } from '../lib/store';
import { applyTheme, occasionTitle } from '../lib/themes';
import { longDate } from '../lib/format';
import { contributeLink } from '../lib/config';
import { StoreError, StoreMessages, firstName, initialOf, type PublicSendoff } from '../lib/types';
import { loadingView, errorView } from './shared';

// /s/{slug}/qr?t={token}  — a printable card for the break room, the party, or inside a real card.
// The QR encodes the contribute link (slug + token), the same one the organizer shares.

export async function qrPage(slug: string, token: string | null): Promise<void> {
  mount(loadingView());
  const store = await getStore();
  if (!token && !store.isMock) {
    mount(errorView('This link is missing its key.', 'Open the QR card from the share screen in the app so the code carries the right link.'));
    return;
  }
  let s: PublicSendoff;
  try {
    s = await store.publicSendoff(slug, token ?? '');
  } catch (e) {
    const err = e instanceof StoreError ? e : new StoreError('network', StoreMessages.network);
    mount(errorView("We couldn't find that Sendoff.", err.message));
    return;
  }
  applyTheme(s.themeId);
  setTitle(`QR card — Sendoff for ${s.recipientName}`);

  const link = contributeLink(slug, token);
  // Near-black on warm white in every theme: the code sits on its own tile so it always scans.
  const [screen, print] = await Promise.all([
    QRCode.toDataURL(link, { errorCorrectionLevel: 'M', margin: 0, scale: 10, color: { dark: '#0E0E0D', light: '#F3F1EC' } }),
    QRCode.toDataURL(link, { errorCorrectionLevel: 'M', margin: 1, scale: 10, color: { dark: '#000000', light: '#ffffff' } }),
  ]);

  const img = h('img', { src: screen, alt: `QR code linking to ${link}` });
  // Swap to black-on-white for print.
  window.addEventListener('beforeprint', () => { img.src = print; });
  window.addEventListener('afterprint', () => { img.src = screen; });

  const first = firstName(s.recipientName);
  mount(h('main', { class: 'page' },
    h('div', { class: 'between no-print', style: 'margin-bottom:20px' },
      h('p', { class: 'eyebrow' }, 'QR card'),
      h('button', { class: 'btn small', onclick: () => window.print() }, svg(Icons.print), 'Print'),
    ),
    h('div', { class: 'qr-card' },
      seal(initialOf(s.recipientName), 48),
      h('p', { class: 'eyebrow', style: 'margin-top:8px' }, occasionTitle(s.occasion)),
      h('h1', { class: 'display' }, `A Sendoff for ${s.recipientName}`),
      s.fromLine && h('p', { class: 'body' }, s.fromLine),
      h('p', { class: 'body', style: 'max-width:36ch' }, `Add a note, a photo, a voice memo or a short video. Only ${first} and ${s.organizerName} will see what you add.`),
      h('div', { class: 'qr' }, img),
      h('div', { class: 'url' }, link.replace(/^https?:\/\//, '')),
      s.closesAt && h('p', { class: 'caption' }, `Please add yours by ${longDate(s.closesAt)}`),
      h('p', { class: 'caption print-only', style: 'margin-top:8px' }, 'Made with Sendoff'),
    ),
    h('div', { class: 'stack no-print', style: 'margin-top:16px' },
      h('div', { class: 'row', style: 'gap:10px' },
        h('button', { class: 'btn wide', style: 'flex:1', onclick: async () => { await navigator.clipboard.writeText(link); toast('Link copied'); } }, svg(Icons.copy), 'Copy link'),
        h('a', { class: 'btn wide', style: 'flex:1', href: print, download: `sendoff-${slug}-qr.png` }, svg(Icons.download), 'Save QR'),
      ),
      h('p', { class: 'caption', style: 'margin-top:6px' }, 'Tape it in the break room, put it on the table at the party, or tuck it inside a real card.'),
    ),
  ));
}

import QRCode from 'qrcode';
import { h, mount, svg, Icons, setTitle, toast } from '../lib/dom';
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
  const styles = getComputedStyle(document.documentElement);
  const ink = styles.getPropertyValue('--ink').trim() || '#1F1D1A';
  const paper = styles.getPropertyValue('--paper').trim() || '#F4EFE6';
  const [screen, print] = await Promise.all([
    QRCode.toDataURL(link, { errorCorrectionLevel: 'M', margin: 1, scale: 10, color: { dark: ink, light: paper } }),
    QRCode.toDataURL(link, { errorCorrectionLevel: 'M', margin: 1, scale: 10, color: { dark: '#000000', light: '#ffffff' } }),
  ]);

  const img = h('img', { src: screen, alt: `QR code linking to ${link}` });
  // Swap to black-on-white for print.
  window.addEventListener('beforeprint', () => { img.src = print; });
  window.addEventListener('afterprint', () => { img.src = screen; });

  const first = firstName(s.recipientName);
  mount(h('main', { class: 'page' },
    h('div', { class: 'between no-print', style: 'margin-bottom:24px' },
      h('span', { class: 'stamp' }, 'QR card'),
      h('button', { class: 'btn small quiet', onclick: () => window.print() }, svg(Icons.print), 'Print'),
    ),
    h('div', { class: 'qr-card' },
      h('div', { class: 'seal-mark', style: '--s:64px', 'aria-hidden': 'true' }, initialOf(s.recipientName)),
      h('span', { class: 'stamp' }, occasionTitle(s.occasion)),
      h('h1', { class: 'display' }, `A Sendoff for ${s.recipientName}`),
      s.fromLine && h('div', { class: 'signature' }, s.fromLine),
      h('p', { class: 'ui', style: 'margin:0; max-width:34ch' }, `Add a note, a photo, a voice memo or a short video. Only ${first} and ${s.organizerName} will see what you add.`),
      img,
      h('div', { class: 'url' }, link.replace(/^https?:\/\//, '')),
      s.closesAt && h('div', { class: 'caption' }, `Please add yours by ${longDate(s.closesAt)}`),
      h('div', { class: 'caption print-only', style: 'margin-top:8px' }, 'Made with Sendoff'),
    ),
    h('div', { class: 'stack no-print', style: 'margin-top:20px' },
      h('button', { class: 'btn quiet', onclick: async () => { await navigator.clipboard.writeText(link); toast('Link copied'); } }, 'Copy the link'),
      h('a', { class: 'btn quiet', href: print, download: `sendoff-${slug}-qr.png` }, 'Download the code as PNG'),
      h('p', { class: 'caption center' }, 'Tape it in the break room, put it on the table at the party, or tuck it inside a real card.'),
    ),
  ));
}

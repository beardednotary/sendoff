import { h, mount, svg, Icons, setTitle } from '../lib/dom';
import { applyTheme } from '../lib/themes';
import { getStore } from '../lib/store';
import { FooterLinks, TeamsPage } from '../site/content';

// "/" — one screen. The product lives in the app and behind links; this is for the curious.
// Follows the visitor's light or dark setting, like the app: Evening in dark, Paper in light.

export async function landingPage(): Promise<void> {
  const dark = matchMedia('(prefers-color-scheme: dark)');
  applyTheme(dark.matches ? 'midnight_toast' : 'letterpress');
  dark.addEventListener('change', (e) => applyTheme(e.matches ? 'midnight_toast' : 'letterpress'));
  setTitle('Sendoff');
  const store = await getStore();
  mount(h('main', { class: 'hero' },
    h('div', { class: 'between', style: 'height:52px' }, svg(Icons.pathmark),
      h('nav', { class: 'site-nav', 'aria-label': 'Sendoff' }, h('a', { href: TeamsPage.path }, TeamsPage.label))),
    h('div', { class: 'lead' },
      h('p', { class: 'eyebrow' }, 'Sendoff'),
      h('h1', { class: 'display' }, 'Everyone adds privately.', h('br'), 'One person opens it, on the day.'),
      h('p', { class: 'body', style: 'max-width:40ch' },
        'A sealed group keepsake for retirements, graduations and goodbyes. The card passed around the office gets lost; this stays sealed until the day, and only they read it.'),
      h('p', { class: 'ui', style: 'margin-top:8px' }, 'Coming soon to the App Store.'),
      h('p', { class: 'caption' }, 'Organizers start one in the iPhone app. Everyone else just needs the link.'),
    ),
    store.isMock && h('section', { style: 'margin-top:48px' },
      h('p', { class: 'eyebrow' }, 'Demo, no backend configured'),
      h('div', { class: 'demo-links' },
        h('a', { href: '/s/maria-r/open?k=demo' }, h('span', { class: 'name' }, 'Maria Reyes'), h('span', { class: 'caption' }, 'The reveal')),
        h('a', { href: '/s/mr-patel/open?k=demo' }, h('span', { class: 'name' }, 'Mr. Patel'), h('span', { class: 'caption' }, 'Sealed, counting down')),
        h('a', { href: '/s/jo-moves?t=demo' }, h('span', { class: 'name' }, 'Jo Lindqvist'), h('span', { class: 'caption' }, 'Add yours')),
        h('a', { href: '/s/jo-moves/qr?t=demo' }, h('span', { class: 'name' }, 'Jo Lindqvist'), h('span', { class: 'caption' }, 'QR card')),
      ),
    ),
    footer(),
  ));
}

/** The same footer as the prerendered site pages (src/site/render.ts), so every page links to every other. */
export function footer(): HTMLElement {
  const links = (list: { href: string; label: string }[]) => h('ul', {}, list.map((a) => h('li', {}, h('a', { href: a.href }, a.label))));
  return h('footer', { class: 'site-foot caption' },
    h('nav', { 'aria-label': 'Occasions' }, links(FooterLinks.occasions)),
    h('nav', { 'aria-label': 'More' }, links(FooterLinks.more)),
    h('p', {}, `\u00A9 ${new Date().getFullYear()} Sendoff`),
  );
}

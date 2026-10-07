import { h, mount, svg, Icons, setTitle } from '../lib/dom';
import { applyTheme } from '../lib/themes';
import { getStore } from '../lib/store';

// "/" — one screen. The product lives in the app and behind links; this is for the curious.

export async function landingPage(): Promise<void> {
  applyTheme('letterpress');
  setTitle('Sendoff');
  const store = await getStore();
  mount(h('main', { class: 'hero' },
    svg(Icons.pathmark.replace('class="pathmark"', 'class="pathmark" style="--s:72px"')),
    h('h1', { class: 'display' }, 'Sendoff'),
    h('p', { class: 'ui muted', style: 'margin:0; max-width:36ch; justify-self:center' },
      'A private, sealed group keepsake for retirements, graduations and goodbyes. Everyone adds something. Only the person leaving sees it all.'),
    h('p', { class: 'signature' }, 'Kudoboard is a bulletin board. Sendoff is a sealed envelope.'),
    h('div', { class: 'stack', style: 'max-width:360px; width:100%; justify-self:center; margin-top:10px' },
      h('a', { class: 'btn', href: '#', onclick: (e: Event) => e.preventDefault() }, 'Get the iPhone app'),
      h('p', { class: 'caption center', style: 'margin:0' }, 'Organizers start one in the app. Everyone else just needs the link.'),
    ),
    store.isMock && h('div', { class: 'stack', style: 'max-width:420px; width:100%; justify-self:center; margin-top:30px' },
      h('div', { class: 'caption center' }, 'Demo (no backend configured)'),
      h('div', { class: 'demo-links' },
        h('a', { href: '/s/maria-r/open?k=demo' }, h('span', {}, 'Maria Reyes · the reveal'), h('span', { class: 'caption' }, 'opens now')),
        h('a', { href: '/s/mr-patel/open?k=demo' }, h('span', {}, 'Mr. Patel · sealed'), h('span', { class: 'caption' }, 'countdown')),
        h('a', { href: '/s/jo-moves?t=demo' }, h('span', {}, 'Jo Lindqvist · add yours'), h('span', { class: 'caption' }, 'contribute')),
        h('a', { href: '/s/jo-moves/qr?t=demo' }, h('span', {}, 'Jo Lindqvist · QR card'), h('span', { class: 'caption' }, 'print')),
      ),
    ),
  ));
}

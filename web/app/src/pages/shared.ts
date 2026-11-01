import { h, svg, Icons, seal } from '../lib/dom';

export function loadingView(): HTMLElement {
  const mark = seal('', 64);
  mark.setAttribute('aria-label', 'Loading');
  mark.removeAttribute('aria-hidden');
  return h('main', { class: 'page loading' }, mark);
}

export function errorView(title: string, detail: string): HTMLElement {
  return h('main', { class: 'page', style: 'min-height:100vh; min-height:100dvh; display:flex; flex-direction:column' },
    h('div', { style: 'height:52px; display:flex; align-items:center' }, svg(Icons.pathmark)),
    h('div', { style: 'margin-top:auto; margin-bottom:auto; display:grid; gap:12px' },
      h('h1', { class: 'display' }, title),
      h('p', { class: 'body', style: 'max-width:40ch' }, detail),
      h('p', { class: 'caption', style: 'margin-top:12px' }, h('a', { href: '/' }, 'What is Sendoff?')),
    ),
  );
}

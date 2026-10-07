import { h, svg, Icons } from '../lib/dom';

export function loadingView(): HTMLElement {
  return h('main', { class: 'page loading' }, h('div', { class: 'seal-mark', style: '--s:64px', 'aria-label': 'Loading' }, ''));
}

export function errorView(title: string, detail: string): HTMLElement {
  return h('main', { class: 'page stage active center', style: 'align-items:center' },
    svg(Icons.pathmark.replace('class="pathmark"', 'class="pathmark" style="--s:56px"')),
    h('h1', { class: 'title' }, title),
    h('p', { class: 'ui muted', style: 'margin:0; max-width:40ch' }, detail),
    h('p', { class: 'caption', style: 'margin-top:30px' }, h('a', { href: '/' }, 'What is Sendoff?')),
  );
}

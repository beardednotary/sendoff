// Tiny DOM helpers. No framework: three pages, each a few hundred lines.

type Child = Node | string | number | null | undefined | false | Child[];

type Props<K extends keyof HTMLElementTagNameMap> = Partial<Omit<HTMLElementTagNameMap[K], 'style' | 'children' | 'dataset'>> & {
  class?: string;
  style?: string | Partial<CSSStyleDeclaration>;
  dataset?: Record<string, string>;
  html?: string;
  for?: string;
  tabindex?: string;
  role?: string;
  [key: `aria-${string}`]: string | undefined;
  [key: `on${string}`]: ((e: Event) => void) | ((e: never) => void) | undefined;
};

export function h<K extends keyof HTMLElementTagNameMap>(tag: K, props?: Props<K> | null, ...children: Child[]): HTMLElementTagNameMap[K] {
  const el = document.createElement(tag);
  if (props) {
    for (const [k, v] of Object.entries(props)) {
      if (v == null || v === false) continue;
      if (k === 'class') el.className = v as string;
      else if (k === 'style') {
        if (typeof v === 'string') el.setAttribute('style', v);
        else Object.assign(el.style, v);
      } else if (k === 'dataset') Object.assign(el.dataset, v);
      else if (k === 'html') el.innerHTML = v as string;
      else if (k.startsWith('on') && typeof v === 'function') el.addEventListener(k.slice(2).toLowerCase(), v as EventListener);
      else if (k.startsWith('aria-') || k === 'role' || k === 'for' || k === 'tabindex') el.setAttribute(k, String(v));
      else if (k in el) (el as unknown as Record<string, unknown>)[k] = v;
      else el.setAttribute(k, String(v));
    }
  }
  append(el, children);
  return el;
}

export function append(el: Node, children: Child[]): void {
  for (const c of children) {
    if (c == null || c === false) continue;
    if (Array.isArray(c)) append(el, c);
    else if (c instanceof Node) el.appendChild(c);
    else el.appendChild(document.createTextNode(String(c)));
  }
}

export function svg(markup: string): SVGElement {
  const t = document.createElement('template');
  t.innerHTML = markup.trim();
  return t.content.firstElementChild as SVGElement;
}

export function clear(el: Element): void {
  while (el.firstChild) el.removeChild(el.firstChild);
}

export function mount(view: Node): void {
  const app = document.getElementById('app')!;
  clear(app);
  app.appendChild(view);
  window.scrollTo(0, 0);
}

let toastTimer: number | undefined;
export function toast(text: string): void {
  document.querySelector('.toast')?.remove();
  const t = h('div', { class: 'toast', role: 'status' }, text);
  document.body.appendChild(t);
  window.clearTimeout(toastTimer);
  toastTimer = window.setTimeout(() => t.remove(), 2200);
}

export function setTitle(title: string): void {
  document.title = title;
}

export const Icons = {
  close: '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round"><path d="M6 6l12 12M18 6L6 18"/></svg>',
  play: '<svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor"><path d="M7 5v14l12-7z"/></svg>',
  pause: '<svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor"><path d="M6 5h4v14H6zM14 5h4v14h-4z"/></svg>',
  photo: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"><rect x="3" y="5" width="18" height="14" rx="2"/><circle cx="9" cy="10" r="2"/><path d="M21 16l-5-5-9 8"/></svg>',
  voice: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"><path d="M4 12v2M8 8v8M12 5v14M16 9v6M20 11v2"/></svg>',
  video: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"><rect x="3" y="6" width="13" height="12" rx="2"/><path d="M16 10l5-3v10l-5-3z"/></svg>',
  lock: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M12 2a5 5 0 0 0-5 5v3H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-8a2 2 0 0 0-2-2h-1V7a5 5 0 0 0-5-5zm-3 5a3 3 0 0 1 6 0v3H9V7z"/></svg>',
  envelope: '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M3 7l9 6 9-6M4 5h16a1 1 0 0 1 1 1v12a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1z"/></svg>',
  music: '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/></svg>',
  musicOff: '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/><path d="M3 3l18 18"/></svg>',
  stop: '<svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor"><rect x="6" y="6" width="12" height="12" rx="2"/></svg>',
  mic: '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5 11a7 7 0 0 0 14 0M12 18v3"/></svg>',
  print: '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M6 9V3h12v6M6 18H4a2 2 0 0 1-2-2v-5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2h-2"/><rect x="6" y="14" width="12" height="7"/></svg>',
  pathmark: '<svg class="pathmark" viewBox="0 0 1024 1024" aria-label="Sendoff" role="img"><defs><linearGradient id="pm-sky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#1C2F52"/><stop offset="1" stop-color="#11213F"/></linearGradient><linearGradient id="pm-road" x1="0" y1="1" x2="1" y2="0"><stop offset="0" stop-color="#F4E9D6"/><stop offset="1" stop-color="#E8D5B6"/></linearGradient><linearGradient id="pm-gold" x1="0" y1="1" x2="1" y2="0"><stop offset="0" stop-color="#C9A24A"/><stop offset="1" stop-color="#E6CB85"/></linearGradient></defs><rect width="1024" height="1024" rx="228" fill="url(#pm-sky)"/><path fill="url(#pm-road)" d="M100 1024C190 850 480 800 585 680 680 570 590 475 470 405 395 360 430 290 610 232 720 197 820 170 905 148 845 190 760 220 690 248 560 302 575 350 650 392 820 480 830 630 720 740 630 830 625 920 650 1024Z"/><path fill="url(#pm-gold)" d="M100 1024C190 850 480 800 585 680 680 570 590 475 470 405 395 360 430 290 610 232 720 197 820 170 905 148 815 192 690 222 600 265 465 315 455 365 515 410 625 485 695 575 610 680 515 800 280 850 170 1024Z"/></svg>',
};

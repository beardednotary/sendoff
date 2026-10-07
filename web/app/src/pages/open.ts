import { h, mount, svg, Icons, setTitle, clear, toast } from '../lib/dom';
import { getStore } from '../lib/store';
import { applyTheme, occasionTitle } from '../lib/themes';
import { longDate, countdown, clock, plural } from '../lib/format';
import { MusicBed, Foreground } from '../lib/audio';
import { StoreError, StoreMessages, initialOf, signatureOf, type Contribution, type Media, type RevealSendoff } from '../lib/types';
import { loadingView, errorView } from './shared';

// /s/{slug}/open?k={recipient_key}  — the sealed envelope. The hero of the product.

type StageID = 'sealed' | 'cover' | 'entries' | 'kept';

export async function openPage(slug: string, key: string | null): Promise<void> {
  mount(loadingView());
  const store = await getStore();
  if (!key && !store.isMock) {
    mount(errorView('This link is missing its key.', 'The envelope only opens with the link or QR code you were given. Ask the person who made it to send it again.'));
    return;
  }
  let sendoff: RevealSendoff;
  try {
    sendoff = await store.reveal(slug, key ?? '');
  } catch (e) {
    const err = e instanceof StoreError ? e : new StoreError('network', StoreMessages.network);
    mount(errorView(err.code === 'network' ? 'Something went wrong.' : "We couldn't find that Sendoff.", err.message));
    return;
  }
  applyTheme(sendoff.themeId);
  setTitle(`A Sendoff for ${sendoff.recipientName}`);
  new Reveal(sendoff, slug, key ?? '').start();
}

class Reveal {
  private root = h('div');
  private stages: Record<StageID, HTMLElement>;
  private entries: Contribution[] = [];
  private idx = 0;
  private bed = new MusicBed();
  private fg = new Foreground(this.bed);
  private musicBtn = h('button', { class: 'iconbtn', 'aria-label': 'Music', 'aria-pressed': 'true', hidden: true, onclick: () => this.bed.toggle() }, svg(Icons.music));
  private countdownTimer: number | undefined;

  constructor(private s: RevealSendoff, private slug: string, private key: string) {
    this.stages = {
      sealed: this.sealedStage(),
      cover: this.coverStage(),
      entries: h('section', { class: 'stage entry-stage', id: 'entries' }),
      kept: this.keptStage(),
    };
    this.bed.onChange = (p) => {
      this.musicBtn.setAttribute('aria-pressed', String(p));
      clear(this.musicBtn); this.musicBtn.appendChild(svg(p ? Icons.music : Icons.musicOff));
    };
  }

  start(): void {
    const top = h('div', { class: 'topbar' },
      h('span', { class: 'stamp', hidden: !new URLSearchParams(location.search).has('preview') }, 'Preview'),
      h('div', { class: 'row' }, this.musicBtn),
    );
    this.root.append(top, this.stages.sealed, this.stages.cover, this.stages.entries, this.stages.kept);
    mount(this.root);
    this.go('sealed');
    void this.loadMusic();

    // Navigation: tap, swipe, keys
    this.stages.cover.addEventListener('click', () => this.advance());
    this.stages.entries.addEventListener('click', (e) => { if (!(e.target as HTMLElement).closest('button, a, video, audio, .photos')) this.advance(); });
    let x0: number | null = null;
    document.addEventListener('touchstart', (e) => { x0 = e.touches[0]?.clientX ?? null; }, { passive: true });
    document.addEventListener('touchend', (e) => {
      if (x0 == null) return;
      const dx = (e.changedTouches[0]?.clientX ?? x0) - x0; x0 = null;
      if (this.current() === 'sealed') return;
      if (dx < -60) this.advance(); else if (dx > 60) this.retreat();
    });
    document.addEventListener('keydown', (e) => {
      if (e.key !== 'ArrowRight' && e.key !== 'ArrowLeft') return;
      e.preventDefault();
      if (e.key === 'ArrowRight') this.advance(); else this.retreat();
    });
  }

  private async loadMusic(): Promise<void> {
    const track = await (await getStore()).track(this.s.musicTrackId);
    this.bed.load(track?.url ?? null);
    this.musicBtn.hidden = !this.bed.available;
  }

  private current(): StageID {
    return (this.root.querySelector('.stage.active')?.id as StageID | undefined) ?? 'sealed';
  }

  private go(id: StageID): void {
    for (const el of Object.values(this.stages)) { el.classList.remove('active'); void el.offsetWidth; }
    this.stages[id].classList.add('active');
    window.scrollTo(0, 0);
    if (id !== 'entries') this.fg.stopAll();
  }

  // MARK: Sealed

  private get isDue(): boolean {
    const { s } = this;
    if (s.state === 'open') return true;
    return s.reveal === 'on_date' && s.opensAt != null && s.opensAt.getTime() <= Date.now();
  }

  private sealedStage(): HTMLElement {
    const { s } = this;
    const count = plural(s.contributorCount, 'person', 'people');
    const envelope = h('div', {
      class: 'envelope', role: 'button', tabindex: '0',
      'aria-label': `Sealed envelope for ${s.recipientName} from ${count}. ${this.isDue ? 'Tap to open.' : 'Not yet.'}`,
    },
      h('div', { class: 'body' }),
      h('div', { class: 'address' },
        h('div', { class: 'caption' }, 'To'),
        h('div', { class: 'display', style: 'font-size:clamp(26px,6vw,34px)' }, s.recipientName),
        s.fromLine && h('div', { class: 'signature' }, s.fromLine),
      ),
      h('div', { class: 'flap' }),
      h('div', { class: 'seal-mark' }, initialOf(s.recipientName)),
      s.contributorCount > 0 && h('div', { class: 'ribbon' }, h('span', {}, count), h('i')),
    );
    const hint = h('p', { class: 'ui center muted', style: 'margin:0' });
    const under = h('div', { class: 'stack center', style: 'justify-items:center' });

    const breakSeal = async () => {
      if (envelope.classList.contains('open')) return;
      if (!this.isDue) {
        envelope.classList.remove('shake'); void envelope.offsetWidth; envelope.classList.add('shake');
        return;
      }
      envelope.classList.add('open');
      void this.bed.play();
      try {
        const store = await getStore();
        const [opened, entries] = await Promise.all([store.open(this.slug, this.key), store.revealContributions(this.slug, this.key)]);
        this.s = opened;
        this.entries = entries;
        this.refreshCounts();
        window.setTimeout(() => this.go('cover'), 700);
      } catch (e) {
        envelope.classList.remove('open');
        this.bed.pause();
        const err = e instanceof StoreError ? e : new StoreError('network', StoreMessages.network);
        toast(err.message);
      }
    };
    envelope.addEventListener('click', () => void breakSeal());
    envelope.addEventListener('keydown', (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); void breakSeal(); } });

    const render = () => {
      clear(under);
      if (this.isDue) {
        envelope.classList.remove('locked');
        hint.textContent = 'Tap the seal';
        window.clearInterval(this.countdownTimer);
      } else if (s.reveal === 'on_date' && s.opensAt) {
        envelope.classList.add('locked');
        hint.textContent = `Sealed until ${longDate(s.opensAt)}`;
        const cd = countdown(s.opensAt);
        under.appendChild(h('div', { class: 'countdown', 'aria-label': 'Time until it opens' },
          ...([['days', cd.days], ['hours', cd.hours], ['minutes', cd.minutes], ['seconds', cd.seconds]] as const)
            .filter(([u]) => u !== 'seconds' || cd.days === 0)
            .map(([u, n]) => h('div', {}, h('span', { class: 'n' }, String(n)), h('span', { class: 'caption' }, u))),
        ));
        under.appendChild(h('p', { class: 'caption', style: 'margin:0' }, `${plural(s.contributorCount, 'person has', 'people have')} added something. Keep this link.`));
      } else {
        envelope.classList.add('locked');
        hint.textContent = s.state === 'collecting' ? "It's still being filled." : "It's sealed.";
        under.appendChild(h('p', { class: 'caption', style: 'margin:0' }, `${s.organizerName} opens it when the time comes. Keep this link.`));
      }
    };
    render();
    if (!this.isDue && s.reveal === 'on_date' && s.opensAt) this.countdownTimer = window.setInterval(render, 1000);

    return h('section', { class: 'stage active', id: 'sealed' }, envelope, hint, under);
  }

  private refreshCounts(): void {
    const n = this.entries.length || this.s.contributorCount;
    for (const el of this.root.querySelectorAll('[data-count]')) el.textContent = plural(n, 'person', 'people');
  }

  // MARK: Cover

  private coverStage(): HTMLElement {
    const { s } = this;
    return h('section', { class: 'stage', id: 'cover' },
      h('span', { class: 'stamp' }, occasionTitle(s.occasion)),
      h('h1', { class: 'display', style: 'font-size:clamp(40px,10vw,56px)' }, s.recipientName),
      s.fromLine && h('div', { class: 'signature' }, s.fromLine),
      h('hr', { class: 'rule', style: 'margin:8px 0' }),
      s.coverMessage && h('p', { class: 'entry' }, s.coverMessage),
      h('div', { class: 'between', style: 'margin-top:40px' },
        h('div', { class: 'ribbon' }, h('span', { dataset: { count: '' } }, plural(s.contributorCount, 'person', 'people')), h('i')),
        h('span', { class: 'caption' }, 'Tap or swipe to begin'),
      ),
    );
  }

  // MARK: Entries

  private renderEntry(i: number): void {
    const e = this.entries[i];
    const host = this.stages.entries;
    clear(host);
    if (!e) return;
    this.fg.stopAll();

    const article = h('article', { class: 'entry-page' });
    const photos = e.media.filter((m) => m.kind === 'photo');
    const voice = e.media.find((m) => m.kind === 'voice');
    const video = e.media.find((m) => m.kind === 'video');

    if (video) article.appendChild(this.videoView(video));
    if (photos.length) article.appendChild(this.photoStack(photos));
    if (voice) article.appendChild(this.voiceView(voice));
    if (e.body) article.appendChild(h('p', { class: 'entry' }, e.body));
    article.appendChild(h('div', { class: 'sig' }, h('span', { class: 'signature' }, signatureOf(e))));

    host.append(
      h('div', { class: 'fill' }, article),
      h('div', { class: 'caption center' }, `${i + 1} of ${this.entries.length}`),
      h('div', { class: 'dots', 'aria-hidden': 'true' }, ...this.entries.map((_, d) => h('b', { class: d === i ? 'on' : '' }))),
    );
    if (!matchMedia('(prefers-reduced-motion: reduce)').matches && document.documentElement.dataset.motion !== 'fade') {
      article.animate([{ opacity: 0, transform: 'translateX(24px) rotateY(6deg)' }, { opacity: 1, transform: 'none' }], { duration: 450, easing: 'ease', fill: 'both' });
    }
  }

  private photoStack(photos: Media[]): HTMLElement {
    const stack = h('div', { class: 'photos', role: 'group', 'aria-label': plural(photos.length, 'photo') });
    let top = photos.length - 1;
    const place = () => {
      stack.querySelectorAll('img, .ph').forEach((el, p) => {
        const depth = (p - top + photos.length) % photos.length; // 0 is on top
        const r = (depth - 1) * 2.2, x = (depth - 1) * 6, y = depth * -4;
        (el as HTMLElement).style.cssText = `--r:${r}deg; --x:${x}px; --y:${y}px; z-index:${photos.length - depth}`;
      });
    };
    for (const m of photos) {
      const el = m.url
        ? h('img', { src: m.url, alt: '', loading: 'eager' })
        : h('div', { class: 'ph' }, svg(Icons.photo.replace('<svg', '<svg width="28" height="28"')));
      el.addEventListener('click', (ev) => {
        ev.stopPropagation();
        if (photos.length > 1) { top = (top + 1) % photos.length; place(); }
        else if (m.url) lightbox(m.url);
      });
      stack.appendChild(el);
    }
    if (photos.length > 1) stack.appendChild(h('span', { class: 'caption count' }, `${photos.length} photos · tap to shuffle`));
    place();
    return stack;
  }

  private voiceView(m: Media): HTMLElement {
    const bars: HTMLElement[] = [];
    let seed = 11;
    for (let b = 0; b < 36; b++) { seed = (seed * 9301 + 49297) % 233280; bars.push(h('b', { style: `--h:${25 + (seed / 233280) * 75}%` })); }
    const time = h('span', { class: 'caption time' }, clock(m.durationSeconds));
    const play = h('button', { class: 'play', 'aria-label': 'Play voice note' }, svg(Icons.play));
    const audio = m.url ? new Audio(m.url) : null;
    if (audio) this.fg.attach(audio);

    const setIcon = (playing: boolean) => { clear(play); play.appendChild(svg(playing ? Icons.pause : Icons.play)); play.setAttribute('aria-label', playing ? 'Pause voice note' : 'Play voice note'); };
    const paint = (fraction: number) => bars.forEach((b, i) => b.classList.toggle('on', i / bars.length < fraction));

    let simTimer: number | undefined;
    play.addEventListener('click', (e) => {
      e.stopPropagation();
      if (audio) {
        if (audio.paused) void audio.play(); else audio.pause();
      } else {
        // No file (mock or still processing): animate the waveform over the stated duration.
        const dur = (m.durationSeconds ?? 30) * 1000;
        if (simTimer) { window.clearInterval(simTimer); simTimer = undefined; setIcon(false); this.bed.recover(); return; }
        const start = performance.now(); setIcon(true); this.bed.duck();
        simTimer = window.setInterval(() => {
          const f = Math.min(1, (performance.now() - start) / dur);
          paint(f); time.textContent = clock((m.durationSeconds ?? 30) * f);
          if (f >= 1) { window.clearInterval(simTimer); simTimer = undefined; setIcon(false); this.bed.recover(); }
        }, 100);
      }
    });
    if (audio) {
      audio.addEventListener('play', () => setIcon(true));
      audio.addEventListener('pause', () => setIcon(false));
      audio.addEventListener('ended', () => { setIcon(false); paint(0); });
      audio.addEventListener('timeupdate', () => { if (audio.duration) { paint(audio.currentTime / audio.duration); time.textContent = clock(audio.currentTime); } });
    }

    return h('div', { class: 'voice' },
      h('div', { class: 'row' }, play, h('div', { class: 'wave', 'aria-hidden': 'true' }, ...bars), time),
      m.transcript && h('div', { class: 'caption' }, m.transcript),
      !m.url && m.status !== 'ready' && h('div', { class: 'caption' }, 'Still processing. Check back in a minute.'),
    );
  }

  private videoView(m: Media): HTMLElement {
    const box = h('div', { class: 'video' });
    if (m.url) {
      const v = h('video', { src: m.url, playsInline: true, preload: 'metadata', controls: true, poster: m.posterUrl ?? undefined });
      this.fg.attach(v);
      box.appendChild(v);
    } else {
      box.appendChild(h('div', { class: 'ph', style: m.posterUrl ? `background:url(${m.posterUrl}) center/cover` : '' },
        h('div', { class: 'stack center', style: 'justify-items:center; gap:6px' },
          svg(Icons.video.replace('<svg', '<svg width="32" height="32"')),
          h('span', { class: 'caption', style: 'color:#ddd' }, m.status === 'ready' ? `Video · ${clock(m.durationSeconds)}` : 'Still processing'))));
    }
    return box;
  }

  // MARK: Kept

  private keptStage(): HTMLElement {
    const { s } = this;
    const footer = s.plan === 'free' ? h('p', { class: 'caption', style: 'margin-top:30px; opacity:.7' }, 'Made with Sendoff') : null;
    return h('section', { class: 'stage center', id: 'kept', style: 'align-items:center' },
      svg(Icons.pathmark.replace('class="pathmark"', 'class="pathmark" style="--s:84px"')),
      h('h1', { class: 'display', style: 'font-size:40px' }, 'Kept for you.'),
      h('p', { class: 'ui muted', style: 'margin:0' }, h('span', { dataset: { count: '' } }, plural(s.contributorCount, 'person', 'people')), '. This stays here as long as you want it.'),
      h('div', { class: 'stack', style: 'width:100%; max-width:420px; margin-top:30px' },
        h('button', { class: 'btn', onclick: (e: Event) => { e.stopPropagation(); this.go('cover'); } }, 'Read it again'),
        h('button', { class: 'btn quiet', onclick: (e: Event) => { e.stopPropagation(); this.printKeepsake(); } }, 'Save as PDF'),
      ),
      h('p', { class: 'caption', style: 'margin-top:30px' }, `From ${s.organizerName} and everyone who added to it.`),
      footer,
    );
  }

  /** The browser's print dialog saves to PDF on every platform. A printable sheet of every entry. */
  private printKeepsake(): void {
    const sheet = h('div', { class: 'page print-only', id: 'keepsake' },
      h('h1', { class: 'display' }, `For ${this.s.recipientName}`),
      this.s.fromLine && h('div', { class: 'signature' }, this.s.fromLine),
      this.s.coverMessage && h('p', { class: 'entry' }, this.s.coverMessage),
      h('hr', { class: 'rule' }),
      ...this.entries.map((e) => h('article', { class: 'stack', style: 'margin:24px 0; break-inside:avoid' },
        ...e.media.filter((m) => m.kind === 'photo' && m.url).map((m) => h('img', { src: m.url!, alt: '', style: 'max-width:100%; max-height:300px; object-fit:contain' })),
        ...e.media.filter((m) => m.kind === 'voice' && m.transcript).map((m) => h('p', { class: 'entry', style: 'font-style:italic' }, `“${m.transcript}”`)),
        ...e.media.filter((m) => m.kind === 'video').map(() => h('p', { class: 'caption' }, `Video from ${e.authorName} (watch it at the link)`)),
        e.body && h('p', { class: 'entry' }, e.body),
        h('div', { class: 'signature' }, signatureOf(e)),
      )),
      h('p', { class: 'caption' }, `Opened ${longDate(new Date())}. Made with Sendoff.`),
    );
    document.body.appendChild(sheet);
    const cleanup = () => { sheet.remove(); window.removeEventListener('afterprint', cleanup); };
    window.addEventListener('afterprint', cleanup);
    window.print();
    window.setTimeout(cleanup, 60_000);
  }

  // MARK: Navigation

  private advance(): void {
    const cur = this.current();
    if (cur === 'cover') {
      if (!this.entries.length) { this.go('kept'); return; }
      this.idx = 0; this.renderEntry(0); this.go('entries');
    } else if (cur === 'entries') {
      if (this.idx + 1 < this.entries.length) this.renderEntry(++this.idx); else this.go('kept');
    }
  }

  private retreat(): void {
    const cur = this.current();
    if (cur === 'entries') { if (this.idx > 0) this.renderEntry(--this.idx); else this.go('cover'); }
    else if (cur === 'kept') {
      if (!this.entries.length) { this.go('cover'); return; }
      this.idx = this.entries.length - 1; this.renderEntry(this.idx); this.go('entries');
    }
  }
}

function lightbox(url: string): void {
  const box = h('div', { class: 'lightbox', role: 'dialog', 'aria-label': 'Photo', onclick: () => box.remove() }, h('img', { src: url, alt: '' }));
  document.body.appendChild(box);
  const esc = (e: KeyboardEvent) => { if (e.key === 'Escape') { box.remove(); document.removeEventListener('keydown', esc); } };
  document.addEventListener('keydown', esc);
}

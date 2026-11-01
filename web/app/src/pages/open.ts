import { h, mount, svg, Icons, setTitle, clear, toast, seal } from '../lib/dom';
import { getStore } from '../lib/store';
import { applyTheme, occasionTitle } from '../lib/themes';
import { longDate, countdown, clock, plural } from '../lib/format';
import { MusicBed, Foreground } from '../lib/audio';
import { StoreError, StoreMessages, initialOf, entrySize, type Contribution, type Media, type RevealSendoff } from '../lib/types';
import { loadingView, errorView } from './shared';

// /s/{slug}/open?k={recipient_key}  — the reveal. Their photo out of focus behind the seal; hold the
// seal and its ring draws closed, the photo comes into focus, and the cover rises. Then one entry
// per page, nothing around it. Same sequence as ios/Sendoff/Features/Reveal/RevealView.swift.

type StageID = 'sealed' | 'cover' | 'entries' | 'kept';

/** How long the seal is held before it opens (Motion.holdToOpen on iOS). */
const HOLD_MS = 1000;
/** How long their photo takes to settle from full screen into the cover's place. */
const SETTLE_MS = 900;

export async function openPage(slug: string, key: string | null): Promise<void> {
  mount(loadingView());
  const store = await getStore();
  if (!key && !store.isMock) {
    mount(errorView('This link is missing its key.', 'The Sendoff only opens with the link or QR code you were given. Ask the person who made it to send it again.'));
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
  private trackTitle: string | null = null;
  private musicBtn = h('button', { class: 'iconbtn', 'aria-label': 'Music', 'aria-pressed': 'true', hidden: true, onclick: () => this.bed.toggle() }, svg(Icons.music));
  private segments = h('div', { class: 'segments', 'aria-hidden': 'true', hidden: true });
  private count = h('span', { class: 'count' });
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
    const preview = new URLSearchParams(location.search).has('preview');
    const top = h('div', { class: 'topbar' },
      h('div', { class: 'inner' },
        this.segments,
        h('div', { class: 'between', style: 'min-height:44px' },
          preview ? h('span', { class: 'eyebrow' }, 'Preview') : this.count,
          this.musicBtn,
        ),
      ),
    );
    this.root.append(top, this.stages.sealed, this.stages.cover, this.stages.entries, this.stages.kept);
    mount(this.root);
    this.go('sealed');
    void this.loadMusic();

    // Navigation: tap, swipe, keys
    this.stages.cover.addEventListener('click', (e) => { if (!(e.target as HTMLElement).closest('a')) this.advance(); });
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
    const store = await getStore();
    const label = this.root.querySelector<HTMLElement>('[data-track]');
    // A linked song plays as Apple's 30-second preview and is credited to Apple Music, with a
    // link to the whole song. Without a preview it falls back to the stock track.
    const song = this.s.song;
    const preview = song ? await store.songPreview(this.slug, this.key) : null;
    if (song && preview?.previewUrl) {
      this.trackTitle = `${song.title} · ${song.artist}`;
      if (label) {
        label.hidden = false;
        label.lastChild!.textContent = `${this.trackTitle} · `;
        label.appendChild(preview.appleMusicUrl
          ? h('a', { href: preview.appleMusicUrl, target: '_blank', rel: 'noopener' }, 'Apple Music')
          : document.createTextNode('Apple Music'));
      }
      this.bed.load(preview.previewUrl);
    } else {
      const track = await store.track(this.s.musicTrackId);
      this.trackTitle = track?.title ?? null;
      if (label && this.trackTitle) { label.hidden = false; label.lastChild!.textContent = this.trackTitle; }
      this.bed.load(track?.url ?? null);
    }
    this.musicBtn.hidden = !this.bed.available;
  }

  private current(): StageID {
    return (this.root.querySelector('.stage.active')?.id as StageID | undefined) ?? 'sealed';
  }

  private go(id: StageID, fromSeal = false): void {
    for (const el of Object.values(this.stages)) { el.classList.remove('active'); void el.offsetWidth; }
    // Straight from the seal the photo is already in place; only the words come up.
    this.stages.cover.classList.toggle('from-seal', id === 'cover' && fromSeal);
    this.stages[id].classList.add('active');
    window.scrollTo(0, 0);
    if (id !== 'entries') this.fg.stopAll();
    // Over a photo the music button is glass; on paper it is a plain control.
    const onPhoto = this.s.recipientPhotoUrl != null && (id === 'sealed' || id === 'cover');
    this.musicBtn.classList.toggle('glass', onPhoto);
    this.segments.hidden = id !== 'entries';
    this.count.hidden = id !== 'entries';
  }

  // MARK: Sealed

  private get isDue(): boolean {
    const { s } = this;
    if (s.state === 'open') return true;
    return s.reveal === 'on_date' && s.opensAt != null && s.opensAt.getTime() <= Date.now();
  }

  private sealedStage(): HTMLElement {
    const { s } = this;
    const photo = s.recipientPhotoUrl;
    const mark = seal(initialOf(s.recipientName), 140, { ring: true });
    mark.setAttribute('role', 'button');
    mark.setAttribute('tabindex', '0');
    mark.removeAttribute('aria-hidden');
    mark.style.setProperty('--hold', `${HOLD_MS}ms`);
    const hint = h('p', { class: 'hint' });
    const under = h('div', { class: 'stack', style: 'justify-items:center' });
    const section = h('section', { class: `stage active${photo ? ' has-photo' : ''}`, id: 'sealed' },
      h('div', { class: 'backdrop', style: photo ? `background-image:url("${photo}")` : '' }),
      h('div', { class: 'inner' },
        h('div', { style: 'flex:1' }),
        mark,
        h('h1', { class: 'display for' }, `For ${s.recipientName}`),
        h('p', { class: 'body sub' }, [s.fromLine, s.contributorCount > 0 ? plural(s.contributorCount, 'person', 'people') : null].filter(Boolean).join(' · ')),
        under,
        h('div', { style: 'flex:1' }),
        hint,
      ),
    );

    let opening = false;
    const breakSeal = async () => {
      if (opening) return;
      if (!this.isDue) { refuse(); return; }
      opening = true;
      const started = performance.now();
      mark.classList.add('holding');
      section.classList.add('opening');
      navigator.vibrate?.(30);
      void this.bed.play();
      try {
        const store = await getStore();
        // In order: the entries are only readable once the server has flipped it open.
        this.s = await store.open(this.slug, this.key);
        this.entries = await store.revealContributions(this.slug, this.key);
        this.refreshCounts();
        // Let the blur lift, then settle their photo into the cover's place so the page never
        // cuts from the photo to bright paper.
        await pause(700 - (performance.now() - started));
        if (photo && !matchMedia('(prefers-reduced-motion: reduce)').matches) {
          section.classList.add('settling');
          await pause(SETTLE_MS);
        }
        this.go('cover', true);
      } catch (e) {
        opening = false;
        mark.classList.remove('holding');
        section.classList.remove('opening');
        this.bed.pause();
        const err = e instanceof StoreError ? e : new StoreError('network', StoreMessages.network);
        toast(err.message);
      }
    };
    const refuse = () => { section.classList.remove('shake'); void section.offsetWidth; section.classList.add('shake'); };

    // Press and hold. Letting go early unwinds the ring.
    let timer: number | undefined;
    const release = () => {
      if (timer === undefined) return;
      window.clearTimeout(timer); timer = undefined;
      if (!opening) { mark.classList.remove('holding'); render(); }
    };
    mark.addEventListener('pointerdown', (e) => {
      if (opening || timer !== undefined) return;
      if (!this.isDue) { refuse(); return; }
      mark.setPointerCapture?.(e.pointerId);
      mark.classList.add('holding');
      hint.textContent = 'Keep holding';
      navigator.vibrate?.(8);
      timer = window.setTimeout(() => { timer = undefined; void breakSeal(); }, HOLD_MS);
    });
    for (const ev of ['pointerup', 'pointercancel', 'lostpointercapture'] as const) mark.addEventListener(ev, release);
    // A release anywhere counts, in case the browser delivers it outside the seal.
    document.addEventListener('pointerup', release);
    mark.addEventListener('contextmenu', (e) => e.preventDefault());
    // Keyboard and screen readers open it in one step: a hold is not something they can do.
    mark.addEventListener('keydown', (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); void breakSeal(); } });
    mark.addEventListener('click', (e) => { if ((e as MouseEvent).detail === 0) void breakSeal(); });

    const render = () => {
      clear(under);
      mark.classList.toggle('locked', !this.isDue);
      if (this.isDue) {
        mark.setAttribute('aria-label', `Open the Sendoff for ${s.recipientName}`);
        hint.textContent = 'Press and hold the seal';
        window.clearInterval(this.countdownTimer);
      } else if (s.reveal === 'on_date' && s.opensAt) {
        mark.setAttribute('aria-label', `Sealed until ${longDate(s.opensAt)}`);
        hint.textContent = `Sealed until ${longDate(s.opensAt)}`;
        const cd = countdown(s.opensAt);
        under.appendChild(h('div', { class: 'countdown', 'aria-label': 'Time until it opens' },
          ...([['days', cd.days], ['hours', cd.hours], ['minutes', cd.minutes], ['seconds', cd.seconds]] as const)
            .filter(([u]) => u !== 'seconds' || cd.days === 0)
            .map(([u, n]) => h('div', {}, h('span', { class: 'n' }, String(n)), h('span', { class: 'caption' }, u))),
        ));
      } else {
        mark.setAttribute('aria-label', 'Not open yet');
        hint.textContent = s.state === 'collecting' ? "It's still being filled. Keep this link." : `${s.organizerName} opens it when the time comes. Keep this link.`;
      }
    };
    render();
    if (!this.isDue && s.reveal === 'on_date' && s.opensAt) this.countdownTimer = window.setInterval(render, 1000);
    return section;
  }

  private refreshCounts(): void {
    const n = this.entries.length || this.s.contributorCount;
    for (const el of this.root.querySelectorAll('[data-count]')) el.textContent = plural(n, 'person', 'people');
  }

  // MARK: Cover

  private coverStage(): HTMLElement {
    const { s } = this;
    return h('section', { class: 'stage', id: 'cover' },
      s.recipientPhotoUrl
        ? h('div', { class: 'photo', role: 'img', 'aria-label': `Photo of ${s.recipientName}`, style: `background-image:url("${s.recipientPhotoUrl}")` })
        : h('div', { class: 'noface' }, seal(initialOf(s.recipientName), 120)),
      h('div', { class: 'name-block' },
        h('p', { class: 'eyebrow', style: 'color:var(--muted)' }, occasionTitle(s.occasion)),
        h('h1', { class: 'display xl' }, s.recipientName),
        s.fromLine && h('p', { class: 'body' }, s.fromLine),
      ),
      s.coverMessage && h('p', { class: 'entry message' }, s.coverMessage),
      h('div', { class: 'between foot' },
        h('p', { class: 'caption row', style: 'gap:6px' },
          h('span', { dataset: { count: '' } }, plural(s.contributorCount, 'person', 'people')),
          h('span', { dataset: { track: '' }, hidden: true }, ' · ', ''),
        ),
        h('button', { class: 'btn small', type: 'button' }, 'Begin', svg(Icons.arrow)),
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

    clear(this.segments);
    this.segments.append(...this.entries.map((_, d) => h('b', { class: d <= i ? 'on' : '' })));
    this.count.textContent = `${i + 1} of ${this.entries.length}`;

    const article = h('article', { class: 'entry-page' });
    const photos = e.media.filter((m) => m.kind === 'photo');
    const voice = e.media.find((m) => m.kind === 'voice');
    const video = e.media.find((m) => m.kind === 'video');

    if (photos.length) article.appendChild(this.photoPager(photos));
    if (video) article.appendChild(this.videoView(video));
    if (voice) article.appendChild(this.voiceView(voice));
    if (e.body) article.appendChild(h('p', { class: `entry ${entrySize(e.body)}` }, e.body));
    article.appendChild(h('p', { class: 'sig' }, h('b', {}, e.authorName), e.authorRelationship && h('span', {}, `· ${e.authorRelationship}`)));

    host.append(article);
    if (!matchMedia('(prefers-reduced-motion: reduce)').matches && document.documentElement.dataset.motion !== 'fade') {
      article.animate([{ opacity: 0, transform: 'translateX(24px)' }, { opacity: 1, transform: 'none' }], { duration: 450, easing: 'cubic-bezier(.2,.8,.2,1)', fill: 'both' });
    }
  }

  /** One photo at a time, inset with rounded corners. Tap for the next. */
  private photoPager(photos: Media[]): HTMLElement {
    const box = h('div', { class: 'photos', role: 'group', 'aria-label': plural(photos.length, 'photo') });
    const dots = photos.length > 1 ? h('div', { class: 'pager', 'aria-hidden': 'true' }, ...photos.map(() => h('b'))) : null;
    let shown = 0;
    const show = (n: number) => {
      shown = n;
      box.querySelectorAll('img, .ph').forEach((el, p) => el.classList.toggle('on', p === n));
      dots?.querySelectorAll('b').forEach((el, p) => el.classList.toggle('on', p === n));
    };
    for (const m of photos) {
      box.appendChild(m.url
        ? h('img', { src: m.url, alt: '', loading: 'eager' })
        : h('div', { class: 'ph' }, svg(Icons.photo.replace('<svg', '<svg width="28" height="28"'))));
    }
    if (dots) box.appendChild(dots);
    box.addEventListener('click', (ev) => {
      ev.stopPropagation();
      if (photos.length > 1) show((shown + 1) % photos.length);
      else if (photos[0]?.url) lightbox(photos[0].url);
    });
    show(0);
    return box;
  }

  private voiceView(m: Media): HTMLElement {
    const bars: HTMLElement[] = [];
    let seed = 11;
    for (let b = 0; b < 44; b++) { seed = (seed * 9301 + 49297) % 233280; bars.push(h('b', { style: `--h:${18 + (seed / 233280) * 82}%` })); }
    const time = h('span', { class: 'body time' }, clock(m.durationSeconds));
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
      h('div', { class: 'wave', 'aria-hidden': 'true' }, ...bars),
      h('div', { class: 'controls' }, play, time),
      m.transcript && h('p', { class: `entry ${entrySize(m.transcript)}` }, `“${m.transcript}”`),
      !m.url && m.status !== 'ready' && h('p', { class: 'caption' }, 'Still processing. Check back in a minute.'),
    );
  }

  private videoView(m: Media): HTMLElement {
    const box = h('div', { class: 'video' });
    if (m.url) {
      const v = h('video', { src: m.url, playsInline: true, preload: 'metadata', controls: true, poster: m.posterUrl ?? undefined });
      this.fg.attach(v);
      box.appendChild(v);
    } else {
      box.appendChild(h('div', { class: 'ph', style: m.posterUrl ? `background-image:url("${m.posterUrl}")` : '' },
        h('div', { class: 'stack', style: 'justify-items:center; gap:10px' },
          h('div', { class: 'glass' }, svg(Icons.play.replace('width="16" height="16"', 'width="22" height="22"'))),
          m.status !== 'ready' && h('span', { class: 'caption', style: 'color:#fff' }, 'Still processing'))));
      if (m.durationSeconds) box.appendChild(h('span', { class: 'duration' }, clock(m.durationSeconds)));
    }
    return box;
  }

  // MARK: Kept

  private keptStage(): HTMLElement {
    const { s } = this;
    return h('section', { class: 'stage', id: 'kept' },
      h('div', { style: 'flex:1' }),
      seal(initialOf(s.recipientName), 96),
      h('h1', { class: 'display xl', style: 'margin-top:28px' }, 'Kept for you.'),
      h('p', { class: 'body', style: 'margin-top:12px' }, h('span', { dataset: { count: '' } }, plural(s.contributorCount, 'person', 'people')), ' wrote to you. This stays here as long as you want it.'),
      h('div', { style: 'flex:1' }),
      h('div', { class: 'stack' },
        h('button', { class: 'btn primary wide', onclick: (e: Event) => { e.stopPropagation(); this.go('cover'); } }, svg(Icons.replay), 'Read it again'),
        h('button', { class: 'btn wide', onclick: (e: Event) => { e.stopPropagation(); this.printKeepsake(); } }, svg(Icons.doc), 'Save as PDF'),
      ),
      h('p', { class: 'caption', style: 'margin-top:20px' }, `From ${s.organizerName} and everyone who added to it.${s.plan === 'free' ? ' Made with Sendoff.' : ''}`),
    );
  }

  /** The browser's print dialog saves to PDF on every platform. A printable sheet of every entry. */
  private printKeepsake(): void {
    const sheet = h('div', { class: 'page print-only', id: 'keepsake' },
      h('h1', { class: 'display' }, `For ${this.s.recipientName}`),
      this.s.fromLine && h('p', { class: 'body' }, this.s.fromLine),
      this.s.coverMessage && h('p', { class: 'entry' }, this.s.coverMessage),
      h('hr', { class: 'rule' }),
      ...this.entries.map((e) => h('article', { class: 'stack', style: 'margin:24px 0; break-inside:avoid' },
        ...e.media.filter((m) => m.kind === 'photo' && m.url).map((m) => h('img', { src: m.url!, alt: '', style: 'max-width:100%; max-height:300px; object-fit:contain' })),
        ...e.media.filter((m) => m.kind === 'voice' && m.transcript).map((m) => h('p', { class: 'entry' }, `“${m.transcript}”`)),
        ...e.media.filter((m) => m.kind === 'video').map(() => h('p', { class: 'caption' }, `Video from ${e.authorName} (watch it at the link)`)),
        e.body && h('p', { class: 'entry' }, e.body),
        h('p', { class: 'sig' }, h('b', {}, e.authorName), e.authorRelationship && h('span', {}, `· ${e.authorRelationship}`)),
      )),
      // Paid Sendoffs carry no Sendoff line, here or on the last page of the reveal.
      h('p', { class: 'caption' }, `Opened ${longDate(new Date())}.${this.s.plan === 'free' ? ' Made with Sendoff.' : ''}`),
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

function pause(ms: number): Promise<void> {
  return new Promise((resolve) => window.setTimeout(resolve, Math.max(0, ms)));
}

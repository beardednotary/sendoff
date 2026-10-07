import type { WebStore, Progress } from './store';
import {
  StoreError, StoreMessages, revealOrder,
  type Contribution, type ContributionDraft, type Media, type MusicTrack, type PublicSendoff, type RevealSendoff,
} from './types';
import { uuid } from './format';

// In-memory store seeded with the same three Sendoffs as ios MockStore. Any token or key is
// accepted. Lets the whole site run with no backend: /s/maria-r/open is the full reveal.

const day = 86_400_000;
const now = Date.now();

interface MockSendoff extends RevealSendoff { closesAt: Date | null; moderation: 'trust' | 'review' }

const MARIA: MockSendoff = {
  id: '11111111-1111-1111-1111-111111111111', slug: 'maria-r', recipientName: 'Maria Reyes', occasion: 'retirement',
  fromLine: 'From the whole fourth floor', coverMessage: 'Thirty-one years. We tried to fit it in here.',
  themeId: 'midnight_toast', musicTrackId: 'warm_piano', state: 'sealed', reveal: 'on_date',
  opensAt: new Date(now - 3_600_000), closesAt: new Date(now - 2 * day), organizerName: 'Dan Okafor',
  contributorCount: 6, plan: 'plus', moderation: 'trust',
};
const PATEL: MockSendoff = {
  id: '22222222-2222-2222-2222-222222222222', slug: 'mr-patel', recipientName: 'Mr. Patel', occasion: 'teacher',
  fromLine: 'Room 14', coverMessage: null, themeId: 'chalk', musicTrackId: 'reflective_guitar', state: 'sealed',
  reveal: 'on_date', opensAt: new Date(now + 5 * day + 3 * 3_600_000), closesAt: new Date(now + 3 * day),
  organizerName: 'Dan Okafor', contributorCount: 11, plan: 'single', moderation: 'review',
};
const JO: MockSendoff = {
  id: '33333333-3333-3333-3333-333333333333', slug: 'jo-moves', recipientName: 'Jo Lindqvist', occasion: 'new_job',
  fromLine: 'Platform team', coverMessage: null, themeId: 'letterpress', musicTrackId: 'bright_strings',
  state: 'collecting', reveal: 'manual', opensAt: null, closesAt: new Date(now + 9 * day),
  organizerName: 'Dan Okafor', contributorCount: 4, plan: 'single', moderation: 'trust',
};

function photo(w: number, h: number, hue: number, label: string): string {
  const s = `<svg xmlns='http://www.w3.org/2000/svg' width='${w}' height='${h}' viewBox='0 0 ${w} ${h}'>
    <defs><linearGradient id='g' x1='0' y1='0' x2='1' y2='1'><stop offset='0' stop-color='hsl(${hue},40%,70%)'/><stop offset='1' stop-color='hsl(${hue + 40},45%,45%)'/></linearGradient></defs>
    <rect width='${w}' height='${h}' fill='url(#g)'/>
    <circle cx='${w * 0.7}' cy='${h * 0.3}' r='${h * 0.12}' fill='rgba(255,255,255,0.55)'/>
    <path d='M0 ${h} L${w * 0.3} ${h * 0.55} L${w * 0.5} ${h * 0.75} L${w * 0.72} ${h * 0.45} L${w} ${h * 0.8} L${w} ${h} Z' fill='rgba(0,0,0,0.25)'/>
    <text x='${w / 2}' y='${h * 0.92}' font-family='Georgia' font-size='${h * 0.07}' fill='rgba(255,255,255,0.8)' text-anchor='middle'>${label}</text>
  </svg>`;
  return `data:image/svg+xml;utf8,${encodeURIComponent(s)}`;
}

function media(kind: Media['kind'], extra: Partial<Media> = {}): Media {
  return { id: uuid(), kind, url: null, posterUrl: null, durationSeconds: null, transcript: null, width: null, height: null, status: 'ready', storagePath: `mock/${kind}`, ...extra };
}

function c(sendoffId: string, name: string, rel: string | null, body: string | null, daysAgo: number, extra: Partial<Contribution> = {}): Contribution {
  return {
    id: uuid(), sendoffId, authorName: name, authorRelationship: rel, body, promptUsed: null, status: 'approved',
    sharedWithGroup: false, pinned: false, sortOrder: null, media: [], createdAt: new Date(now - daysAgo * day), ...extra,
  };
}

const MARIA_ENTRIES: Contribution[] = [
  c(MARIA.id, 'Dan Okafor', 'Your manager, somehow', 'Maria. You hired me when I had no business being hired. You spent the first year quietly fixing what I broke and the next nine teaching me not to break it. Every good habit I have at work is one of yours.\n\nEnjoy the mornings.', 18, { pinned: true }),
  c(MARIA.id, 'Priya N.', 'Your 2019 intern', 'You said "the deadline is real, the panic is optional." I have it on a sticky note. Still.', 12),
  c(MARIA.id, 'Tom Alvarez', 'Facilities', null, 10, {
    media: [media('voice', { durationSeconds: 48, transcript: "Hey Maria, it's Tom. I just wanted to say... you were the only one who learned my kids' names." })],
  }),
  c(MARIA.id, 'The Wednesday lunch crew', null, 'We are not going to survive Wednesdays.', 7, {
    media: [
      media('photo', { url: photo(1200, 900, 28, 'Wednesday, March'), width: 1200, height: 900 }),
      media('photo', { url: photo(1200, 900, 200, 'The good table'), width: 1200, height: 900 }),
      media('photo', { url: photo(1200, 900, 120, 'Birthday cake, 2023'), width: 1200, height: 900 }),
    ],
  }),
  c(MARIA.id, 'Lena Fischer', 'Finance', null, 5, {
    media: [media('video', { durationSeconds: 41, width: 1280, height: 720, posterUrl: photo(1280, 720, 330, 'Lena') })],
  }),
  c(MARIA.id, 'Sam', 'The new guy', "I've been here six weeks. You still made time. That told me everything about this place.", 3),
];

const TRACKS: MusicTrack[] = [
  { id: 'warm_piano', title: 'Last Light', artist: 'Stock', durationSeconds: 182, url: null, mood: 'warm' },
  { id: 'bright_strings', title: 'Open Windows', artist: 'Stock', durationSeconds: 164, url: null, mood: 'bright' },
  { id: 'reflective_guitar', title: 'Long Hallway', artist: 'Stock', durationSeconds: 201, url: null, mood: 'reflective' },
  { id: 'triumphant_brass', title: 'Final Whistle', artist: 'Stock', durationSeconds: 158, url: null, mood: 'triumphant' },
];

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

// The contributor's own entry survives a reload, so "come back and change yours" can be shown.
// Blob previews cannot be stored, so media comes back without a URL (as it would while processing).
const MINE_KEY = 'sendoff.mock.mine';
function loadMine(): Map<string, Contribution> {
  try {
    const raw = localStorage.getItem(MINE_KEY);
    if (!raw) return new Map();
    const obj = JSON.parse(raw) as Record<string, Contribution & { createdAt: string }>;
    return new Map(Object.entries(obj).map(([k, v]) => [k, { ...v, createdAt: new Date(v.createdAt), media: v.media.map((m) => ({ ...m, url: m.url?.startsWith('data:') ? m.url : null })) }]));
  } catch { return new Map(); }
}
function saveMine(mine: Map<string, Contribution>): void {
  try { localStorage.setItem(MINE_KEY, JSON.stringify(Object.fromEntries(mine))); } catch { /* private mode */ }
}

export class MockStore implements WebStore {
  readonly isMock = true;
  private sendoffs = new Map<string, MockSendoff>([[MARIA.slug, MARIA], [PATEL.slug, PATEL], [JO.slug, JO]]);
  private entries = new Map<string, Contribution[]>([[MARIA.id, MARIA_ENTRIES], [PATEL.id, []], [JO.id, []]]);
  private mine = loadMine();

  private find(slug: string): MockSendoff {
    const s = this.sendoffs.get(slug);
    if (!s) throw new StoreError('not_found', StoreMessages.not_found);
    return s;
  }

  async publicSendoff(slug: string): Promise<PublicSendoff> {
    await sleep(250);
    const s = this.find(slug);
    return { id: s.id, slug: s.slug, recipientName: s.recipientName, occasion: s.occasion, fromLine: s.fromLine, themeId: s.themeId, closesAt: s.closesAt, state: s.state, organizerName: s.organizerName };
  }

  async myContribution(sendoffId: string): Promise<Contribution | null> {
    return this.mine.get(sendoffId) ?? null;
  }

  async submit(sendoff: PublicSendoff, d: ContributionDraft, existing: Contribution | null, onProgress: Progress): Promise<Contribution> {
    const s = this.find(sendoff.slug);
    if (s.state !== 'collecting') throw new StoreError('closed', StoreMessages.closed);
    const kept = (existing?.media ?? []).filter((m) => d.keepMediaIds.includes(m.id));
    const added: Media[] = [];
    for (const [i, m] of d.newMedia.entries()) {
      onProgress((i + 1) / (d.newMedia.length + 1), `Uploading ${m.kind} ${i + 1} of ${d.newMedia.length}`);
      await sleep(400);
      added.push(media(m.kind, { url: m.previewUrl, durationSeconds: m.durationSeconds, width: m.width, height: m.height, posterUrl: m.kind === 'video' ? null : null }));
    }
    onProgress(1, 'Sealing');
    await sleep(300);
    const entry: Contribution = {
      id: existing?.id ?? uuid(), sendoffId: s.id, authorName: d.authorName.trim(),
      authorRelationship: d.authorRelationship.trim() || null, body: d.body.trim() || null, promptUsed: d.promptUsed,
      status: s.moderation === 'review' ? 'pending' : 'approved', sharedWithGroup: d.sharedWithGroup,
      pinned: false, sortOrder: null, media: [...kept, ...added], createdAt: existing?.createdAt ?? new Date(),
    };
    const list = this.entries.get(s.id) ?? [];
    const idx = list.findIndex((e) => e.id === entry.id);
    if (idx >= 0) list[idx] = entry; else { list.push(entry); s.contributorCount += 1; }
    this.entries.set(s.id, list);
    this.mine.set(s.id, entry);
    saveMine(this.mine);
    return entry;
  }

  async reveal(slug: string): Promise<RevealSendoff> {
    await sleep(300);
    return { ...this.find(slug) };
  }

  async open(slug: string): Promise<RevealSendoff> {
    const s = this.find(slug);
    const due = s.reveal === 'on_date' && s.opensAt != null && s.opensAt.getTime() <= Date.now();
    if (s.state === 'open' || (due && (s.state === 'sealed' || s.state === 'collecting'))) {
      s.state = 'open';
      return { ...s };
    }
    throw new StoreError('sealed', StoreMessages.sealed);
  }

  async revealContributions(slug: string): Promise<Contribution[]> {
    const s = this.find(slug);
    if (s.state !== 'open') return [];
    await sleep(200);
    return (this.entries.get(s.id) ?? []).filter((e) => e.status === 'approved').sort(revealOrder);
  }

  async track(id: string | null): Promise<MusicTrack | null> {
    return TRACKS.find((t) => t.id === id) ?? null;
  }
}

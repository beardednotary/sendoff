import { h, mount, Icons, svg, setTitle, clear, seal } from '../lib/dom';
import { getStore } from '../lib/store';
import { applyTheme, Occasions, occasionTitle } from '../lib/themes';
import { longDate, clock } from '../lib/format';
import { canRecord, imageFromFile, pickFiles, videoFromFile, VoiceRecorder, kindLabel } from '../lib/media';
import { Limits, StoreError, StoreMessages, firstName, initialOf, type Contribution, type ContributionDraft, type LocalMedia, type Media, type PublicSendoff } from '../lib/types';
import { loadingView, errorView } from './shared';
import { contributeLink } from '../lib/config';

// /s/{slug}?t={token}  — the page a contributor lands on. No account, no app.

export async function contributePage(slug: string, token: string | null): Promise<void> {
  mount(loadingView());
  const store = await getStore();
  if (!token && !store.isMock) {
    mount(errorView("This link is missing its key.", 'Ask whoever sent it to share the link again, exactly as the app gave it to them.'));
    return;
  }
  let sendoff: PublicSendoff;
  try {
    sendoff = await store.publicSendoff(slug, token ?? '');
  } catch (e) {
    const err = e instanceof StoreError ? e : new StoreError('network', StoreMessages.network);
    mount(errorView(err.code === 'not_found' || err.code === 'not_allowed' ? "We couldn't find that Sendoff." : 'Something went wrong.', err.message));
    return;
  }
  applyTheme(sendoff.themeId);
  setTitle(`Add yours — Sendoff for ${sendoff.recipientName}`);

  if (sendoff.state !== 'collecting') {
    mount(sealedView(sendoff));
    return;
  }

  const existing = await store.myContribution(sendoff.id).catch(() => null);
  if (existing) mount(thanksView(sendoff, existing, () => mount(formView(sendoff, existing))));
  else mount(formView(sendoff, null));
}

function header(s: PublicSendoff): HTMLElement {
  const first = firstName(s.recipientName);
  return h('header', { class: 'stack', style: 'gap:0' },
    h('div', { style: 'display:flex; justify-content:center; padding:6px 0 18px' }, seal(initialOf(s.recipientName), 40)),
    h('p', { class: 'eyebrow' }, `For ${s.recipientName} · ${occasionTitle(s.occasion)}`),
    h('h1', { class: 'display', style: 'margin-top:10px' }, 'Write something', h('br'), `only ${first} will read.`),
    h('p', { class: 'caption privacy', style: 'margin-top:12px' }, svg(Icons.lock),
      h('span', {}, `Only ${first} and ${s.organizerName} will see this. Nobody else who adds can read it.${s.closesAt ? ` Add yours by ${longDate(s.closesAt)}.` : ''}`)),
  );
}

/** Thanks and closed: left-aligned, the seal, one line of display type. */
function endView(s: PublicSendoff, title: string, body: string, ...rest: (HTMLElement | false | null)[]): HTMLElement {
  return h('main', { class: 'page', style: 'min-height:100vh; min-height:100dvh; display:flex; flex-direction:column; padding-bottom:40px' },
    h('div', { style: 'margin-top:auto' }, seal(initialOf(s.recipientName), 96)),
    h('h1', { class: 'display', style: 'margin-top:28px' }, title),
    h('p', { class: 'body', style: 'margin-top:12px' }, body),
    ...rest,
    h('div', { style: 'margin-top:auto; padding-top:48px' }, footerPromo()),
  );
}

function sealedView(s: PublicSendoff): HTMLElement {
  const first = firstName(s.recipientName);
  return endView(s,
    s.state === 'open' ? `${first} has opened it.` : "It's sealed.",
    s.state === 'open'
      ? 'This Sendoff is no longer collecting. Thank you for being part of it.'
      : `${s.organizerName} has sealed the Sendoff for ${first}. Nothing more can be added.`);
}

function footerPromo(): HTMLElement {
  return h('p', { class: 'caption' },
    'Know someone else leaving? ', h('a', { href: '/' }, 'Start a Sendoff of your own.'));
}

function thanksView(s: PublicSendoff, c: Contribution, onEdit: () => void): HTMLElement {
  const first = firstName(s.recipientName);
  return endView(s, "It's in the envelope.",
    c.status === 'pending'
      ? `${s.organizerName} will take a look before it goes in. ${first} opens it when the time comes.`
      : `${first} opens it when the time comes. You can come back and change yours until then.`,
    h('div', { style: 'margin-top:28px' }, h('button', { class: 'btn small', onclick: onEdit }, 'Change mine')),
  );
}

function formView(s: PublicSendoff, existing: Contribution | null): HTMLElement {
  const first = firstName(s.recipientName);
  const prompts = Occasions[s.occasion]?.prompts ?? [];

  const draft: ContributionDraft = {
    authorName: existing?.authorName ?? '',
    authorRelationship: existing?.authorRelationship ?? '',
    body: existing?.body ?? '',
    promptUsed: existing?.promptUsed ?? null,
    sharedWithGroup: existing?.sharedWithGroup ?? false,
    newMedia: [],
    keepMediaIds: existing?.media.map((m) => m.id) ?? [],
  };
  const keptMedia = (): Media[] => (existing?.media ?? []).filter((m) => draft.keepMediaIds.includes(m.id));

  // Fields
  const body = h('textarea', { id: 'body', class: 'writing', placeholder: 'Start anywhere. A memory, a thank you, something you never said.', maxLength: Limits.bodyCharacters, value: draft.body, 'aria-label': `What you want ${first} to read` });
  const count = h('span', {}, String(draft.body.length));
  const countLine = h('p', { class: 'caption', hidden: true, style: 'margin-top:8px' }, count, ` / ${Limits.bodyCharacters}`);
  const grow = () => { body.style.height = 'auto'; body.style.height = `${Math.max(150, body.scrollHeight)}px`; };
  body.addEventListener('input', grow);
  const name = h('input', { id: 'name', placeholder: 'Your name', autocomplete: 'name', value: draft.authorName });
  const rel = h('input', { id: 'rel', placeholder: 'Your 2019 intern', value: draft.authorRelationship });
  const share = h('input', { type: 'checkbox', role: 'switch', checked: draft.sharedWithGroup });
  const submit = h('button', { class: 'btn primary wide', disabled: true }, existing ? 'Save changes' : 'Add yours');
  const error = h('div', { class: 'notice error', role: 'alert', hidden: true });
  const progress = h('div', { class: 'stack', hidden: true, style: 'gap:6px' }, h('div', { class: 'progress' }, h('i')), h('div', { class: 'caption center' }));

  const hasContent = () => body.value.trim().length > 0 || draft.newMedia.length > 0 || keptMedia().length > 0;
  const validate = () => {
    submit.disabled = !(hasContent() && name.value.trim().length > 0);
    count.textContent = String(body.value.length);
    countLine.hidden = body.value.length < Limits.bodyCharacters - 200;
  };
  body.addEventListener('input', validate);
  name.addEventListener('input', validate);

  // Prompts
  const chips = h('div', { class: 'chips', role: 'group', 'aria-label': 'Prompts' },
    ...prompts.map((p) => h('button', {
      class: 'chip', type: 'button', 'aria-pressed': draft.promptUsed === p ? 'true' : 'false',
      onclick: (e: Event) => {
        chips.querySelectorAll('.chip').forEach((x) => x.setAttribute('aria-pressed', 'false'));
        (e.currentTarget as HTMLElement).setAttribute('aria-pressed', 'true');
        draft.promptUsed = p;
        if (!body.value.trim()) body.value = `${p}\n\n`;
        body.focus();
        body.setSelectionRange(body.value.length, body.value.length);
        validate();
      },
    }, p)),
  );

  // Attachments
  const thumbs = h('div', { class: 'thumbs' });
  const limitsLine = h('p', { class: 'caption' }, `Video up to ${Limits.videoSeconds} seconds, voice up to ${Limits.voiceSeconds / 60} minutes, up to ${Limits.photosPerEntry} photos.`);
  const recorderHost = h('div');

  const photoCount = () => keptMedia().filter((m) => m.kind === 'photo').length + draft.newMedia.filter((m) => m.kind === 'photo').length;
  const has = (k: Media['kind']) => keptMedia().some((m) => m.kind === k) || draft.newMedia.some((m) => m.kind === k);

  const photoBtn = h('button', { class: 'btn small', type: 'button', onclick: addPhotos }, svg(Icons.photo), 'Photo');
  const voiceBtn = h('button', { class: 'btn small', type: 'button', onclick: addVoice }, svg(Icons.voice), 'Voice');
  const videoBtn = h('button', { class: 'btn small', type: 'button', onclick: addVideo }, svg(Icons.video), 'Video');

  function renderThumbs(): void {
    clear(thumbs);
    for (const m of keptMedia()) thumbs.appendChild(thumb(m.kind, m.url, m.durationSeconds, () => { draft.keepMediaIds = draft.keepMediaIds.filter((id) => id !== m.id); refresh(); }));
    for (const m of draft.newMedia) thumbs.appendChild(thumb(m.kind, m.previewUrl, m.durationSeconds, () => { draft.newMedia = draft.newMedia.filter((x) => x !== m); URL.revokeObjectURL(m.previewUrl); refresh(); }));
    thumbs.hidden = thumbs.childElementCount === 0;
  }
  function refresh(): void {
    renderThumbs();
    photoBtn.disabled = photoCount() >= Limits.photosPerEntry;
    voiceBtn.disabled = has('voice');
    videoBtn.disabled = has('video');
    validate();
  }
  function showError(msg: string): void { error.textContent = msg; error.hidden = false; error.scrollIntoView({ block: 'nearest' }); }

  async function addPhotos(): Promise<void> {
    const room = Limits.photosPerEntry - photoCount();
    const files = await pickFiles('image/*', room > 1);
    for (const f of files.slice(0, room)) {
      try { draft.newMedia.push(await imageFromFile(f)); } catch (e) { showError((e as Error).message); }
    }
    error.hidden = error.textContent === '';
    refresh();
  }
  async function addVideo(): Promise<void> {
    const [f] = await pickFiles('video/*', false);
    if (!f) return;
    try { draft.newMedia.push(await videoFromFile(f)); error.hidden = true; } catch (e) { showError((e as Error).message); }
    refresh();
  }
  async function addVoice(): Promise<void> {
    if (!canRecord()) {
      const [f] = await pickFiles('audio/*', false);
      if (!f) return;
      draft.newMedia.push({ id: crypto.randomUUID(), kind: 'voice', file: f, previewUrl: URL.createObjectURL(f), durationSeconds: null, width: null, height: null, mime: f.type || 'audio/mp4' });
      refresh();
      return;
    }
    clear(recorderHost);
    recorderHost.appendChild(recorderView(
      (m) => { draft.newMedia.push(m); clear(recorderHost); refresh(); },
      () => clear(recorderHost),
      showError,
    ));
    recorderHost.scrollIntoView({ block: 'center', behavior: 'smooth' });
  }

  // Submit
  submit.addEventListener('click', async () => {
    draft.authorName = name.value;
    draft.authorRelationship = rel.value;
    draft.body = body.value;
    draft.sharedWithGroup = share.checked;
    submit.disabled = true;
    error.hidden = true;
    progress.hidden = false;
    const bar = progress.querySelector('i') as HTMLElement;
    const label = progress.querySelector('.caption') as HTMLElement;
    try {
      const store = await getStore();
      const saved = await store.submit(s, draft, existing, (f, l) => { bar.style.setProperty('--p', `${Math.round(f * 100)}%`); label.textContent = l; });
      mount(thanksView(s, saved, () => mount(formView(s, saved))));
    } catch (e) {
      const err = e instanceof StoreError ? e : new StoreError('network', StoreMessages.network);
      progress.hidden = true;
      showError(err.message);
      validate();
    }
  });

  const main = h('main', { class: 'page' },
    header(s),
    prompts.length > 0 && h('section', { style: 'margin-top:20px' }, chips),
    h('section', { style: 'margin-top:22px' }, body, countLine),
    h('section', { class: 'stack', style: 'gap:12px; margin-top:16px' },
      h('div', { class: 'attach' }, photoBtn, voiceBtn, videoBtn),
      recorderHost,
      thumbs,
      limitsLine,
    ),
    h('section', { class: 'stack', style: 'gap:14px; margin-top:26px' },
      h('div', { class: 'field' }, h('label', { for: 'name' }, 'Sign it'), name),
      h('div', { class: 'field' }, h('label', { for: 'rel' }, 'How you know them (optional)'), rel),
      h('label', { class: 'switch', style: 'margin-top:4px' }, h('span', {}, 'Let the others who added read mine too'), share),
    ),
    h('section', { class: 'stack', style: 'margin-top:20px' }, error, progress),
    existing && h('p', { class: 'caption center', style: 'margin-top:24px' }, h('button', { class: 'link', type: 'button', onclick: () => mount(thanksView(s, existing, () => mount(formView(s, existing)))) }, 'Never mind, keep it as it was')),
    h('div', { class: 'sticky' }, submit),
  );

  // Link hint for the mock, so the demo link can be copied
  if (!token()) main.appendChild(h('p', { class: 'caption center no-print', style: 'margin-top:30px; opacity:.6' }, contributeLink(s.slug, null).replace(/^https?:\/\//, '')));

  refresh();
  requestAnimationFrame(grow);
  return main;

  function token(): string | null { return new URLSearchParams(location.search).get('t'); }
}

function thumb(kind: Media['kind'], url: string | null, duration: number | null, onRemove: () => void): HTMLElement {
  const inner = kind === 'photo' && url ? h('img', { src: url, alt: '' })
    : kind === 'video' && url ? h('video', { src: url, muted: true, playsInline: true, preload: 'metadata' })
    : h('div', { style: 'display:grid; place-items:center; height:100%; color:var(--muted)' }, svg(kind === 'voice' ? Icons.voice : kind === 'video' ? Icons.video : Icons.photo));
  if (inner instanceof SVGElement) { /* unreachable */ }
  return h('div', { class: 'thumb' },
    inner,
    h('span', { class: 'tag' }, duration != null ? `${kindLabel(kind)} · ${clock(duration)}` : kindLabel(kind)),
    h('button', { class: 'x', type: 'button', 'aria-label': `Remove ${kindLabel(kind).toLowerCase()}`, onclick: onRemove }, svg(Icons.close)),
  );
}

function recorderView(onDone: (m: LocalMedia) => void, onCancel: () => void, onError: (msg: string) => void): HTMLElement {
  const rec = new VoiceRecorder();
  const time = h('div', { class: 'time' }, '0:00');
  const hint = h('div', { class: 'caption' }, 'Tap to start. Up to two minutes.');
  const bars = Array.from({ length: 28 }, () => h('b', { style: '--h:20%' }));
  const wave = h('div', { class: 'wave', 'aria-hidden': 'true' }, ...bars);
  let recording = false;
  let levels: number[] = [];

  const button = h('button', { class: 'rec', type: 'button', 'aria-label': 'Start recording' }, svg(Icons.mic));
  button.addEventListener('click', async () => {
    if (!recording) {
      try {
        await rec.start();
      } catch {
        onError("We couldn't reach the microphone. Check the browser's permission for this site, or attach an audio file instead.");
        onCancel();
        return;
      }
      recording = true;
      button.classList.add('on');
      button.setAttribute('aria-label', 'Stop recording');
      clear(button); button.appendChild(svg(Icons.stop));
      hint.textContent = 'Recording. Tap to stop.';
      rec.onTick = (elapsed, level) => {
        time.textContent = clock(elapsed);
        levels = [...levels.slice(-27), level];
        bars.forEach((b, i) => { const l = levels[levels.length - 28 + i] ?? 0; b.style.setProperty('--h', `${20 + l * 80}%`); b.classList.toggle('on', l > 0.05); });
        if (elapsed >= Limits.voiceSeconds) button.click();
      };
    } else {
      recording = false;
      button.disabled = true;
      try { onDone(await rec.stop()); } catch { onError("That recording didn't save. Try again."); onCancel(); }
    }
  });

  return h('div', { class: 'recorder' },
    h('div', { class: 'row', style: 'gap:16px' }, button, h('div', { class: 'stack', style: 'gap:0; flex:1' }, time, hint)),
    wave,
    h('button', { class: 'link caption', type: 'button', style: 'justify-self:start', onclick: () => { rec.cancel(); onCancel(); } }, 'Cancel'),
  );
}

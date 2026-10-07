import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import type { WebStore, Progress } from './store';
import {
  StoreError, StoreMessages, revealOrder,
  type Contribution, type ContributionDraft, type Media, type MusicTrack, type PublicSendoff, type RevealSendoff,
} from './types';

// Mirrors supabase/migrations/0001_init.sql and 0002_web.sql. Contributors and recipients get an
// anonymous Supabase session so RLS has an auth.uid(); the slug + token / key in the link is the
// actual capability and is checked by security-definer functions in Postgres.

interface SendoffPublicRow {
  id: string; recipient_name: string; occasion: PublicSendoff['occasion']; from_line: string | null;
  theme_id: PublicSendoff['themeId']; closes_at: string | null; state: PublicSendoff['state']; organizer_name: string | null;
}
interface SendoffRevealRow {
  id: string; recipient_name: string; occasion: RevealSendoff['occasion']; from_line: string | null; cover_message: string | null;
  theme_id: RevealSendoff['themeId']; music_track_id: string | null; state: RevealSendoff['state']; reveal: RevealSendoff['reveal'];
  opens_at: string | null; organizer_name: string | null; contributor_count: number; plan: RevealSendoff['plan'];
}
interface MediaRow {
  id: string; contribution_id: string; kind: Media['kind']; storage_path: string; processed_path: string | null; poster_path: string | null;
  duration_seconds: number | null; width: number | null; height: number | null; transcript: string | null; status: Media['status'];
  sort_order: number;
}
interface ContributionRow {
  id: string; sendoff_id: string; author_name: string; author_relationship: string | null; body: string | null; prompt_used: string | null;
  status: Contribution['status']; shared_with_group: boolean; pinned: boolean; sort_order: number | null; created_at: string;
  media?: MediaRow[];
}

function date(s: string | null): Date | null { return s ? new Date(s) : null; }

function mapMedia(r: MediaRow): Media {
  return {
    id: r.id, kind: r.kind, url: null, posterUrl: null, durationSeconds: r.duration_seconds, transcript: r.transcript,
    width: r.width, height: r.height, status: r.status, storagePath: r.processed_path ?? r.storage_path,
  };
}

function mapContribution(r: ContributionRow, media: MediaRow[] = r.media ?? []): Contribution {
  return {
    id: r.id, sendoffId: r.sendoff_id, authorName: r.author_name, authorRelationship: r.author_relationship, body: r.body,
    promptUsed: r.prompt_used, status: r.status, sharedWithGroup: r.shared_with_group, pinned: r.pinned, sortOrder: r.sort_order,
    media: [...media].sort((a, b) => a.sort_order - b.sort_order).map(mapMedia), createdAt: new Date(r.created_at),
  };
}

function extensionFor(mime: string): string {
  const map: Record<string, string> = {
    'image/jpeg': 'jpg', 'image/png': 'png', 'image/heic': 'heic', 'image/webp': 'webp', 'image/gif': 'gif',
    'audio/webm': 'webm', 'audio/mp4': 'm4a', 'audio/mpeg': 'mp3', 'audio/ogg': 'ogg', 'audio/wav': 'wav',
    'video/mp4': 'mp4', 'video/quicktime': 'mov', 'video/webm': 'webm',
  };
  const base = mime.split(';')[0] ?? '';
  return map[base] ?? base.split('/')[1] ?? 'bin';
}

export class SupabaseStore implements WebStore {
  readonly isMock = false;
  private client: SupabaseClient;
  private signed = new Map<string, string>();

  constructor(url: string, anonKey: string) {
    this.client = createClient(url, anonKey, { auth: { persistSession: true, autoRefreshToken: true } });
  }

  private async ensureSession(): Promise<string> {
    const { data } = await this.client.auth.getSession();
    if (data.session) return data.session.user.id;
    const { data: anon, error } = await this.client.auth.signInAnonymously();
    if (error || !anon.user) throw new StoreError('network', StoreMessages.network);
    return anon.user.id;
  }

  private fail(error: { message: string; code?: string } | null, fallback: StoreError['code'] = 'network'): never {
    console.error(error);
    throw new StoreError(fallback, StoreMessages[fallback]);
  }

  // MARK: Contributor

  async publicSendoff(slug: string, token: string): Promise<PublicSendoff> {
    await this.ensureSession();
    const { data, error } = await this.client.rpc('sendoff_public', { p_slug: slug, p_token: token });
    if (error) this.fail(error);
    const r = (data as SendoffPublicRow[] | null)?.[0];
    if (!r) throw new StoreError('not_found', StoreMessages.not_found);
    return {
      id: r.id, slug, recipientName: r.recipient_name, occasion: r.occasion, fromLine: r.from_line, themeId: r.theme_id,
      closesAt: date(r.closes_at), state: r.state, organizerName: r.organizer_name ?? 'the organizer',
    };
  }

  async myContribution(sendoffId: string): Promise<Contribution | null> {
    const uid = await this.ensureSession();
    const { data, error } = await this.client.from('contributions').select('*, media(*)')
      .eq('sendoff_id', sendoffId).eq('author_id', uid).order('created_at', { ascending: false }).limit(1);
    if (error) this.fail(error);
    const row = (data as ContributionRow[] | null)?.[0];
    if (!row) return null;
    const c = mapContribution(row);
    await this.signOwn(c.media);
    return c;
  }

  /** Signed URLs for the contributor's own uploads (storage RLS allows the author to read them). */
  private async signOwn(media: Media[]): Promise<void> {
    const paths = media.map((m) => m.storagePath).filter((p) => !this.signed.has(p));
    if (paths.length) {
      const { data } = await this.client.storage.from('uploads').createSignedUrls(paths, 3600);
      for (const d of data ?? []) if (d.signedUrl && d.path) this.signed.set(d.path, d.signedUrl);
    }
    for (const m of media) m.url = this.signed.get(m.storagePath) ?? null;
  }

  async submit(sendoff: PublicSendoff, d: ContributionDraft, existing: Contribution | null, onProgress: Progress): Promise<Contribution> {
    const uid = await this.ensureSession();
    onProgress(0.05, 'Saving your note');

    const fields = {
      author_name: d.authorName.trim(), author_relationship: d.authorRelationship.trim() || null,
      body: d.body.trim() || null, prompt_used: d.promptUsed, shared_with_group: d.sharedWithGroup,
    };

    let row: ContributionRow;
    if (existing) {
      const { data, error } = await this.client.from('contributions').update(fields).eq('id', existing.id).select().single();
      if (error || !data) this.fail(error, error?.code === '42501' ? 'closed' : 'network');
      row = data as ContributionRow;
      const drop = existing.media.filter((m) => !d.keepMediaIds.includes(m.id));
      if (drop.length) {
        await this.client.from('media').delete().in('id', drop.map((m) => m.id));
        await this.client.storage.from('uploads').remove(drop.map((m) => m.storagePath));
      }
    } else {
      const { data, error } = await this.client.from('contributions')
        .insert({ ...fields, sendoff_id: sendoff.id, author_id: uid }).select().single();
      if (error || !data) this.fail(error, error?.code === '42501' ? 'closed' : 'network');
      row = data as ContributionRow;
    }

    const kept = (existing?.media ?? []).filter((m) => d.keepMediaIds.includes(m.id));
    const added: Media[] = [];
    const total = d.newMedia.length;
    for (const [i, m] of d.newMedia.entries()) {
      onProgress(0.1 + (0.85 * i) / Math.max(total, 1), `Uploading ${m.kind} ${i + 1} of ${total}`);
      const path = `${sendoff.id}/${row.id}/${m.id}.${extensionFor(m.mime)}`;
      const { error: upErr } = await this.client.storage.from('uploads').upload(path, m.file, { contentType: m.mime, upsert: false });
      if (upErr) this.fail(upErr);
      const { data: mrow, error: mErr } = await this.client.from('media').insert({
        contribution_id: row.id, kind: m.kind, storage_path: path, duration_seconds: m.durationSeconds,
        width: m.width, height: m.height, sort_order: kept.length + i,
      }).select().single();
      if (mErr || !mrow) this.fail(mErr);
      const media = mapMedia(mrow as MediaRow);
      media.url = m.previewUrl;
      added.push(media);
    }
    onProgress(1, 'Sealed');
    return { ...mapContribution(row, []), media: [...kept, ...added] };
  }

  // MARK: Recipient

  private mapReveal(slug: string, r: SendoffRevealRow): RevealSendoff {
    return {
      id: r.id, slug, recipientName: r.recipient_name, occasion: r.occasion, fromLine: r.from_line, coverMessage: r.cover_message,
      themeId: r.theme_id, musicTrackId: r.music_track_id, state: r.state, reveal: r.reveal, opensAt: date(r.opens_at),
      organizerName: r.organizer_name ?? 'the organizer', contributorCount: r.contributor_count ?? 0, plan: r.plan ?? 'free',
    };
  }

  async reveal(slug: string, key: string): Promise<RevealSendoff> {
    await this.ensureSession();
    const { data, error } = await this.client.rpc('sendoff_reveal', { p_slug: slug, p_key: key });
    if (error) this.fail(error);
    const r = (data as SendoffRevealRow[] | null)?.[0];
    if (!r) throw new StoreError('not_found', StoreMessages.not_found);
    return this.mapReveal(slug, r);
  }

  async open(slug: string, key: string): Promise<RevealSendoff> {
    await this.ensureSession();
    const { data, error } = await this.client.rpc('sendoff_open', { p_slug: slug, p_key: key });
    if (error) this.fail(error);
    const r = (data as SendoffRevealRow[] | null)?.[0];
    if (!r) throw new StoreError('sealed', StoreMessages.sealed);
    return this.mapReveal(slug, r);
  }

  async revealContributions(slug: string, key: string): Promise<Contribution[]> {
    await this.ensureSession();
    const [{ data: cs, error: e1 }, { data: ms, error: e2 }] = await Promise.all([
      this.client.rpc('reveal_contributions', { p_slug: slug, p_key: key }),
      this.client.rpc('reveal_media', { p_slug: slug, p_key: key }),
    ]);
    if (e1) this.fail(e1);
    if (e2) this.fail(e2);
    const byContribution = new Map<string, MediaRow[]>();
    for (const m of (ms as MediaRow[] | null) ?? []) {
      const list = byContribution.get(m.contribution_id) ?? [];
      list.push(m);
      byContribution.set(m.contribution_id, list);
    }
    const list = ((cs as ContributionRow[] | null) ?? []).map((r) => mapContribution(r, byContribution.get(r.id) ?? [])).sort(revealOrder);
    await this.signForRecipient(slug, key, list.flatMap((c) => c.media), (ms as MediaRow[] | null) ?? []);
    return list;
  }

  /** The recipient holds no row-level grant on storage, so an Edge Function signs for them. */
  private async signForRecipient(slug: string, key: string, media: Media[], rows: MediaRow[]): Promise<void> {
    const posters = new Map(rows.filter((r) => r.poster_path).map((r) => [r.id, r.poster_path as string]));
    const paths = [...new Set([...media.map((m) => m.storagePath), ...posters.values()])];
    if (!paths.length) return;
    const { data, error } = await this.client.functions.invoke<{ urls: Record<string, string> }>('sign-media', {
      body: { slug, key, paths },
    });
    if (error || !data) { console.error(error); return; }
    for (const m of media) {
      m.url = data.urls[m.storagePath] ?? null;
      const poster = posters.get(m.id);
      m.posterUrl = poster ? data.urls[poster] ?? null : null;
    }
  }

  // MARK: Catalog

  async track(id: string | null): Promise<MusicTrack | null> {
    if (!id) return null;
    const { data, error } = await this.client.from('music_tracks').select().eq('id', id).maybeSingle();
    if (error || !data) return null;
    const r = data as { id: string; title: string; artist: string | null; duration_seconds: number | null; storage_path: string | null; mood: string | null };
    let url: string | null = null;
    if (r.storage_path) {
      const path = r.storage_path.replace(/^stock-music\//, '');
      url = this.client.storage.from('stock-music').getPublicUrl(path).data.publicUrl;
    }
    return { id: r.id, title: r.title, artist: r.artist, durationSeconds: r.duration_seconds, url, mood: r.mood };
  }
}

// process-media — runs after a `media` row is inserted (database webhook).
//
// Pipeline (docs/ARCHITECTURE.md, Media pipeline):
//   uploaded -> processing -> ready | failed
//   photo : read dimensions, write a resized 1600px JPEG to `processed`, keep the original 7 days
//   voice : normalize loudness, transcode to AAC m4a, transcript via a speech API
//   video : H.264 720p MP4, poster frame, loudness
//
// Edge Functions cannot run ffmpeg. Transcoding goes to an external service; this function
// owns the state machine, validates limits and dispatches. Two adapters are sketched:
//   - `passthrough` (default): marks photos ready as-is (the web and app render originals) and
//     leaves audio/video `uploaded` with a note. Enough to run the product end to end today.
//   - `mux`: creates a Mux asset from a signed URL of the upload. Fill in MUX_TOKEN_ID/SECRET.
//
// Deploy:  supabase functions deploy process-media
// Webhook: Database > Webhooks > table `media`, event INSERT, URL of this function,
//          header Authorization: Bearer <service role key>.

import { createClient } from 'npm:@supabase/supabase-js@2';

type MediaRow = {
  id: string; contribution_id: string; kind: 'photo' | 'voice' | 'video'; storage_path: string;
  duration_seconds: number | null; status: 'uploaded' | 'processing' | 'ready' | 'failed';
};

const LIMITS = { videoSeconds: 60, voiceSeconds: 120 };

const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);

Deno.serve(async (req) => {
  // Only the database webhook (service role) may call this.
  const auth = req.headers.get('authorization') ?? '';
  if (auth !== `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`) return new Response('forbidden', { status: 403 });

  const payload = await req.json() as { type: string; record: MediaRow };
  if (payload.type !== 'INSERT') return new Response('ignored');
  const m = payload.record;

  // Enforce caps server-side. The client already checked, but the client is not trusted.
  if ((m.kind === 'video' && (m.duration_seconds ?? 0) > LIMITS.videoSeconds + 1) ||
      (m.kind === 'voice' && (m.duration_seconds ?? 0) > LIMITS.voiceSeconds + 1)) {
    await fail(m.id, 'over length');
    await admin.storage.from('uploads').remove([m.storage_path]);
    return new Response('rejected');
  }

  await admin.from('media').update({ status: 'processing' }).eq('id', m.id);

  try {
    const adapter = Deno.env.get('MEDIA_ADAPTER') ?? 'passthrough';
    if (adapter === 'mux' && m.kind !== 'photo') await viaMux(m);
    else await passthrough(m);
    return new Response('ok');
  } catch (e) {
    console.error(e);
    await fail(m.id, String(e));
    return new Response('failed', { status: 500 });
  }
});

async function fail(id: string, reason: string) {
  await admin.from('media').update({ status: 'failed', transcript: null }).eq('id', id);
  console.warn(`media ${id} failed: ${reason}`);
}

/** Originals are served as uploaded. Photos are ready immediately; audio and video too, since
 *  browsers and iOS play the formats the capture produced (m4a/mp4/mov; webm on Android). */
async function passthrough(m: MediaRow) {
  await admin.from('media').update({ status: 'ready' }).eq('id', m.id);
}

/** Mux: create an asset from a short-lived signed URL. Mux calls back when ready; wire the
 *  `video.asset.ready` webhook to a second function that sets processed_path (an HLS playback id)
 *  and poster_path. */
async function viaMux(m: MediaRow) {
  const id = Deno.env.get('MUX_TOKEN_ID'), secret = Deno.env.get('MUX_TOKEN_SECRET');
  if (!id || !secret) throw new Error('MUX_TOKEN_ID / MUX_TOKEN_SECRET not set');
  const { data: signed, error } = await admin.storage.from('uploads').createSignedUrl(m.storage_path, 600);
  if (error || !signed) throw new Error('could not sign upload');
  const res = await fetch('https://api.mux.com/video/v1/assets', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Basic ${btoa(`${id}:${secret}`)}` },
    body: JSON.stringify({
      input: [{ url: signed.signedUrl }],
      playback_policy: ['signed'],
      mp4_support: 'standard',
      max_resolution_tier: '1080p',
      normalize_audio: true,
      passthrough: m.id,
    }),
  });
  if (!res.ok) throw new Error(`mux ${res.status}: ${await res.text()}`);
  // Stays `processing` until the Mux webhook marks it ready.
}

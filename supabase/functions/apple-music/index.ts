// apple-music — the linked song's 30-second preview, for a recipient without Apple Music.
//
// A Plus Sendoff can carry a song from Apple Music (0007_apple_music.sql). The iPhone app plays
// the full song for Apple Music subscribers through MusicKit; everyone else, and the website,
// hears Apple's preview. Looking that up needs a MusicKit developer token, which is signed here
// so the private key never reaches a browser. Nothing is downloaded or stored: the response is
// Apple's own preview URL and the song's details, with its Apple Music link for attribution.
//
//   POST { slug, key, storefront? }  ->  { id, title, artist, artworkUrl, previewUrl, appleMusicUrl }
//
// The recipient key is the capability, as in sign-media, so this is not an open catalog proxy:
// it answers only for a Sendoff whose reveal includes a song, which means it has Plus.
//
// Secrets (supabase secrets set ...): MUSICKIT_TEAM_ID, MUSICKIT_KEY_ID, MUSICKIT_PRIVATE_KEY
// (the .p8 file's contents). Deploy: supabase functions deploy apple-music --no-verify-jwt

import { createClient } from 'npm:@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });
}

const b64url = (bytes: Uint8Array | string) =>
  btoa(typeof bytes === 'string' ? bytes : String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

/** A MusicKit developer token (ES256 JWT), kept for a day and refreshed well before it expires. */
let cached: { token: string; until: number } | null = null;
async function developerToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cached && cached.until > now + 3600) return cached.token;
  const team = Deno.env.get('MUSICKIT_TEAM_ID'), kid = Deno.env.get('MUSICKIT_KEY_ID'), pem = Deno.env.get('MUSICKIT_PRIVATE_KEY');
  if (!team || !kid || !pem) throw new Error('MusicKit secrets are not set');
  const der = Uint8Array.from(atob(pem.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '')), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey('pkcs8', der, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
  const exp = now + 60 * 60 * 24;
  const unsigned = `${b64url(JSON.stringify({ alg: 'ES256', kid }))}.${b64url(JSON.stringify({ iss: team, iat: now, exp }))}`;
  // WebCrypto's ECDSA signature is already the raw r||s form JWS wants.
  const sig = new Uint8Array(await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, new TextEncoder().encode(unsigned)));
  cached = { token: `${unsigned}.${b64url(sig)}`, until: exp };
  return cached.token;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ error: 'method' }, 405);

  let body: { slug?: string; key?: string; storefront?: string };
  try { body = await req.json(); } catch { return json({ error: 'bad json' }, 400); }
  const { slug, key } = body;
  if (!slug || !key) return json({ error: 'slug and key are required' }, 400);
  const storefront = /^[a-z]{2}$/.test(body.storefront ?? '') ? body.storefront! : 'us';

  // The same view the recipient gets: the song is there only when the Sendoff has Plus.
  const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  const { data: rows, error } = await admin.rpc('sendoff_reveal', { p_slug: slug, p_key: key });
  if (error) return json({ error: 'lookup failed' }, 500);
  const songID: string | null = rows?.[0]?.apple_music_id ?? null;
  if (!songID) return json({ error: 'no song' }, 404);

  let token: string;
  try { token = await developerToken(); } catch { return json({ error: 'not configured' }, 503); }

  // A song may not be sold in every storefront; fall back to the US catalog.
  for (const sf of storefront === 'us' ? ['us'] : [storefront, 'us']) {
    const res = await fetch(`https://api.music.apple.com/v1/catalog/${sf}/songs/${songID}`, { headers: { Authorization: `Bearer ${token}` } });
    if (res.status === 404) continue;
    if (!res.ok) return json({ error: 'apple music unavailable' }, 502);
    const song = (await res.json()).data?.[0];
    const a = song?.attributes;
    if (!a) continue;
    return json({
      id: song.id,
      title: a.name,
      artist: a.artistName,
      artworkUrl: a.artwork?.url?.replace('{w}', '600').replace('{h}', '600') ?? null,
      previewUrl: a.previews?.[0]?.url ?? null,
      appleMusicUrl: a.url ?? null,
    });
  }
  return json({ error: 'not in catalog' }, 404);
});

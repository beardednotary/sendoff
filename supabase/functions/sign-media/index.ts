// sign-media — signed URLs for the recipient's reveal.
//
// The recipient opens the Sendoff with slug + recipient_key and no account. Storage RLS cannot
// express that, so this function checks the key against the database with the service role and
// signs only paths that belong to approved entries of that open Sendoff.
//
//   POST { slug, key, paths: string[] }  ->  { urls: { [path]: signedUrl } }
//
// Deploy: supabase functions deploy sign-media --no-verify-jwt
// (anonymous sessions do carry a JWT; --no-verify-jwt keeps the page working if the session
//  has not been created yet. The key is the capability, not the JWT.)

import { createClient } from 'npm:@supabase/supabase-js@2';

const SIGNED_TTL_SECONDS = 60 * 60 * 6;
const MAX_PATHS = 400;

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ error: 'method' }, 405);

  let body: { slug?: string; key?: string; paths?: string[] };
  try { body = await req.json(); } catch { return json({ error: 'bad json' }, 400); }
  const { slug, key, paths } = body;
  if (!slug || !key || !Array.isArray(paths)) return json({ error: 'slug, key and paths are required' }, 400);
  if (paths.length > MAX_PATHS) return json({ error: 'too many paths' }, 400);

  const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);

  // 1. The key must open this Sendoff, and it must be open.
  const { data: sendoff, error: sErr } = await admin.from('sendoffs').select('id, state')
    .eq('slug', slug).eq('recipient_key', key).maybeSingle();
  if (sErr) return json({ error: 'lookup failed' }, 500);
  if (!sendoff) return json({ error: 'not found' }, 404);
  if (sendoff.state !== 'open') return json({ error: 'sealed' }, 403);

  // 2. Only paths that belong to approved entries of this Sendoff.
  const { data: rows, error: mErr } = await admin.from('media')
    .select('storage_path, processed_path, poster_path, contributions!inner(sendoff_id, status)')
    .eq('contributions.sendoff_id', sendoff.id).eq('contributions.status', 'approved');
  if (mErr) return json({ error: 'media lookup failed' }, 500);

  const allowed = new Set<string>();
  for (const r of rows ?? []) {
    for (const p of [r.storage_path, r.processed_path, r.poster_path]) if (p) allowed.add(p);
  }
  const wanted = [...new Set(paths)].filter((p) => allowed.has(p));

  // 3. Sign. Processed files live in `processed`, originals in `uploads`; paths carry no bucket,
  //    so try processed first for anything the processor wrote.
  const urls: Record<string, string> = {};
  const byBucket: Record<'processed' | 'uploads', string[]> = { processed: [], uploads: [] };
  const processedPaths = new Set((rows ?? []).flatMap((r) => [r.processed_path, r.poster_path].filter(Boolean) as string[]));
  for (const p of wanted) byBucket[processedPaths.has(p) ? 'processed' : 'uploads'].push(p);

  for (const bucket of ['processed', 'uploads'] as const) {
    if (!byBucket[bucket].length) continue;
    const { data } = await admin.storage.from(bucket).createSignedUrls(byBucket[bucket], SIGNED_TTL_SECONDS);
    for (const d of data ?? []) if (d.signedUrl && d.path) urls[d.path] = d.signedUrl;
  }

  return json({ urls });
});

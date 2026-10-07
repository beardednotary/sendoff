-- Sendoff — what the web pages need on top of 0001_init.sql
--
-- 1. The recipient's reveal functions return the count, the reveal policy and the plan.
-- 2. sendoff_open(): breaking the seal from the web. Flips state to 'open' when due.
-- 3. reveal_media(): media rows for the approved entries of an open Sendoff, keyed by the link.
-- 4. Storage policies on the private `uploads` bucket for contributors.
--
-- Keyed functions are `security definer` and check slug + token/key themselves. The anonymous
-- session the web creates only exists so RLS has an auth.uid() for the contributor's own rows.

-- ---------------------------------------------------------------------------
-- 1. Reveal metadata
-- ---------------------------------------------------------------------------
drop function if exists sendoff_reveal(text, text);

create or replace function sendoff_reveal(p_slug text, p_key text)
returns table (id uuid, recipient_name text, occasion occasion, from_line text, cover_message text,
               theme_id text, music_track_id text, state sendoff_state, reveal reveal_policy,
               opens_at timestamptz, organizer_name text, contributor_count int, plan plan)
language sql stable security definer set search_path = public as $$
  select s.id, s.recipient_name, s.occasion, s.from_line, s.cover_message, s.theme_id,
         s.music_track_id, s.state, s.reveal, s.opens_at, p.display_name,
         (select count(*)::int from contributions c where c.sendoff_id = s.id and c.status <> 'hidden'),
         s.plan
  from sendoffs s join profiles p on p.id = s.organizer_id
  where s.slug = p_slug and s.recipient_key = p_key
$$;

-- ---------------------------------------------------------------------------
-- 2. Breaking the seal
-- ---------------------------------------------------------------------------
-- Returns the Sendoff when it is (now) open, nothing when it is not yet due. A Sendoff on an
-- `on_date` policy opens itself at opens_at even if the organizer forgot to seal it; a `manual`
-- one opens only when the organizer sets state = 'open' from the app.
create or replace function sendoff_open(p_slug text, p_key text)
returns setof sendoff_reveal
language plpgsql volatile security definer set search_path = public as $$
begin
  update sendoffs s
     set state = 'open',
         opened_at = coalesce(s.opened_at, now())
   where s.slug = p_slug and s.recipient_key = p_key
     and (s.state = 'open'
          or (s.reveal = 'on_date' and s.opens_at is not null and s.opens_at <= now()
              and s.state in ('collecting', 'sealed')));

  return query
    select * from sendoff_reveal(p_slug, p_key) r where r.state = 'open';
end $$;

-- ---------------------------------------------------------------------------
-- 3. Media for the reveal
-- ---------------------------------------------------------------------------
create or replace function reveal_media(p_slug text, p_key text)
returns setof media
language sql stable security definer set search_path = public as $$
  select m.* from media m
  join contributions c on c.id = m.contribution_id
  join sendoffs s on s.id = c.sendoff_id
  where s.slug = p_slug and s.recipient_key = p_key and s.state = 'open' and c.status = 'approved'
  order by m.contribution_id, m.sort_order
$$;

-- Lock the keyed functions down to callers through the API (anon and authenticated).
revoke all on function sendoff_reveal(text, text) from public;
revoke all on function sendoff_open(text, text) from public;
revoke all on function reveal_media(text, text) from public;
revoke all on function sendoff_public(text, text) from public;
revoke all on function reveal_contributions(text, text) from public;
grant execute on function sendoff_reveal(text, text), sendoff_open(text, text), reveal_media(text, text),
                          sendoff_public(text, text), reveal_contributions(text, text)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. Storage: uploads/{sendoff_id}/{contribution_id}/{media_id}.{ext}
-- ---------------------------------------------------------------------------
-- A contributor may write under a contribution they authored while the Sendoff is collecting,
-- and read or delete their own files. The organizer may read and delete everything under their
-- Sendoff. Recipients get signed URLs from the `sign-media` Edge Function (service role), which
-- checks slug + recipient_key, so no policy is needed for them.

create or replace function storage_contribution_id(name text) returns uuid
language sql immutable as $$
  select nullif(split_part(name, '/', 2), '')::uuid
$$;

create or replace function storage_sendoff_id(name text) returns uuid
language sql immutable as $$
  select nullif(split_part(name, '/', 1), '')::uuid
$$;

create policy "uploads: author writes own" on storage.objects for insert to authenticated
  with check (
    bucket_id = 'uploads'
    and exists (
      select 1 from contributions c join sendoffs s on s.id = c.sendoff_id
      where c.id = storage_contribution_id(name) and c.author_id = auth.uid()
        and s.id = storage_sendoff_id(name) and s.state = 'collecting'
    )
  );

create policy "uploads: author reads own" on storage.objects for select to authenticated
  using (
    bucket_id = 'uploads'
    and exists (select 1 from contributions c where c.id = storage_contribution_id(name) and c.author_id = auth.uid())
  );

create policy "uploads: author deletes own" on storage.objects for delete to authenticated
  using (
    bucket_id = 'uploads'
    and exists (
      select 1 from contributions c join sendoffs s on s.id = c.sendoff_id
      where c.id = storage_contribution_id(name) and c.author_id = auth.uid() and s.state = 'collecting'
    )
  );

create policy "uploads: organizer reads" on storage.objects for select to authenticated
  using (bucket_id in ('uploads', 'processed') and is_organizer(storage_sendoff_id(name)));

create policy "uploads: organizer deletes" on storage.objects for delete to authenticated
  using (bucket_id in ('uploads', 'processed') and is_organizer(storage_sendoff_id(name)));

-- Recipients who claimed the Sendoff in the app (recipient_user_id) read processed media directly.
create policy "processed: open recipient reads" on storage.objects for select to authenticated
  using (bucket_id in ('uploads', 'processed') and is_open_recipient(storage_sendoff_id(name)));

-- ---------------------------------------------------------------------------
-- Housekeeping
-- ---------------------------------------------------------------------------
-- The contributor's anonymous session is tied to their browser. If they lose it, they cannot
-- edit their entry; the organizer can remove it for them. Magic-link upgrade of the anonymous
-- user (supabase.auth.updateUser with an email) keeps author_id stable, so nothing here changes.

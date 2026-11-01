-- Sendoff — the recipient's photo on the cover
--
-- The organizer can add a photo of the person when making a Sendoff. It lives in the private
-- `uploads` bucket at {sendoff_id}/cover/{file}.jpg and its path in sendoffs.recipient_photo_path.
-- The organizer reads it through the existing "uploads: organizer reads" policy. The recipient
-- gets a signed URL from the `sign-media` Edge Function, which checks the recipient key, and sees
-- it blurred behind the seal before the Sendoff opens, so the reveal functions return the path.

-- Only the organizer writes under the cover folder. Contributor paths never use it: their second
-- segment is a contribution id, which storage_contribution_id() requires to be a uuid.
create policy "uploads: organizer writes the cover" on storage.objects for insert to authenticated
  with check (bucket_id = 'uploads' and split_part(name, '/', 2) = 'cover' and is_organizer(storage_sendoff_id(name)));

-- The cover must be this Sendoff's own file. sign-media signs whatever this column names for
-- anyone holding the recipient key, so it must never point at another Sendoff's media.
alter table sendoffs add constraint sendoffs_cover_is_own
  check (recipient_photo_path is null or recipient_photo_path like id::text || '/cover/%');

-- The reveal functions gain recipient_photo_path. A new column changes the return type, so they
-- are dropped and created again (sendoff_open reads sendoff_reveal, so it goes first).
drop function if exists sendoff_open(text, text);
drop function if exists sendoff_reveal(text, text);

create function sendoff_reveal(p_slug text, p_key text)
returns table (id uuid, recipient_name text, occasion occasion, from_line text, cover_message text,
               theme_id text, music_track_id text, state sendoff_state, reveal reveal_policy,
               opens_at timestamptz, organizer_name text, contributor_count int, plan plan,
               recipient_photo_path text)
language sql stable security definer set search_path = public as $$
  select s.id, s.recipient_name, s.occasion, s.from_line, s.cover_message, s.theme_id,
         s.music_track_id, s.state, s.reveal, s.opens_at, p.display_name,
         (select count(*)::int from contributions c where c.sendoff_id = s.id and c.status <> 'hidden'),
         s.plan, s.recipient_photo_path
  from sendoffs s join profiles p on p.id = s.organizer_id
  where s.slug = p_slug and s.recipient_key = p_key
$$;

create function sendoff_open(p_slug text, p_key text)
returns table (id uuid, recipient_name text, occasion occasion, from_line text, cover_message text,
               theme_id text, music_track_id text, state sendoff_state, reveal reveal_policy,
               opens_at timestamptz, organizer_name text, contributor_count int, plan plan,
               recipient_photo_path text)
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

revoke all on function sendoff_reveal(text, text) from public;
revoke all on function sendoff_open(text, text) from public;
grant execute on function sendoff_reveal(text, text), sendoff_open(text, text) to anon, authenticated;

-- Sendoff — a song from Apple Music
--
-- A Plus feature, with the same rule as the paid looks (0006): the organizer can link a song
-- and hear it in their own preview at any time, but the recipient gets it only when the Sendoff
-- has Plus. Without Plus the reveal plays the stock track as before.
--
-- Only the catalog id, title and artist are kept. The audio is never stored: the app plays it
-- with MusicKit (the full song for Apple Music subscribers), and everyone else hears Apple's
-- 30-second preview, looked up by the `apple-music` Edge Function with the MusicKit key.

alter table sendoffs
  add column apple_music_id text,
  add column apple_music_title text,
  add column apple_music_artist text,
  add constraint sendoffs_apple_music_id_is_catalog check (apple_music_id is null or apple_music_id ~ '^[0-9]{1,20}$'),
  add constraint sendoffs_apple_music_is_complete check ((apple_music_id is null) = (apple_music_title is null));

-- The reveal functions gain the song. A new column changes the return type, so they are dropped
-- and created again (sendoff_open reads sendoff_reveal, so it goes first), as in 0005.
drop function if exists sendoff_open(text, text);
drop function if exists sendoff_reveal(text, text);

create function sendoff_reveal(p_slug text, p_key text)
returns table (id uuid, recipient_name text, occasion occasion, from_line text, cover_message text,
               theme_id text, music_track_id text, state sendoff_state, reveal reveal_policy,
               opens_at timestamptz, organizer_name text, contributor_count int, plan plan,
               recipient_photo_path text, apple_music_id text, apple_music_title text,
               apple_music_artist text)
language sql stable security definer set search_path = public as $$
  select s.id, s.recipient_name, s.occasion, s.from_line, s.cover_message, sendoff_look(s.id),
         s.music_track_id, s.state, s.reveal, s.opens_at, p.display_name,
         (select count(*)::int from contributions c where c.sendoff_id = s.id and c.status <> 'hidden'),
         s.plan, s.recipient_photo_path,
         case when s.plan >= 'plus' then s.apple_music_id end,
         case when s.plan >= 'plus' then s.apple_music_title end,
         case when s.plan >= 'plus' then s.apple_music_artist end
  from sendoffs s join profiles p on p.id = s.organizer_id
  where s.slug = p_slug and s.recipient_key = p_key
$$;

create function sendoff_open(p_slug text, p_key text)
returns table (id uuid, recipient_name text, occasion occasion, from_line text, cover_message text,
               theme_id text, music_track_id text, state sendoff_state, reveal reveal_policy,
               opens_at timestamptz, organizer_name text, contributor_count int, plan plan,
               recipient_photo_path text, apple_music_id text, apple_music_title text,
               apple_music_artist text)
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

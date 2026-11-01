-- Sendoff — paid looks
--
-- Gold Leaf, Darkroom and Field Day are free to try. An organizer can pick one while making a
-- Sendoff, and contributors see it while they add. The recipient sees it only once it is paid
-- for: Sendoff Plus on this Sendoff, or the look bought on its own. Until then the reveal shows
-- the look's free counterpart, so nothing is taken away from the organizer before they decide,
-- and an unpaid look never reaches the recipient.
--
-- A look bought on its own is a StoreKit non-consumable. The app now records it in
-- `entitlements` (product_id 'theme.<id>', never consumed) the way it records credits, under the
-- same v1 trust model as 0003_payments.sql: the client inserts its own verified transaction.

alter table themes add column free_alternative text references themes(id);
update themes set free_alternative = 'letterpress' where id = 'gold_leaf';
update themes set free_alternative = 'midnight_toast' where id = 'darkroom';
update themes set free_alternative = 'chalk' where id = 'field_day';
alter table themes add constraint themes_premium_has_free_alternative
  check (not premium or free_alternative is not null);

-- The look the recipient sees right now.
create function sendoff_look(p_sendoff uuid) returns text
language sql stable security definer set search_path = public as $$
  select case
           when not t.premium then s.theme_id
           when s.plan >= 'plus' then s.theme_id
           when exists (select 1 from entitlements e
                         where e.user_id = s.organizer_id and e.product_id = 'theme.' || s.theme_id)
             then s.theme_id
           else t.free_alternative
         end
  from sendoffs s join themes t on t.id = s.theme_id
  where s.id = p_sendoff
$$;
-- Only the reveal functions call it. (Supabase grants new functions to anon and authenticated.)
revoke all on function sendoff_look(uuid) from public, anon, authenticated;

-- The recipient's view now carries that look. Same signature, so sendoff_open (which reads
-- sendoff_reveal) picks it up unchanged.
create or replace function sendoff_reveal(p_slug text, p_key text)
returns table (id uuid, recipient_name text, occasion occasion, from_line text, cover_message text,
               theme_id text, music_track_id text, state sendoff_state, reveal reveal_policy,
               opens_at timestamptz, organizer_name text, contributor_count int, plan plan,
               recipient_photo_path text)
language sql stable security definer set search_path = public as $$
  select s.id, s.recipient_name, s.occasion, s.from_line, s.cover_message, sendoff_look(s.id),
         s.music_track_id, s.state, s.reveal, s.opens_at, p.display_name,
         (select count(*)::int from contributions c where c.sendoff_id = s.id and c.status <> 'hidden'),
         s.plan, s.recipient_photo_path
  from sendoffs s join profiles p on p.id = s.organizer_id
  where s.slug = p_slug and s.recipient_key = p_key
$$;

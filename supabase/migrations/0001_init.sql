-- Sendoff — initial schema
-- Postgres / Supabase. Run with `supabase db push` or paste into the SQL editor.

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
create type occasion as enum (
  'retirement', 'new_job', 'graduation', 'teacher', 'season_end', 'military', 'farewell'
);

create type sendoff_state as enum ('draft', 'collecting', 'sealed', 'open');
create type moderation_mode as enum ('trust', 'review');
create type reveal_policy as enum ('on_date', 'manual');
create type contribution_status as enum ('pending', 'approved', 'hidden');
create type media_kind as enum ('photo', 'voice', 'video');
create type media_status as enum ('uploaded', 'processing', 'ready', 'failed');
create type plan as enum ('free', 'single', 'plus', 'org');

-- ---------------------------------------------------------------------------
-- Orgs and profiles
-- ---------------------------------------------------------------------------
create table orgs (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  plan plan not null default 'org',
  default_moderation moderation_mode not null default 'review',
  brand jsonb not null default '{}'::jsonb,          -- logo url, colors, from-line
  stripe_customer_id text,
  created_at timestamptz not null default now()
);

create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  email text,
  org_id uuid references orgs(id) on delete set null,
  org_role text check (org_role in ('admin', 'member')),
  created_at timestamptz not null default now()
);

-- Keep profiles in sync with auth.users
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, email, display_name)
  values (new.id, new.email, coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email, '@', 1)))
  on conflict (id) do nothing;
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- ---------------------------------------------------------------------------
-- Themes and music (catalog data, readable by everyone)
-- ---------------------------------------------------------------------------
create table themes (
  id text primary key,                 -- 'letterpress', 'midnight_toast', 'chalk', 'gold_leaf', ...
  name text not null,
  premium boolean not null default false,
  definition jsonb not null,           -- SendoffTheme as JSON (paper, ink, seal, type, motion)
  sort_order int not null default 0
);

create table music_tracks (
  id text primary key,
  title text not null,
  artist text,
  duration_seconds int,
  storage_path text,                   -- stock: bucket path. null for linked tracks
  apple_music_id text,                 -- premium: MusicKit catalog id
  premium boolean not null default false,
  mood text,                           -- 'warm', 'bright', 'reflective', 'triumphant'
  sort_order int not null default 0
);

-- ---------------------------------------------------------------------------
-- Sendoffs
-- ---------------------------------------------------------------------------
create table sendoffs (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,                         -- short, in the shared link
  organizer_id uuid not null references profiles(id) on delete cascade,
  org_id uuid references orgs(id) on delete set null,

  occasion occasion not null,
  recipient_name text not null,
  recipient_photo_path text,
  recipient_user_id uuid references profiles(id),     -- set when the recipient claims it
  from_line text,                                     -- "From the whole 4th floor"
  cover_message text,

  theme_id text not null references themes(id) default 'letterpress',
  music_track_id text references music_tracks(id),

  state sendoff_state not null default 'draft',
  moderation moderation_mode not null default 'trust',
  reveal reveal_policy not null default 'on_date',
  closes_at timestamptz,                              -- contributions stop
  opens_at timestamptz,                               -- recipient can open
  opened_at timestamptz,

  contribute_token text not null default encode(gen_random_bytes(16), 'hex'),  -- in the shared link
  recipient_key text not null default encode(gen_random_bytes(24), 'hex'),     -- in the recipient's reveal link / QR
  plan plan not null default 'free',
  contributor_limit int not null default 100,
  contributor_goal int default 25,                    -- organizer's own target, not a cap

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index sendoffs_organizer_idx on sendoffs(organizer_id);
create index sendoffs_recipient_idx on sendoffs(recipient_user_id);

-- ---------------------------------------------------------------------------
-- Contributions and media
-- ---------------------------------------------------------------------------
create table contributions (
  id uuid primary key default gen_random_uuid(),
  sendoff_id uuid not null references sendoffs(id) on delete cascade,
  author_id uuid references auth.users(id) on delete set null,   -- anonymous or magic-link user
  author_name text not null,
  author_relationship text,                                      -- "Your 2019 intern"
  author_email text,
  body text,
  prompt_used text,
  status contribution_status not null default 'approved',
  shared_with_group boolean not null default false,
  pinned boolean not null default false,
  sort_order int,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index contributions_sendoff_idx on contributions(sendoff_id, status);

create table media (
  id uuid primary key default gen_random_uuid(),
  contribution_id uuid not null references contributions(id) on delete cascade,
  kind media_kind not null,
  storage_path text not null,
  processed_path text,
  poster_path text,
  duration_seconds numeric(6,2),
  width int,
  height int,
  transcript text,
  status media_status not null default 'uploaded',
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);

create index media_contribution_idx on media(contribution_id);

-- ---------------------------------------------------------------------------
-- Entitlements and invites
-- ---------------------------------------------------------------------------
create table entitlements (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references profiles(id) on delete cascade,
  org_id uuid references orgs(id) on delete cascade,
  product_id text not null,          -- 'sendoff.single', 'sendoff.plus', 'theme.gold_leaf', 'org.annual'
  source text not null,              -- 'storekit', 'stripe', 'grant'
  external_id text,                  -- transaction / subscription id
  consumed_by uuid references sendoffs(id),
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  check (user_id is not null or org_id is not null)
);

create table invites (
  id uuid primary key default gen_random_uuid(),
  sendoff_id uuid not null references sendoffs(id) on delete cascade,
  name text,
  email text,
  contributed boolean not null default false,
  nudged_at timestamptz,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
create or replace function set_updated_at() returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

create trigger sendoffs_updated before update on sendoffs for each row execute function set_updated_at();
create trigger contributions_updated before update on contributions for each row execute function set_updated_at();

-- In Review mode new contributions start pending.
create or replace function apply_moderation_default() returns trigger language plpgsql as $$
declare m moderation_mode;
begin
  select moderation into m from sendoffs where id = new.sendoff_id;
  if m = 'review' then new.status := 'pending'; end if;
  return new;
end $$;

create trigger contributions_moderation before insert on contributions
  for each row execute function apply_moderation_default();

-- Is the current user the organizer of a sendoff?
create or replace function is_organizer(s uuid) returns boolean language sql stable security definer as $$
  select exists (select 1 from sendoffs where id = s and organizer_id = auth.uid())
$$;

-- Is the current user the recipient and is the sendoff open?
create or replace function is_open_recipient(s uuid) returns boolean language sql stable security definer as $$
  select exists (
    select 1 from sendoffs where id = s and recipient_user_id = auth.uid() and state = 'open'
  )
$$;

-- Has the current user contributed to this sendoff?
create or replace function has_contributed(s uuid) returns boolean language sql stable security definer as $$
  select exists (select 1 from contributions where sendoff_id = s and author_id = auth.uid())
$$;

-- Recipient opens the reveal from the web with slug + recipient_key, no account needed.
create or replace function sendoff_reveal(p_slug text, p_key text)
returns table (id uuid, recipient_name text, occasion occasion, from_line text, cover_message text,
               theme_id text, music_track_id text, state sendoff_state, opens_at timestamptz,
               organizer_name text)
language sql stable security definer as $$
  select s.id, s.recipient_name, s.occasion, s.from_line, s.cover_message, s.theme_id,
         s.music_track_id, s.state, s.opens_at, p.display_name
  from sendoffs s join profiles p on p.id = s.organizer_id
  where s.slug = p_slug and s.recipient_key = p_key
$$;

-- Approved entries for an open sendoff, keyed by the recipient link. Returns nothing before open.
create or replace function reveal_contributions(p_slug text, p_key text)
returns setof contributions
language sql stable security definer as $$
  select c.* from contributions c
  join sendoffs s on s.id = c.sendoff_id
  where s.slug = p_slug and s.recipient_key = p_key and s.state = 'open' and c.status = 'approved'
  order by c.pinned desc, c.sort_order nulls last, c.created_at
$$;

-- Contributors need a tiny public view of the sendoff they were linked to.
create or replace function sendoff_public(p_slug text, p_token text)
returns table (id uuid, recipient_name text, occasion occasion, from_line text,
               theme_id text, closes_at timestamptz, state sendoff_state, organizer_name text)
language sql stable security definer as $$
  select s.id, s.recipient_name, s.occasion, s.from_line, s.theme_id, s.closes_at, s.state,
         p.display_name
  from sendoffs s join profiles p on p.id = s.organizer_id
  where s.slug = p_slug and s.contribute_token = p_token
$$;

-- ---------------------------------------------------------------------------
-- Row level security: the privacy model
-- ---------------------------------------------------------------------------
alter table orgs enable row level security;
alter table profiles enable row level security;
alter table themes enable row level security;
alter table music_tracks enable row level security;
alter table sendoffs enable row level security;
alter table contributions enable row level security;
alter table media enable row level security;
alter table entitlements enable row level security;
alter table invites enable row level security;

-- Catalog: anyone can read
create policy "themes readable" on themes for select using (true);
create policy "music readable" on music_tracks for select using (true);

-- Profiles: you can see yourself and members of your org
create policy "own profile" on profiles for select using (
  id = auth.uid() or (org_id is not null and org_id = (select org_id from profiles where id = auth.uid()))
);
create policy "update own profile" on profiles for update using (id = auth.uid());

-- Orgs: members can read, admins can update
create policy "org members read" on orgs for select using (
  id = (select org_id from profiles where id = auth.uid())
);
create policy "org admins update" on orgs for update using (
  id = (select org_id from profiles where id = auth.uid() and org_role = 'admin')
);

-- Sendoffs
create policy "organizer full access" on sendoffs for all
  using (organizer_id = auth.uid()) with check (organizer_id = auth.uid());
create policy "recipient reads own" on sendoffs for select
  using (recipient_user_id = auth.uid());
create policy "org admins read org sendoffs" on sendoffs for select
  using (org_id is not null and org_id = (select org_id from profiles where id = auth.uid() and org_role = 'admin'));

-- Contributions: THE privacy rule
create policy "contributions select" on contributions for select using (
  is_organizer(sendoff_id)
  or author_id = auth.uid()
  or (status = 'approved' and is_open_recipient(sendoff_id))
  or (shared_with_group and status = 'approved' and has_contributed(sendoff_id))
);
create policy "contributions insert" on contributions for insert with check (
  author_id = auth.uid()
  and exists (select 1 from sendoffs s where s.id = sendoff_id and s.state = 'collecting')
);
create policy "contributions update by author" on contributions for update using (
  author_id = auth.uid()
  and exists (select 1 from sendoffs s where s.id = sendoff_id and s.state = 'collecting')
);
create policy "contributions update by organizer" on contributions for update using (is_organizer(sendoff_id));
create policy "contributions delete by organizer" on contributions for delete using (is_organizer(sendoff_id));

-- Media inherits from its contribution
create policy "media select" on media for select using (
  exists (select 1 from contributions c where c.id = contribution_id)   -- RLS on contributions filters
);
create policy "media insert" on media for insert with check (
  exists (select 1 from contributions c where c.id = contribution_id and c.author_id = auth.uid())
);
create policy "media delete" on media for delete using (
  exists (select 1 from contributions c where c.id = contribution_id
          and (c.author_id = auth.uid() or is_organizer(c.sendoff_id)))
);

-- Entitlements: read your own or your org's
create policy "entitlements read" on entitlements for select using (
  user_id = auth.uid() or org_id = (select org_id from profiles where id = auth.uid())
);

-- Invites: organizer only
create policy "invites organizer" on invites for all
  using (is_organizer(sendoff_id)) with check (is_organizer(sendoff_id));

-- ---------------------------------------------------------------------------
-- Storage buckets (private; served by signed URL)
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public) values
  ('uploads', 'uploads', false),
  ('processed', 'processed', false),
  ('stock-music', 'stock-music', true)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- Seed: themes and stock music placeholders
-- ---------------------------------------------------------------------------
insert into themes (id, name, premium, sort_order, definition) values
('letterpress', 'Letterpress', false, 1, '{"paper":"#F4EFE6","ink":"#1F1D1A","mutedInk":"#6B655C","seal":"#C8442B","accent":"#D9C7A3","motion":"lift","texture":"paper","radius":6}'),
('midnight_toast', 'Midnight Toast', false, 2, '{"paper":"#0F1B2D","ink":"#F2EBDD","mutedInk":"#A79F8E","seal":"#C9A24A","accent":"#2A3A55","motion":"lift","texture":"linen","radius":10}'),
('chalk', 'Chalk', false, 3, '{"paper":"#2F4A3E","ink":"#F7F3E8","mutedInk":"#B8C4B9","seal":"#E9C46A","accent":"#3E5C4E","motion":"turn","texture":"chalk","radius":4}'),
('gold_leaf', 'Gold Leaf', true, 10, '{"paper":"#F6F1E7","ink":"#1F1D1A","mutedInk":"#6B655C","seal":"#B8912E","accent":"#E8D9B5","motion":"lift","texture":"paper","radius":6,"foil":true}'),
('darkroom', 'Darkroom', true, 11, '{"paper":"#0B0B0C","ink":"#EDEDED","mutedInk":"#8E8E8E","seal":"#E04E39","accent":"#1E1E20","motion":"fade","texture":"grain","radius":2}'),
('field_day', 'Field Day', true, 12, '{"paper":"#2E7D4F","ink":"#FFFFFF","mutedInk":"#CFE6D7","seal":"#F4D35E","accent":"#256A42","motion":"turn","texture":"grass","radius":8}')
on conflict (id) do nothing;

insert into music_tracks (id, title, artist, duration_seconds, storage_path, premium, mood, sort_order) values
('warm_piano', 'Last Light', 'Stock', 182, 'stock-music/last_light.m4a', false, 'warm', 1),
('bright_strings', 'Open Windows', 'Stock', 164, 'stock-music/open_windows.m4a', false, 'bright', 2),
('reflective_guitar', 'Long Hallway', 'Stock', 201, 'stock-music/long_hallway.m4a', false, 'reflective', 3),
('triumphant_brass', 'Final Whistle', 'Stock', 158, 'stock-music/final_whistle.m4a', false, 'triumphant', 4)
on conflict (id) do nothing;

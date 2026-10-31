-- Sendoff — media webhook
--
-- Calls the process-media Edge Function when a `media` row is inserted. This is the trigger a
-- dashboard "database webhook" would create, kept here so it is versioned and reviewed.
--
-- The project URL and the service role key live in Vault under `sendoff_project_url` and
-- `sendoff_service_role_key`; supabase/setup.sh stores them. Until both exist, and on plain
-- Postgres in the test harness (no Vault, no pg_net), the trigger does nothing.

do $$ begin
  if exists (select 1 from pg_available_extensions where name = 'pg_net') then
    create extension if not exists pg_net with schema extensions;
  end if;
end $$;

create or replace function dispatch_process_media() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  base text;
  key text;
begin
  if to_regclass('vault.decrypted_secrets') is null or to_regnamespace('net') is null then
    return new;
  end if;
  -- Dynamic SQL so plain Postgres never has to resolve vault or net.
  execute 'select decrypted_secret from vault.decrypted_secrets where name = $1' into base using 'sendoff_project_url';
  execute 'select decrypted_secret from vault.decrypted_secrets where name = $1' into key using 'sendoff_service_role_key';
  if base is null or key is null then
    return new;
  end if;
  execute 'select net.http_post(url := $1, body := $2, headers := $3)'
    using rtrim(base, '/') || '/functions/v1/process-media',
          jsonb_build_object('type', 'INSERT', 'table', 'media', 'schema', 'public',
                             'record', to_jsonb(new), 'old_record', null),
          jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || key);
  return new;
end $$;

revoke all on function dispatch_process_media() from public, anon, authenticated;

drop trigger if exists media_dispatch on media;
create trigger media_dispatch after insert on media
  for each row execute function dispatch_process_media();

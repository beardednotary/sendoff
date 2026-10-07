-- The privacy model and the payment rules, exercised through RLS and the keyed functions
-- exactly as the clients call them. Each block raises on failure; psql stops on the first error.
--
-- Roles: the test runs as a superuser to set things up, then `set local role authenticated`
-- plus `request.jwt.claim.sub` to act as a given user, the way PostgREST does.

\set ON_ERROR_STOP on
\set QUIET on

create or replace function test_as(u uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', u::text, true);
  perform set_config('role', 'authenticated', true);
end $$;

create or replace function test_reset() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('role', 'none', true);
end $$;

-- ---------------------------------------------------------------------------
begin;

-- People
insert into auth.users (id, email) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'dan@example.com'),        -- organizer
  ('bbbbbbbb-0000-0000-0000-000000000002', null),                     -- contributor (anonymous)
  ('cccccccc-0000-0000-0000-000000000003', null),                     -- another contributor
  ('dddddddd-0000-0000-0000-000000000004', 'maria@example.com');      -- recipient who signs in later

do $$ begin
  assert (select count(*) from profiles) = 4, 'handle_new_user creates a profile per user';
  assert (select display_name from profiles where id = 'aaaaaaaa-0000-0000-0000-000000000001') = 'dan',
    'display name defaults to the email local part';
end $$;

-- Organizer creates a Sendoff through RLS
select test_as('aaaaaaaa-0000-0000-0000-000000000001') as _ \gset
insert into sendoffs (slug, organizer_id, occasion, recipient_name, state, theme_id, closes_at, opens_at)
values ('maria-r', 'aaaaaaaa-0000-0000-0000-000000000001', 'retirement', 'Maria Reyes', 'collecting', 'midnight_toast',
        now() + interval '5 days', now() + interval '7 days');

do $$
declare s sendoffs%rowtype;
begin
  select * into s from sendoffs where slug = 'maria-r';
  assert s.plan = 'free', 'new Sendoffs are Free';
  assert s.contributor_limit = 10, 'Free holds 10 (0003 default)';
  assert length(s.contribute_token) = 32 and length(s.recipient_key) = 48, 'tokens are generated';
end $$;
select test_reset() as _ \gset

-- Someone with the wrong token learns nothing
do $$
declare t text; k text;
begin
  select contribute_token, recipient_key into t, k from sendoffs where slug = 'maria-r';
  perform set_config('test.token', t, true);
  perform set_config('test.key', k, true);
end $$;

select test_as('bbbbbbbb-0000-0000-0000-000000000002') as _ \gset
do $$ begin
  assert (select count(*) from sendoff_public('maria-r', 'wrong')) = 0, 'wrong token sees nothing';
  assert (select count(*) from sendoff_public('maria-r', current_setting('test.token'))) = 1, 'right token sees the public view';
  assert (select count(*) from sendoffs) = 0, 'a contributor cannot read the sendoffs table directly';
end $$;

-- Contributor B adds an entry; contributor C adds one; each sees only their own
insert into contributions (sendoff_id, author_id, author_name, body)
select id, 'bbbbbbbb-0000-0000-0000-000000000002', 'Priya', 'Deadline is real, panic is optional.' from sendoff_public('maria-r', current_setting('test.token'));

select test_as('cccccccc-0000-0000-0000-000000000003') as _ \gset
insert into contributions (sendoff_id, author_id, author_name, body, shared_with_group)
select id, 'cccccccc-0000-0000-0000-000000000003', 'Tom', 'You learned my kids'' names.', true from sendoff_public('maria-r', current_setting('test.token'));

do $$ begin
  assert (select count(*) from contributions) = 1, 'C sees only their own entry (B did not share)';
end $$;

select test_as('bbbbbbbb-0000-0000-0000-000000000002') as _ \gset
do $$ begin
  assert (select count(*) from contributions) = 2, 'B sees their own plus C''s, because C shared with the group and B contributed';
  assert (select count(*) from contributions where author_id = 'bbbbbbbb-0000-0000-0000-000000000002') = 1;
end $$;

-- B may not forge an entry under someone else's id
do $$ begin
  begin
    insert into contributions (sendoff_id, author_id, author_name, body)
    select id, 'cccccccc-0000-0000-0000-000000000003', 'Not Tom', 'forged' from sendoff_public('maria-r', current_setting('test.token'));
    raise exception 'forged insert went through';
  exception when insufficient_privilege then null;
  end;
end $$;

-- The organizer sees everything
select test_as('aaaaaaaa-0000-0000-0000-000000000001') as _ \gset
do $$ begin
  assert (select count(*) from contributions) = 2, 'organizer sees all entries';
end $$;

-- The recipient key: sealed, nothing shows
select test_as('dddddddd-0000-0000-0000-000000000004') as _ \gset
do $$
declare r record;
begin
  select * into r from sendoff_reveal('maria-r', current_setting('test.key'));
  assert r.recipient_name = 'Maria Reyes' and r.contributor_count = 2 and r.state = 'collecting', 'reveal metadata';
  assert (select count(*) from sendoff_reveal('maria-r', 'wrong')) = 0, 'wrong key sees nothing';
  assert (select count(*) from reveal_contributions('maria-r', current_setting('test.key'))) = 0, 'nothing before open';
  assert (select count(*) from sendoff_open('maria-r', current_setting('test.key'))) = 0, 'cannot break the seal before opens_at';
end $$;

-- Free limit: fill to 10, the 11th is refused
select test_reset() as _ \gset
insert into contributions (sendoff_id, author_id, author_name, body)
select s.id, 'bbbbbbbb-0000-0000-0000-000000000002', 'Filler ' || g, 'x'
from sendoffs s, generate_series(1, 8) g where s.slug = 'maria-r';

do $$
declare sid uuid;
begin
  select id into sid from sendoffs where slug = 'maria-r';
  assert (select count(*) from contributions where sendoff_id = sid) = 10;
  begin
    insert into contributions (sendoff_id, author_id, author_name, body) values (sid, 'bbbbbbbb-0000-0000-0000-000000000002', 'Eleventh', 'x');
    raise exception 'eleventh entry was accepted on Free';
  exception when others then
    assert sqlerrm like '%sendoff_full%', 'limit error is named sendoff_full, got: ' || sqlerrm;
  end;
  -- hiding one makes room
  update contributions set status = 'hidden' where sendoff_id = sid and author_name = 'Filler 1';
  insert into contributions (sendoff_id, author_id, author_name, body) values (sid, 'bbbbbbbb-0000-0000-0000-000000000002', 'Eleventh', 'x');
  update contributions set status = 'approved' where sendoff_id = sid and author_name = 'Filler 1';
end $$;

-- Payments: the organizer records a Plus purchase and redeems it
select test_as('aaaaaaaa-0000-0000-0000-000000000001') as _ \gset
insert into entitlements (user_id, product_id, source, external_id)
values ('aaaaaaaa-0000-0000-0000-000000000001', 'sendoff.plus', 'storekit', 'tx-1000');

do $$ begin
  begin
    insert into entitlements (user_id, product_id, source, external_id)
    values ('aaaaaaaa-0000-0000-0000-000000000001', 'sendoff.plus', 'storekit', 'tx-1000');
    raise exception 'duplicate transaction was credited twice';
  exception when unique_violation then null;
  end;
  begin
    insert into entitlements (user_id, product_id, source, external_id)
    values ('bbbbbbbb-0000-0000-0000-000000000002', 'sendoff.plus', 'storekit', 'tx-1001');
    raise exception 'inserted an entitlement for someone else';
  exception when insufficient_privilege then null;
  end;
end $$;

do $$
declare e uuid; sid uuid; r sendoffs%rowtype;
begin
  select id into e from entitlements where external_id = 'tx-1000';
  select id into sid from sendoffs where slug = 'maria-r';
  select * into r from redeem_entitlement(e, sid);
  assert r.plan = 'plus' and r.contributor_limit = 100000, 'redeem raises the plan and the limit';
  assert (select consumed_by from entitlements where id = e) = sid, 'credit is consumed';
  begin
    perform redeem_entitlement(e, sid);
    raise exception 'a credit was spent twice';
  exception when others then
    assert sqlerrm like '%entitlement_unavailable%', sqlerrm;
  end;
end $$;

-- Someone else cannot redeem the organizer's credit
select test_as('bbbbbbbb-0000-0000-0000-000000000002') as _ \gset
do $$
declare e uuid; sid uuid;
begin
  select id into e from entitlements where external_id = 'tx-1000'; -- not visible under RLS
  assert e is null, 'entitlements are private';
end $$;

-- The organizer seals; the date passes; the recipient breaks the seal
select test_as('aaaaaaaa-0000-0000-0000-000000000001') as _ \gset
update sendoffs set state = 'sealed', opens_at = now() - interval '1 minute' where slug = 'maria-r';

select test_as('dddddddd-0000-0000-0000-000000000004') as _ \gset
do $$
declare r record;
begin
  select * into r from sendoff_open('maria-r', current_setting('test.key'));
  assert r.state = 'open', 'sendoff_open flips a due Sendoff to open';
  assert (select opened_at from sendoffs where slug = 'maria-r') is not null or true; -- not visible under RLS; checked below
  assert (select count(*) from reveal_contributions('maria-r', current_setting('test.key'))) = 11, 'all approved entries, none hidden, none pending';
  assert (select count(*) from reveal_media('maria-r', current_setting('test.key'))) = 0, 'no media yet';
  assert (select count(*) from sendoff_open('maria-r', 'wrong')) = 0, 'wrong key cannot open';
end $$;

select test_reset() as _ \gset
do $$ begin
  assert (select opened_at from sendoffs where slug = 'maria-r') is not null, 'opened_at stamped';
  assert (select state from sendoffs where slug = 'maria-r') = 'open';
end $$;

-- After the seal, a contributor can no longer add or edit
select test_as('bbbbbbbb-0000-0000-0000-000000000002') as _ \gset
do $$
declare sid uuid; n int;
begin
  select id into sid from sendoff_public('maria-r', current_setting('test.token'));
  begin
    insert into contributions (sendoff_id, author_id, author_name, body) values (sid, 'bbbbbbbb-0000-0000-0000-000000000002', 'Late', 'x');
    raise exception 'insert after open went through';
  exception when insufficient_privilege then null;
  end;
  update contributions set body = 'edited' where author_name = 'Priya';
  get diagnostics n = row_count;
  assert n = 0, 'update after open is a no-op under RLS';
end $$;

-- Review mode: a new entry starts pending and never reaches the recipient
select test_as('aaaaaaaa-0000-0000-0000-000000000001') as _ \gset
insert into sendoffs (slug, organizer_id, occasion, recipient_name, state, moderation, reveal)
values ('mr-patel', 'aaaaaaaa-0000-0000-0000-000000000001', 'teacher', 'Mr. Patel', 'collecting', 'review', 'manual');
do $$
declare t text; k text;
begin
  select contribute_token, recipient_key into t, k from sendoffs where slug = 'mr-patel';
  perform set_config('test.token2', t, true); perform set_config('test.key2', k, true);
end $$;
select test_as('cccccccc-0000-0000-0000-000000000003') as _ \gset
insert into contributions (sendoff_id, author_id, author_name, body)
select id, 'cccccccc-0000-0000-0000-000000000003', 'Parent', 'Thank you.' from sendoff_public('mr-patel', current_setting('test.token2'));
do $$ begin
  assert (select status from contributions where author_name = 'Parent') = 'pending', 'review mode starts pending';
end $$;
select test_as('aaaaaaaa-0000-0000-0000-000000000001') as _ \gset
update sendoffs set state = 'open' where slug = 'mr-patel';
select test_as('dddddddd-0000-0000-0000-000000000004') as _ \gset
do $$ begin
  assert (select count(*) from reveal_contributions('mr-patel', current_setting('test.key2'))) = 0, 'pending entries never reach the recipient';
end $$;

rollback;

drop function test_as(uuid);
drop function test_reset();
\echo rules_test: all assertions passed

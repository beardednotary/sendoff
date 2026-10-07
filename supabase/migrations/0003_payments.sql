-- Sendoff — payments
--
-- Per-Sendoff purchases are StoreKit consumables. The app records each finished transaction as
-- one `entitlements` row per credit (a pack of 5 is five rows) and later redeems a credit against
-- a Sendoff, which raises its plan and entry limit. Premium papers are StoreKit non-consumables
-- and are read from StoreKit on device; they are not mirrored here (yet).
--
-- Trust model for v1: the client inserts its own entitlement rows after StoreKit verifies the
-- transaction on device. Server-side verification of the signed transaction (App Store Server
-- API) is a follow-up; the unique external_id already stops a transaction being credited twice.

-- Free holds 10. Paid plans raise the limit via redeem_entitlement().
alter table sendoffs alter column contributor_limit set default 10;

create or replace function plan_entry_limit(p plan) returns int
language sql immutable as $$
  select case p when 'free' then 10 when 'single' then 100 else 100000 end
$$;

-- One transaction, one credit. Nulls stay allowed for grants and Stripe rows that have no id.
alter table entitlements add constraint entitlements_external_id_key unique (external_id);

create policy "entitlements insert own storekit" on entitlements for insert to authenticated
  with check (user_id = auth.uid() and org_id is null and source = 'storekit' and consumed_by is null);

-- ---------------------------------------------------------------------------
-- Redeem a credit against a Sendoff
-- ---------------------------------------------------------------------------
create or replace function redeem_entitlement(p_entitlement uuid, p_sendoff uuid)
returns setof sendoffs
language plpgsql volatile security definer set search_path = public as $$
declare
  e entitlements%rowtype;
  new_plan plan;
begin
  select * into e from entitlements
   where id = p_entitlement and user_id = auth.uid() and consumed_by is null
     and (expires_at is null or expires_at > now())
   for update;
  if not found then
    raise exception 'entitlement_unavailable' using errcode = 'P0001';
  end if;

  if not exists (select 1 from sendoffs where id = p_sendoff and organizer_id = auth.uid()) then
    raise exception 'not_organizer' using errcode = 'P0001';
  end if;

  new_plan := case e.product_id
    when 'sendoff.single' then 'single'::plan
    when 'sendoff.pack5'  then 'single'::plan
    when 'sendoff.pack10' then 'single'::plan
    when 'sendoff.plus'   then 'plus'::plan
    else null end;
  if new_plan is null then
    raise exception 'not_a_plan_credit' using errcode = 'P0001';
  end if;

  update entitlements set consumed_by = p_sendoff where id = e.id;

  -- Never lower a plan; a single credit on a Plus Sendoff is simply spent.
  update sendoffs
     set plan = new_plan, contributor_limit = plan_entry_limit(new_plan)
   where id = p_sendoff
     and (plan = 'free' or (plan = 'single' and new_plan = 'plus'));

  return query select * from sendoffs where id = p_sendoff;
end $$;

revoke all on function redeem_entitlement(uuid, uuid) from public;
grant execute on function redeem_entitlement(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Enforce the entry limit at insert
-- ---------------------------------------------------------------------------
-- Hidden entries do not count, so the organizer can make room by hiding without paying.
create or replace function enforce_contributor_limit() returns trigger
language plpgsql as $$
declare lim int; n int;
begin
  select contributor_limit into lim from sendoffs where id = new.sendoff_id;
  select count(*) into n from contributions where sendoff_id = new.sendoff_id and status <> 'hidden';
  if n >= coalesce(lim, 10) then
    raise exception 'sendoff_full' using errcode = 'P0001',
      hint = 'The organizer can make room by upgrading or hiding entries.';
  end if;
  return new;
end $$;

drop trigger if exists contributions_limit on contributions;
create trigger contributions_limit before insert on contributions
  for each row execute function enforce_contributor_limit();

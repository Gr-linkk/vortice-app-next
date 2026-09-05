-- Client staff asset visibility.
-- A client/operator/mechanic does not own assets directly. They see vessels
-- through the client organization they work for:
-- profiles.org_id -> client_orgs.id -> client_orgs.owner_profile_id -> assets.client_id.

alter table public.client_orgs enable row level security;
alter table public.assets enable row level security;

-- Let org owners and org members read their org row so app providers can resolve
-- org owner -> assigned client assets.
drop policy if exists "Client org owners read own org" on public.client_orgs;
drop policy if exists "Client org members read own org" on public.client_orgs;

create policy "Client org owners read own org"
on public.client_orgs
for select
to authenticated
using (owner_profile_id = auth.uid());

create policy "Client org members read own org"
on public.client_orgs
for select
to authenticated
using (
  exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.org_id = client_orgs.id
  )
);

-- Let client-side staff see assets belonging to the client org they work for.
-- This is intentionally scoped by org_id; no org_id means no inherited fleet visibility.
drop policy if exists "Client org staff read org assets" on public.assets;

create policy "Client org staff read org assets"
on public.assets
for select
to authenticated
using (
  exists (
    select 1
    from public.profiles p
    join public.client_orgs co on co.id = p.org_id
    where p.id = auth.uid()
      and p.role in ('client_admin', 'client_mechanic', 'client_operator', 'operator')
      and co.owner_profile_id = assets.client_id
  )
);

-- Seed org rows for existing demo/client profiles if missing. This is data repair
-- for the current live demo state where client_orgs was empty.
with client_profiles as (
  select id, coalesce(nullif(full_name, ''), email, 'Client') as name, subscription_tier
  from public.profiles
  where role in ('client', 'client_admin')
), inserted_orgs as (
  insert into public.client_orgs (name, owner_profile_id, subscription_tier, created_at)
  select client_profiles.name || ' Team', client_profiles.id, coalesce(client_profiles.subscription_tier, 0), now()
  from client_profiles
  where not exists (
    select 1
    from public.client_orgs existing
    where existing.owner_profile_id = client_profiles.id
  )
  returning id, owner_profile_id
), all_client_orgs as (
  select id, owner_profile_id from inserted_orgs
  union
  select id, owner_profile_id from public.client_orgs
)
update public.profiles p
set org_id = all_client_orgs.id,
    updated_at = now()
from all_client_orgs
where p.id = all_client_orgs.owner_profile_id
  and p.org_id is distinct from all_client_orgs.id;

-- Current demo field-team accounts should work for the client that owns the dredge.
-- Prefer the Ellicott 460SL asset owner, otherwise fall back to the most recent client profile.
with dredge_client as (
  select client_id
  from public.assets
  where name ilike '%ellicott%'
     or model ilike '%460%'
  order by name
  limit 1
), fallback_client as (
  select id as client_id
  from public.profiles
  where role in ('client', 'client_admin')
  order by created_at desc nulls last, full_name
  limit 1
), target_client as (
  select client_id from dredge_client
  union all
  select client_id from fallback_client
  limit 1
), target_org as (
  select co.id
  from public.client_orgs co
  join target_client tc on tc.client_id = co.owner_profile_id
  limit 1
)
update public.profiles p
set org_id = target_org.id,
    updated_at = now()
from target_org
where p.email in (
    'client_mechanic@vortice.dev',
    'client_operator@vortice.dev',
    'operator@vortice.dev'
  )
  and p.org_id is distinct from target_org.id;

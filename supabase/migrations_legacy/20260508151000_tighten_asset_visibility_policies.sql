-- Tighten legacy asset policies to the current assignment rule:
-- owners manage all assets; clients read only assets assigned via assets.client_id.
-- Operators/org members should not get broad asset visibility from the assets table.

alter table public.assets enable row level security;

-- Older policies from previous app iterations that are broader than the current rule.
drop policy if exists "Client sees own assets" on public.assets;
drop policy if exists "Employee sees assigned assets" on public.assets;
drop policy if exists "Operator sees all assets" on public.assets;
drop policy if exists "Org members see org assets" on public.assets;
drop policy if exists "Owner full access" on public.assets;

-- Keep/recreate canonical policies from the previous migration so the final live
-- policy set is clear and durable.
drop policy if exists "Owners can read all assets" on public.assets;
drop policy if exists "Owners can insert assets" on public.assets;
drop policy if exists "Owners can update assets" on public.assets;
drop policy if exists "Owners can delete assets" on public.assets;
drop policy if exists "Clients can read assigned assets" on public.assets;
drop policy if exists "Service role full access assets" on public.assets;

create policy "Owners can read all assets"
on public.assets
for select
to authenticated
using (
  exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role = 'owner'
  )
);

create policy "Owners can insert assets"
on public.assets
for insert
to authenticated
with check (
  exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role = 'owner'
  )
);

create policy "Owners can update assets"
on public.assets
for update
to authenticated
using (
  exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role = 'owner'
  )
)
with check (
  exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role = 'owner'
  )
);

create policy "Owners can delete assets"
on public.assets
for delete
to authenticated
using (
  exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and p.role = 'owner'
  )
);

create policy "Clients can read assigned assets"
on public.assets
for select
to authenticated
using (client_id = auth.uid());

create policy "Service role full access assets"
on public.assets
for all
to service_role
using (true)
with check (true);

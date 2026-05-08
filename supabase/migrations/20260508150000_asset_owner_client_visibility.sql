-- Asset ownership/assignment visibility.
-- Vórtice owners manage all client assets.
-- Clients only read assets explicitly assigned to their profile via assets.client_id.

alter table public.assets enable row level security;

-- Clean up possible older/partial asset policies so this migration is idempotent-ish
-- across dev databases. Production currently had RLS enabled with no assets policies.
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

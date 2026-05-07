create table if not exists public.saved_checklists (
  id uuid primary key default gen_random_uuid(),
  asset_id uuid not null references public.assets(id) on delete cascade,
  client_id uuid not null references public.profiles(id) on delete cascade,
  template_id uuid references public.checklist_templates(id) on delete set null,
  template_name text not null,
  checklist_type text not null check (checklist_type in ('maintenance', 'operations')),
  source_type text not null,
  submitted_by uuid references public.profiles(id) on delete set null,
  submitted_by_role text,
  submitted_at timestamptz not null default timezone('utc', now()),
  current_hours numeric,
  general_notes text,
  work_order_id uuid references public.work_orders(id) on delete set null,
  assignment_id uuid,
  snapshot jsonb not null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

comment on table public.saved_checklists is
  'Immutable submitted checklist history for assets across maintenance and operations workflows.';

create index if not exists saved_checklists_asset_id_submitted_at_idx
  on public.saved_checklists(asset_id, submitted_at desc);

create index if not exists saved_checklists_client_id_submitted_at_idx
  on public.saved_checklists(client_id, submitted_at desc);

create index if not exists saved_checklists_checklist_type_idx
  on public.saved_checklists(checklist_type);

create index if not exists saved_checklists_source_type_idx
  on public.saved_checklists(source_type);

create index if not exists saved_checklists_work_order_id_idx
  on public.saved_checklists(work_order_id)
  where work_order_id is not null;

alter table public.saved_checklists enable row level security;

create policy "Staff read saved checklists"
  on public.saved_checklists
  for select
  using (
    exists (
      select 1
      from public.profiles p
      where p.id = auth.uid()
        and p.role in ('owner', 'employee')
    )
  );

create policy "Staff submit saved checklists"
  on public.saved_checklists
  for insert
  with check (
    exists (
      select 1
      from public.profiles p
      where p.id = auth.uid()
        and p.role in ('owner', 'employee')
    )
  );

create policy "Clients read own asset saved checklists"
  on public.saved_checklists
  for select
  using (
    exists (
      select 1
      from public.assets a
      where a.id = saved_checklists.asset_id
        and a.client_id = auth.uid()
    )
  );

create policy "Clients submit own asset saved checklists"
  on public.saved_checklists
  for insert
  with check (
    client_id = auth.uid()
    and exists (
      select 1
      from public.assets a
      where a.id = saved_checklists.asset_id
        and a.client_id = auth.uid()
    )
  );

create policy "Org members read associated saved checklists"
  on public.saved_checklists
  for select
  using (
    exists (
      select 1
      from public.assets a
      join public.client_orgs co on co.owner_profile_id = a.client_id
      join public.profiles p on p.org_id = co.id
      where a.id = saved_checklists.asset_id
        and p.id = auth.uid()
        and (
          p.role in ('client_admin', 'client_mechanic')
          or (p.role in ('operator', 'client_operator') and saved_checklists.checklist_type = 'operations')
        )
    )
  );

create policy "Org members submit associated saved checklists"
  on public.saved_checklists
  for insert
  with check (
    exists (
      select 1
      from public.assets a
      join public.client_orgs co on co.owner_profile_id = a.client_id
      join public.profiles p on p.org_id = co.id
      where a.id = saved_checklists.asset_id
        and p.id = auth.uid()
        and a.client_id = saved_checklists.client_id
        and (
          p.role in ('client_admin', 'client_mechanic')
          or (p.role in ('operator', 'client_operator') and saved_checklists.checklist_type = 'operations')
        )
    )
  );

create policy "Service role full access saved checklists"
  on public.saved_checklists
  for all
  using (auth.role() = 'service_role')
  with check (auth.role() = 'service_role');

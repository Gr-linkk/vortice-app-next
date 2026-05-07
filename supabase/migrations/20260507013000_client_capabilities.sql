-- ============================================================
-- Client Capabilities Migration
-- Created: 2026-05-07
-- Purpose: Persist per-client service capability switches.
--
-- Always-on client portal capabilities are intentionally not
-- stored here: assets/documents/history, invoices, and future
-- service requests remain baseline behavior.
-- ============================================================

create table if not exists public.client_capabilities (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.profiles(id) on delete cascade,
  capability_key text not null check (
    capability_key in (
      'operational_checklists',
      'pm_checklists',
      'pm_parts_lists',
      'maintenance_planning',
      'telemetry'
    )
  ),
  enabled boolean not null default false,
  updated_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (client_id, capability_key)
);

comment on table public.client_capabilities is
  'Per-client service capability switches. Missing rows default to disabled in the app.';
comment on column public.client_capabilities.client_id is
  'Client profile id. Mirrors current assets.client_id = profiles.id app model.';
comment on column public.client_capabilities.capability_key is
  'Switch key for optional workflows only; always-on portal capabilities are not stored here.';

create index if not exists client_capabilities_client_id_idx
  on public.client_capabilities(client_id);

create or replace function public.set_client_capabilities_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_client_capabilities_updated_at
  on public.client_capabilities;

create trigger trg_client_capabilities_updated_at
  before update on public.client_capabilities
  for each row
  execute function public.set_client_capabilities_updated_at();

alter table public.client_capabilities enable row level security;

-- Vórtice owner/admin can read all switches.
create policy "Owners can read client capabilities"
  on public.client_capabilities for select
  using (
    exists (
      select 1 from public.profiles
      where id = auth.uid() and role = 'owner'
    )
  );

-- Vórtice owner/admin can create/update/delete switches.
create policy "Owners can manage client capabilities"
  on public.client_capabilities for all
  using (
    exists (
      select 1 from public.profiles
      where id = auth.uid() and role = 'owner'
    )
  )
  with check (
    exists (
      select 1 from public.profiles
      where id = auth.uid() and role = 'owner'
    )
  );

-- Client/profile can see their own enabled/disabled switchboard state.
-- Client org role visibility is deferred until the schema can express it cleanly.
create policy "Clients can read own capabilities"
  on public.client_capabilities for select
  using (client_id = auth.uid());

-- Service role retains full access for admin jobs and backend maintenance.
create policy "Service role full access to client capabilities"
  on public.client_capabilities for all
  using (auth.role() = 'service_role')
  with check (auth.role() = 'service_role');

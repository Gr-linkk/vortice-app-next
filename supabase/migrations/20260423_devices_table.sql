-- Telemetry device pairing table
-- Links a Pi unit (identified by pairing_code) to an asset

create table if not exists public.devices (
  id              uuid primary key default gen_random_uuid(),
  pairing_code    text unique not null,        -- 6-digit string e.g. "482910"
  asset_id        uuid references public.assets(id) on delete set null,
  linked_at       timestamptz,
  linked_by       uuid references public.profiles(id) on delete set null,
  last_seen       timestamptz,
  created_at      timestamptz default now()
);

-- RLS
alter table public.devices enable row level security;

-- Owners can read all devices
create policy "Owners can read devices"
  on public.devices for select
  using (
    exists (
      select 1 from public.profiles
      where id = auth.uid() and role = 'owner'
    )
  );

-- Owners can update devices (for pairing)
create policy "Owners can update devices"
  on public.devices for update
  using (
    exists (
      select 1 from public.profiles
      where id = auth.uid() and role = 'owner'
    )
  );

-- Clients can read their own asset's device
create policy "Clients can read their asset device"
  on public.devices for select
  using (
    asset_id in (
      select id from public.assets
      where client_id = auth.uid()
    )
  );

-- Service role can do anything (for Pi pushing data)
create policy "Service role full access"
  on public.devices for all
  using (auth.role() = 'service_role');

-- Index for fast lookup by pairing code
create index if not exists devices_pairing_code_idx on public.devices(pairing_code);
create index if not exists devices_asset_id_idx on public.devices(asset_id);

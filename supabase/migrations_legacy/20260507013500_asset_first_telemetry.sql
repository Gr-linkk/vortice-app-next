-- ============================================================
-- Asset-first Telemetry Migration
-- Created: 2026-05-07
-- Purpose: Move telemetry ownership from engine-first to asset-first.
--
-- App direction:
-- - asset_id is the canonical telemetry owner and is required.
-- - engine_id is optional metadata for engine/J1939 streams.
-- - device_id remains a first-class source identifier.
-- - gateway/Pi health stays separate in telemetry_gateway_health.
-- - test/bench telemetry tables are intentionally ignored by the app.
--
-- This migration is intentionally schema-only. Do not mix it with
-- collector/runtime changes, test telemetry tables, seed data, or live
-- pairing lifecycle work.
-- ============================================================

-- ============================================================
-- TELEMETRY READINGS: asset_id first-class, engine_id optional
-- ============================================================

alter table public.telemetry_readings
  add column if not exists asset_id uuid references public.assets(id) on delete cascade;

-- Backfill existing engine-owned readings to their parent asset.
update public.telemetry_readings tr
set asset_id = ae.asset_id
from public.asset_engines ae
where tr.asset_id is null
  and tr.engine_id = ae.id;

-- Existing telemetry rows should be backfillable because engine_id was
-- previously NOT NULL. Fail loudly if not; silent orphan telemetry is worse.
do $$
begin
  if exists (select 1 from public.telemetry_readings where asset_id is null) then
    raise exception 'telemetry_readings.asset_id backfill left null rows; repair orphan telemetry before applying asset-first telemetry migration';
  end if;
end;
$$;

alter table public.telemetry_readings
  alter column asset_id set not null;

-- Make engine_id optional and non-destructive. If an engine is deleted, keep
-- the asset-owned telemetry history and clear only the engine pointer.
do $$
declare
  constraint_name text;
begin
  select tc.constraint_name
    into constraint_name
  from information_schema.table_constraints tc
  join information_schema.key_column_usage kcu
    on tc.constraint_name = kcu.constraint_name
   and tc.table_schema = kcu.table_schema
   and tc.table_name = kcu.table_name
  where tc.table_schema = 'public'
    and tc.table_name = 'telemetry_readings'
    and tc.constraint_type = 'FOREIGN KEY'
    and kcu.column_name = 'engine_id'
  limit 1;

  if constraint_name is not null then
    execute format('alter table public.telemetry_readings drop constraint %I', constraint_name);
  end if;
end;
$$;

alter table public.telemetry_readings
  alter column engine_id drop not null,
  add constraint telemetry_readings_engine_id_fkey
    foreign key (engine_id) references public.asset_engines(id) on delete set null;

create index if not exists idx_telemetry_readings_asset_ts
  on public.telemetry_readings(asset_id, ts desc);

create index if not exists idx_telemetry_readings_device_ts
  on public.telemetry_readings(device_id, ts desc)
  where device_id is not null;

-- ============================================================
-- TELEMETRY ALERTS: asset_id first-class, engine_id optional
-- ============================================================

alter table public.telemetry_alerts
  add column if not exists asset_id uuid references public.assets(id) on delete cascade;

update public.telemetry_alerts ta
set asset_id = ae.asset_id
from public.asset_engines ae
where ta.asset_id is null
  and ta.engine_id = ae.id;

do $$
begin
  if exists (select 1 from public.telemetry_alerts where asset_id is null) then
    raise exception 'telemetry_alerts.asset_id backfill left null rows; repair orphan telemetry alerts before applying asset-first telemetry migration';
  end if;
end;
$$;

alter table public.telemetry_alerts
  alter column asset_id set not null;

do $$
declare
  constraint_name text;
begin
  select tc.constraint_name
    into constraint_name
  from information_schema.table_constraints tc
  join information_schema.key_column_usage kcu
    on tc.constraint_name = kcu.constraint_name
   and tc.table_schema = kcu.table_schema
   and tc.table_name = kcu.table_name
  where tc.table_schema = 'public'
    and tc.table_name = 'telemetry_alerts'
    and tc.constraint_type = 'FOREIGN KEY'
    and kcu.column_name = 'engine_id'
  limit 1;

  if constraint_name is not null then
    execute format('alter table public.telemetry_alerts drop constraint %I', constraint_name);
  end if;
end;
$$;

alter table public.telemetry_alerts
  alter column engine_id drop not null,
  add constraint telemetry_alerts_engine_id_fkey
    foreign key (engine_id) references public.asset_engines(id) on delete set null;

create index if not exists idx_telemetry_alerts_asset
  on public.telemetry_alerts(asset_id, created_at desc);

create index if not exists idx_telemetry_alerts_asset_unacked
  on public.telemetry_alerts(asset_id, acknowledged, created_at desc)
  where not acknowledged;

create index if not exists idx_telemetry_alerts_device
  on public.telemetry_alerts(device_id, created_at desc)
  where device_id is not null;

-- ============================================================
-- ROW LEVEL SECURITY: asset-owned telemetry visibility
-- ============================================================

-- Drop known engine-owned / duplicate policies from earlier telemetry iterations.
-- Device insert policies are intentionally preserved for collector compatibility.
drop policy if exists "Owner full access" on public.telemetry_readings;
drop policy if exists "Owner reads all telemetry" on public.telemetry_readings;
drop policy if exists "Owner reads all asset telemetry" on public.telemetry_readings;
drop policy if exists "Owner sees all readings" on public.telemetry_readings;
drop policy if exists "Client reads own asset telemetry" on public.telemetry_readings;
drop policy if exists "Client reads own asset telemetry by asset" on public.telemetry_readings;
drop policy if exists "Client reads own engine telemetry" on public.telemetry_readings;
drop policy if exists "Client sees own readings" on public.telemetry_readings;
drop policy if exists "Employee reads assigned" on public.telemetry_readings;
drop policy if exists "Employee sees all readings" on public.telemetry_readings;
drop policy if exists "Org members see org telemetry readings" on public.telemetry_readings;

drop policy if exists "Owner full access" on public.telemetry_alerts;
drop policy if exists "Owner full access to alerts" on public.telemetry_alerts;
drop policy if exists "Owner full access to asset alerts" on public.telemetry_alerts;
drop policy if exists "Owner sees all alerts" on public.telemetry_alerts;
drop policy if exists "Client reads own asset alerts" on public.telemetry_alerts;
drop policy if exists "Client reads own asset alerts by asset" on public.telemetry_alerts;
drop policy if exists "Client reads own engine alerts" on public.telemetry_alerts;
drop policy if exists "Client sees own alerts" on public.telemetry_alerts;
drop policy if exists "Client acknowledges own alerts" on public.telemetry_alerts;
drop policy if exists "Employee reads assigned alerts" on public.telemetry_alerts;
drop policy if exists "Employee sees all alerts" on public.telemetry_alerts;
drop policy if exists "Org members see org telemetry alerts" on public.telemetry_alerts;

-- telemetry_readings policies
create policy "Owner full access telemetry readings"
  on public.telemetry_readings for all
  using (public.get_my_role() = 'owner')
  with check (public.get_my_role() = 'owner');

create policy "Client reads own asset telemetry readings"
  on public.telemetry_readings for select
  using (
    exists (
      select 1
      from public.assets a
      where a.id = telemetry_readings.asset_id
        and a.client_id = auth.uid()
    )
  );

create policy "Employee reads assigned asset telemetry readings"
  on public.telemetry_readings for select
  using (
    exists (
      select 1
      from public.work_orders wo
      where wo.asset_id = telemetry_readings.asset_id
        and wo.assigned_to = auth.uid()
    )
  );

create policy "Org members read org asset telemetry readings"
  on public.telemetry_readings for select
  using (
    exists (
      select 1
      from public.assets a
      join public.client_orgs co on co.owner_profile_id = a.client_id
      join public.profiles p on p.org_id = co.id
      where a.id = telemetry_readings.asset_id
        and p.id = auth.uid()
        and p.role in ('client_admin', 'client_mechanic', 'client_operator', 'operator')
    )
  );

create policy "Service role full access telemetry readings"
  on public.telemetry_readings for all
  using (auth.role() = 'service_role')
  with check (auth.role() = 'service_role');

-- telemetry_alerts policies
create policy "Owner full access telemetry alerts"
  on public.telemetry_alerts for all
  using (public.get_my_role() = 'owner')
  with check (public.get_my_role() = 'owner');

create policy "Client reads own asset telemetry alerts"
  on public.telemetry_alerts for select
  using (
    exists (
      select 1
      from public.assets a
      where a.id = telemetry_alerts.asset_id
        and a.client_id = auth.uid()
    )
  );

create policy "Employee reads assigned asset telemetry alerts"
  on public.telemetry_alerts for select
  using (
    exists (
      select 1
      from public.work_orders wo
      where wo.asset_id = telemetry_alerts.asset_id
        and wo.assigned_to = auth.uid()
    )
  );

create policy "Org members read org asset telemetry alerts"
  on public.telemetry_alerts for select
  using (
    exists (
      select 1
      from public.assets a
      join public.client_orgs co on co.owner_profile_id = a.client_id
      join public.profiles p on p.org_id = co.id
      where a.id = telemetry_alerts.asset_id
        and p.id = auth.uid()
        and p.role in ('client_admin', 'client_mechanic', 'client_operator', 'operator')
    )
  );

create policy "Service role full access telemetry alerts"
  on public.telemetry_alerts for all
  using (auth.role() = 'service_role')
  with check (auth.role() = 'service_role');

-- ============================================================
-- ENGINE HOURS TRIGGER: tolerate asset-only readings
-- ============================================================

create or replace function public.update_engine_hours_from_telemetry()
returns trigger
language plpgsql
security definer
as $$
begin
  -- Only update engine hours when this reading is tied to a known engine.
  if new.engine_id is not null and new.engine_hours is not null then
    update public.asset_engines
    set
      current_hours = new.engine_hours,
      updated_at = now()
    where id = new.engine_id
      and (current_hours is null or current_hours < new.engine_hours);
  end if;

  return new;
end;
$$;

comment on column public.telemetry_readings.asset_id is
  'Canonical telemetry owner. Required even when engine_id is null.';
comment on column public.telemetry_readings.engine_id is
  'Optional engine/J1939 stream pointer. Telemetry remains asset-owned when null.';
comment on column public.telemetry_alerts.asset_id is
  'Canonical alert owner. Required even when engine_id is null.';
comment on column public.telemetry_alerts.engine_id is
  'Optional engine/J1939 stream pointer. Alerts remain asset-owned when null.';
comment on function public.update_engine_hours_from_telemetry is
  'Auto-updates asset_engines.current_hours only for telemetry rows with a known engine_id.';

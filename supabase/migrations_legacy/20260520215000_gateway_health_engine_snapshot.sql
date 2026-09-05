-- Gateway health prototype engine snapshot fields.
--
-- These fields are intentionally kept on telemetry_gateway_health so service
-- truck / gateway validation data does not enter app-facing telemetry_readings
-- or telemetry_alerts before asset pairing and ingestion rules are explicit.

alter table public.telemetry_gateway_health
  add column if not exists engine_rpm numeric(8,2),
  add column if not exists engine_torque_pct numeric(5,2),
  add column if not exists coolant_temp_c numeric(6,2),
  add column if not exists battery_voltage_v numeric(5,2),
  add column if not exists fuel_rate_lph numeric(8,3),
  add column if not exists engine_hours numeric(10,1),
  add column if not exists active_fault_count integer,
  add column if not exists dm1_faults jsonb;

create index if not exists idx_telemetry_gateway_health_device_ts
  on public.telemetry_gateway_health(device_id, ts desc);

comment on column public.telemetry_gateway_health.engine_rpm is
  'Prototype decoded J1939 engine speed from gateway health snapshots. Not app-facing telemetry_readings.';
comment on column public.telemetry_gateway_health.engine_torque_pct is
  'Prototype decoded J1939 actual engine torque percent from gateway health snapshots.';
comment on column public.telemetry_gateway_health.coolant_temp_c is
  'Prototype decoded J1939 engine coolant temperature in Celsius.';
comment on column public.telemetry_gateway_health.battery_voltage_v is
  'Prototype decoded J1939 battery/electrical potential in volts.';
comment on column public.telemetry_gateway_health.fuel_rate_lph is
  'Prototype decoded J1939 fuel rate in litres per hour.';
comment on column public.telemetry_gateway_health.engine_hours is
  'Prototype decoded J1939 total engine hours.';
comment on column public.telemetry_gateway_health.active_fault_count is
  'Count of active DM1 faults decoded in this gateway health snapshot.';
comment on column public.telemetry_gateway_health.dm1_faults is
  'Decoded DM1 faults as JSON objects containing SPN, FMI, occurrence count, source address, and raw bytes.';

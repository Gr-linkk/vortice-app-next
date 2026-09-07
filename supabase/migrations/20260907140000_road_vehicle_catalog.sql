-- NOW-018 follow-up: additive road vehicle choices, preserving existing rows.
insert into public.asset_types (id, category, name, tracking_unit)
values
  ('00000000-0000-0000-0000-000000000021', 'Road Vehicles', 'LV / Light Vehicle', 'engine_hours'),
  ('00000000-0000-0000-0000-000000000022', 'Road Vehicles', 'Highway Truck', 'engine_hours')
on conflict (id) do nothing;

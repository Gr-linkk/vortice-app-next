-- NOW-018: additive standard asset types. Preserve existing IDs, owner edits,
-- equipment links and policies. Same IDs are used by seed/asset-types.json.
insert into public.asset_types (id, category, name, tracking_unit)
values
  ('00000000-0000-0000-0000-00000000000e', 'Industrial Equipment', 'Pump', 'engine_hours'),
  ('00000000-0000-0000-0000-00000000000f', 'Lifting Equipment', 'Marine Crane', 'engine_hours'),
  ('00000000-0000-0000-0000-000000000010', 'Power Generation', 'Diesel Engine', 'engine_hours'),
  ('00000000-0000-0000-0000-000000000011', 'Marine Vessels', 'RIB / Inflatable Boat', 'engine_hours'),
  ('00000000-0000-0000-0000-000000000012', 'Marine Vessels', 'Aluminum Skiff', 'engine_hours'),
  ('00000000-0000-0000-0000-000000000013', 'Marine Vessels', 'Cabin Cruiser', 'engine_hours'),
  ('00000000-0000-0000-0000-000000000014', 'Commercial Fishing', 'Commercial Trawler', 'engine_hours'),
  ('00000000-0000-0000-0000-000000000015', 'Commercial Fishing', 'Purse Seiner', 'engine_hours'),
  ('00000000-0000-0000-0000-000000000016', 'Marine Vessels', 'Tugboat', 'engine_hours'),
  ('00000000-0000-0000-0000-000000000017', 'Heavy Equipment', 'Backhoe Loader', 'engine_hours'),
  ('00000000-0000-0000-0000-000000000018', 'Heavy Equipment', 'Skid Steer', 'engine_hours'),
  ('00000000-0000-0000-0000-000000000019', 'Heavy Equipment', 'Dump Truck', 'engine_hours'),
  ('00000000-0000-0000-0000-00000000001a', 'Heavy Equipment', 'Motor Grader', 'engine_hours'),
  ('00000000-0000-0000-0000-00000000001b', 'Heavy Equipment', 'Forklift', 'engine_hours'),
  ('00000000-0000-0000-0000-00000000001c', 'Heavy Equipment', 'Telehandler', 'engine_hours'),
  ('00000000-0000-0000-0000-00000000001d', 'Heavy Equipment', 'Road Roller', 'engine_hours'),
  ('00000000-0000-0000-0000-00000000001e', 'Lifting Equipment', 'Mobile Crane', 'engine_hours'),
  ('00000000-0000-0000-0000-00000000001f', 'Lifting Equipment', 'Tower Crane', 'engine_hours'),
  ('00000000-0000-0000-0000-000000000020', 'Lifting Equipment', 'Davit', 'engine_hours')
on conflict (id) do nothing;

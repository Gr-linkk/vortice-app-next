-- Seed/link the dredge daily pre-op checklist to the dredge asset type.
-- Asset Detail checklist picker filters by checklist_templates.asset_type_id,
-- so machine-specific templates must be linked to the machine's asset type.

with dredge_type as (
  select id
  from public.asset_types
  where lower(name) like '%dredge%'
     or lower(coalesce(category, '')) like '%dredge%'
  order by name
  limit 1
)
update public.checklist_templates template
set asset_type_id = dredge_type.id,
    checklist_type = 'operator_daily',
    category = 'pre_ops',
    interval_label = coalesce(template.interval_label, 'Daily Pre-Op'),
    is_active = true,
    updated_at = now()
from dredge_type
where template.name in (
  'Daily Pre-Op — Ellicott 460SL Dredge',
  'Dredge Daily Pre-Op Checklist',
  'Dredge Pre-Op Checklist'
);

with dredge_type as (
  select id
  from public.asset_types
  where lower(name) like '%dredge%'
     or lower(coalesce(category, '')) like '%dredge%'
  order by name
  limit 1
)
insert into public.checklist_templates (
  id,
  asset_type_id,
  checklist_type,
  category,
  interval_label,
  name,
  description,
  version,
  is_active,
  created_at,
  updated_at
)
select
  gen_random_uuid(),
  dredge_type.id,
  'operator_daily',
  'pre_ops',
  'Daily Pre-Op',
  'Daily Pre-Op — Ellicott 460SL Dredge',
  'Operator pre-start and running checks for the Paradise Marina Ellicott 460SL dredge.',
  1,
  true,
  now(),
  now()
from dredge_type
where not exists (
  select 1
  from public.checklist_templates existing
  where existing.name = 'Daily Pre-Op — Ellicott 460SL Dredge'
);

with target_template as (
  select template.id
  from public.checklist_templates template
  join public.asset_types asset_type on asset_type.id = template.asset_type_id
  where template.name = 'Daily Pre-Op — Ellicott 460SL Dredge'
    and (
      lower(asset_type.name) like '%dredge%'
      or lower(coalesce(asset_type.category, '')) like '%dredge%'
    )
  limit 1
), checklist_items(sort_order, category, description_en) as (
  values
    (10, 'Documentation and Logbook', 'Record engine hours'),
    (20, 'Documentation and Logbook', 'Record date and operator name'),
    (30, 'Documentation and Logbook', 'Note operator observations or concerns'),
    (40, 'CAT C15 Engine — Pre-Start', 'Check engine oil level (CAT DEO 10W-30 or 15W-40, 30L capacity)'),
    (50, 'CAT C15 Engine — Pre-Start', 'Check engine coolant level (CAT ELC 50/50 premix, 40L capacity)'),
    (60, 'CAT C15 Engine — Pre-Start', 'Inspect for fuel, oil, and coolant leaks'),
    (70, 'CAT C15 Engine — Pre-Start', 'Check air filter restriction indicator — replace if red'),
    (80, 'CAT C15 Engine — Pre-Start', 'Visual belt inspection — no cracks, fraying, or glazing'),
    (90, 'Hydraulic System', 'Check hydraulic oil filter restriction indicator — replace if indicated'),
    (100, 'Hydraulic System', 'Check hydraulic oil reservoir level (Shell Tellus 46 SM268, 87L capacity)'),
    (110, 'Hydraulic System', 'Inspect hydraulic hoses and fittings for leaks'),
    (120, 'Dredge Pump and Packing Gland', 'Check dredge pump bearing oil level'),
    (130, 'Cutter and Ladder System', 'Grease ladder trunnions (NLGI #2 EP grease)'),
    (140, 'Cutter and Ladder System', 'Grease gimbal / articulation hitch (NLGI #2 EP grease)'),
    (150, 'Cutter and Ladder System', 'Grease swing cylinders — boom arm cylinder grease points'),
    (160, 'Cutter and Ladder System', 'Grease boom raise/lower cylinder grease points'),
    (170, 'Cutter and Ladder System', 'Inspect cutter bits — check for wear'),
    (180, 'Spud System and Carriage', 'Grease spud carriage wheels'),
    (190, 'Spud System and Carriage', 'Check spud planetary oil level — all 3 spuds'),
    (200, 'Spud System and Carriage', 'Grease spud slide guides — all 3 spuds'),
    (210, 'Spud System and Carriage', 'Grease spud fittings — all 3 spuds'),
    (220, 'Spud System and Carriage', 'Inspect saddle clamps / wire rope clamps on spud cables — all 3 spuds'),
    (230, 'Spud System and Carriage', 'Inspect spuds for damage or wear'),
    (240, 'Spud System and Carriage', 'Check carriage cylinder for leaks'),
    (250, 'Fuel System', 'Drain fuel/water separator'),
    (260, 'Fuel System', 'Check fuel tank level — add as required'),
    (270, 'Service Water System', 'Clean raw water strainer'),
    (280, 'Service Water System', 'Check service water pump operation'),
    (290, 'Electrical System', 'Check battery fluid level — add distilled water as required'),
    (300, 'Electrical System', 'Inspect battery terminals for corrosion'),
    (310, 'Wire Rope and Cables', 'Lubricate all wire rope (except swing wire) with cable and open gear compound'),
    (320, 'Wire Rope and Cables', 'Spray rear spud winch cable with WD-40'),
    (330, 'Wire Rope and Cables', 'Grease all 3 winches — 1 grease point each'),
    (340, 'Wire Rope and Cables', 'Inspect winch line cables for fraying or broken strands'),
    (350, 'Hull and Structure', 'Visually check hull void areas for leaks or water accumulation'),
    (360, 'Hull and Structure', 'Check bilge — pump if required'),
    (370, 'Safety and Communications', 'Test horn — verify audible signal operational'),
    (380, 'Safety and Communications', 'Check base radio function — confirm transmit/receive'),
    (390, 'Safety and Communications', 'Check basic operation of lights and controls'),
    (400, 'Safety and Communications', 'Check fire extinguishers — charged and not expired'),
    (410, 'Safety and Communications', 'Verify life jackets present and accessible'),
    (420, 'Running Checks — Engine On', 'Check exhaust color — smoke may indicate coolant or oil issue'),
    (430, 'Running Checks — Engine On', 'Verify alternator charging voltage (26V) — listen for chirps/noise around belt area'),
    (440, 'Running Checks — Engine On', 'Check graphite seal — dripping water (1-2 drips per second)'),
    (450, 'Running Checks — Engine On', 'Listen for unusual pump noise or vibration'),
    (460, 'Running Checks — Engine On', 'Test cutterhead operation'),
    (470, 'Running Checks — Engine On', 'Test safety/navigation lights'),
    (480, 'Final Documentation', 'Log any deficiencies noted'),
    (490, 'Final Documentation', 'Report items requiring immediate attention to supervisor')
)
insert into public.checklist_items (
  id,
  template_id,
  sort_order,
  category,
  description_en,
  requires_photo,
  created_at
)
select
  gen_random_uuid(),
  target_template.id,
  checklist_items.sort_order,
  checklist_items.category,
  checklist_items.description_en,
  false,
  now()
from target_template
cross join checklist_items
where not exists (
  select 1
  from public.checklist_items existing
  where existing.template_id = target_template.id
    and existing.description_en = checklist_items.description_en
);

-- NEXT-002.16: six additional choices; preserve all prior IDs and records.
insert into public.asset_types (id, category, name, tracking_unit)
values
 ('00000000-0000-0000-0000-000000000023', 'Heavy Equipment', 'Compact / Mini Excavator', 'engine_hours'),
 ('00000000-0000-0000-0000-000000000024', 'Heavy Equipment', 'Compact Track Loader', 'engine_hours'),
 ('00000000-0000-0000-0000-000000000025', 'Agriculture & Grounds', 'Agricultural Tractor', 'engine_hours'),
 ('00000000-0000-0000-0000-000000000026', 'Agriculture & Grounds', 'Zero-Turn Mower', 'engine_hours'),
 ('00000000-0000-0000-0000-000000000027', 'Lifting Equipment', 'Boom Lift', 'engine_hours'),
 ('00000000-0000-0000-0000-000000000028', 'Lifting Equipment', 'Scissor Lift', 'engine_hours')
on conflict (id) do nothing;

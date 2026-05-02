-- =============================================================================
-- seed-paradise-marina.sql
-- Seeds Paradise Marina as a Telemetry tier client with the Ellicott 460SL
-- dredge asset + CAT C15 engine + service reminders + PM parts kits
--
-- BEFORE RUNNING:
--   1. Create the Supabase Auth user for Paradise Marina in the Auth UI:
--      Email: paradise@vortice.dev  Password: vortice2026  (or a real email)
--   2. Copy the auth user UUID and replace PARADISE_UUID below
--   3. Run in Supabase Dashboard → SQL Editor
--
-- Safe to re-run (ON CONFLICT guards on all inserts)
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 1: Client profile — Paradise Marina (Telemetry tier = 3)
-- Replace this UUID with the actual auth user UUID after creating in Auth UI
-- ─────────────────────────────────────────────────────────────────────────────

DO $$
DECLARE
  v_client_id   UUID := 'REPLACE_WITH_PARADISE_AUTH_UUID';
  v_owner_id    UUID := 'f33c1b15-f58e-409a-a90f-7c5c233c6bfb';
  v_asset_id    UUID := gen_random_uuid();
  v_engine_id   UUID := gen_random_uuid();

  -- Dredge asset type ID (seeded by seed-checklists.js)
  v_dredge_type_id UUID := '00000000-0000-0000-0000-000000000007';

  -- Checklist template IDs — dredge templates seeded by seed-checklists.js
  -- These match the filenames: dredge-250hr.json, dredge-500hr.json, etc.
  -- Pull actual IDs after confirming templates exist:
  --   SELECT id, name FROM checklist_templates WHERE category = 'dredge';
  v_t250  UUID;
  v_t500  UUID;
  v_t1000 UUID;
  v_t2000 UUID;
  v_t4000 UUID;
  v_t5000 UUID;
  v_thaulout UUID;

  v_r250  UUID := gen_random_uuid();
  v_r500  UUID := gen_random_uuid();
  v_r1000 UUID := gen_random_uuid();
  v_r2000 UUID := gen_random_uuid();
  v_r4000 UUID := gen_random_uuid();
  v_r5000 UUID := gen_random_uuid();
  v_rhaulout UUID := gen_random_uuid();

BEGIN

  -- ── 1. Profile ────────────────────────────────────────────────────────────
  INSERT INTO profiles (id, email, full_name, role, subscription_tier, created_at, updated_at)
  VALUES (
    v_client_id,
    'paradise@vortice.dev',
    'Paradise Marina',
    'client_admin',
    3,  -- Telemetry
    now(), now()
  )
  ON CONFLICT (id) DO UPDATE SET
    full_name = 'Paradise Marina',
    role = 'client_admin',
    subscription_tier = 3;

  RAISE NOTICE 'Profile: Paradise Marina (%))', v_client_id;

  -- ── 2. Asset — Ellicott 460SL ─────────────────────────────────────────────
  INSERT INTO assets (id, name, make, model, year, asset_type_id, client_id, created_at, updated_at)
  VALUES (
    v_asset_id,
    'Ellicott 460SL',
    'Ellicott',
    '460SL',
    2016,
    v_dredge_type_id,
    v_client_id,
    now(), now()
  )
  ON CONFLICT DO NOTHING;

  RAISE NOTICE 'Asset: Ellicott 460SL (%))', v_asset_id;

  -- ── 3. Engine — CAT C15 ───────────────────────────────────────────────────
  INSERT INTO asset_engines (id, asset_id, label, make, model, serial_number, current_hours, created_at, updated_at)
  VALUES (
    v_engine_id,
    v_asset_id,
    'Main Engine',
    'CAT',
    'C15',
    'MCW10441',
    0,  -- set actual hours manually after seeding
    now(), now()
  )
  ON CONFLICT DO NOTHING;

  RAISE NOTICE 'Engine: CAT C15 MCW10441 (%))', v_engine_id;

  -- ── 4. Checklist template IDs ─────────────────────────────────────────────
  -- Fetch dredge templates by name (seeded by seed-checklists.js)
  SELECT id INTO v_t250    FROM checklist_templates WHERE name ILIKE '%dredge%250%' LIMIT 1;
  SELECT id INTO v_t500    FROM checklist_templates WHERE name ILIKE '%dredge%500%' LIMIT 1;
  SELECT id INTO v_t1000   FROM checklist_templates WHERE name ILIKE '%dredge%1000%' LIMIT 1;
  SELECT id INTO v_t2000   FROM checklist_templates WHERE name ILIKE '%dredge%2000%' LIMIT 1;
  SELECT id INTO v_t4000   FROM checklist_templates WHERE name ILIKE '%dredge%4000%' LIMIT 1;
  SELECT id INTO v_t5000   FROM checklist_templates WHERE name ILIKE '%dredge%5000%' LIMIT 1;
  SELECT id INTO v_thaulout FROM checklist_templates WHERE name ILIKE '%dredge%haulout%' LIMIT 1;

  -- ── 5. Service reminders (one per interval) ───────────────────────────────
  -- interval_hours: the service interval
  -- due_at_hours: current hours + interval (start at 0 → first service at interval)
  -- template_id: links to checklist template → PM kits screen uses this

  INSERT INTO service_reminders (id, asset_id, engine_id, interval_hours, due_at_hours, template_id, notes, created_at)
  VALUES
    (v_r250,    v_asset_id, v_engine_id, 250,  250,  v_t250,    'Dredge 250HR PM',  now()),
    (v_r500,    v_asset_id, v_engine_id, 500,  500,  v_t500,    'Dredge 500HR PM',  now()),
    (v_r1000,   v_asset_id, v_engine_id, 1000, 1000, v_t1000,   'Dredge 1000HR PM', now()),
    (v_r2000,   v_asset_id, v_engine_id, 2000, 2000, v_t2000,   'Dredge 2000HR PM', now()),
    (v_r4000,   v_asset_id, v_engine_id, 4000, 4000, v_t4000,   'Dredge 4000HR PM', now()),
    (v_r5000,   v_asset_id, v_engine_id, 5000, 5000, v_t5000,   'Dredge 5000HR PM', now()),
    (v_rhaulout, v_asset_id, v_engine_id, 999999, 999999, v_thaulout, 'Dredge Haulout',  now())
  ON CONFLICT DO NOTHING;

  RAISE NOTICE 'Service reminders: 7 intervals inserted';

  -- ── 6. PM Parts — 250HR ───────────────────────────────────────────────────
  IF v_t250 IS NOT NULL THEN
    INSERT INTO pm_parts_requirements (template_id, description, part_number, qty, unit, notes) VALUES
      (v_t250, 'Engine Oil CAT DEO 10W-30 or 15W-40', NULL,         30,  'L',   NULL),
      (v_t250, 'Engine Oil Filter',                    'CAT 1R-1807', 1,  'ea',  NULL),
      (v_t250, 'Primary Fuel Filter',                  'CAT 326-1643', 1, 'ea',  NULL),
      (v_t250, 'Secondary Fuel Filter',                'CAT 1R-0749', 1,  'ea',  NULL),
      (v_t250, 'CAT ELC Coolant (top-up)',              NULL,          2,  'L',   'Check level, top up only'),
      (v_t250, 'Gasket Sealer / Permatex',              NULL,          1,  'tube','As needed'),
      (v_t250, 'NLGI #2 EP Grease',                    NULL,          1,  'kg',  'Trunnions, gimbal, pivots'),
      (v_t250, 'Shop Rags / Towels',                    NULL,          1,  'pack', NULL)
    ON CONFLICT DO NOTHING;
    RAISE NOTICE 'PM parts: 250HR (8 parts)';
  ELSE
    RAISE WARNING 'Dredge 250HR checklist template not found — skipping parts';
  END IF;

  -- ── 7. PM Parts — 500HR ───────────────────────────────────────────────────
  IF v_t500 IS NOT NULL THEN
    INSERT INTO pm_parts_requirements (template_id, description, part_number, qty, unit, notes) VALUES
      (v_t500, 'Engine Oil CAT DEO',         NULL,            30, 'L',   NULL),
      (v_t500, 'Engine Oil Filter',           'CAT 1R-1807',   1,  'ea',  NULL),
      (v_t500, 'Primary Fuel Filter',         'CAT 326-1643',  1,  'ea',  NULL),
      (v_t500, 'Secondary Fuel Filter',       'CAT 1R-0749',   1,  'ea',  NULL),
      (v_t500, 'Raw Water Pump Impeller',     NULL,             1,  'ea',  'PN needs Ellicott lookup'),
      (v_t500, 'Hydraulic Filter',            'Sakura H-5517', 1,  'ea',  NULL),
      (v_t500, 'Dredge Pump Bearing Oil',     NULL,             1,  'L',   'Drain + refill — confirm qty from pump manual'),
      (v_t500, 'Packing Gland Rope Packing',  NULL,             1,  'set', 'Replace if worn'),
      (v_t500, 'Anti-Seize Compound',         NULL,             1,  'tube','Cutter shaft threads'),
      (v_t500, 'NLGI #2 EP Grease',           NULL,             1,  'kg',  NULL),
      (v_t500, 'SAE 50 Oil (spud winch bearings)', NULL,        1,  'L',   'Confirm qty')
    ON CONFLICT DO NOTHING;
    RAISE NOTICE 'PM parts: 500HR (11 parts)';
  ELSE
    RAISE WARNING 'Dredge 500HR checklist template not found — skipping parts';
  END IF;

  -- ── 8. PM Parts — 1000HR ──────────────────────────────────────────────────
  IF v_t1000 IS NOT NULL THEN
    INSERT INTO pm_parts_requirements (template_id, description, part_number, qty, unit, notes) VALUES
      (v_t1000, 'Engine Oil CAT DEO',              NULL,              30,  'L',   NULL),
      (v_t1000, 'Engine Oil Filter',                'CAT 1R-1807',     1,   'ea',  NULL),
      (v_t1000, 'Primary Fuel Filter',              'CAT 326-1643',    1,   'ea',  NULL),
      (v_t1000, 'Secondary Fuel Filter',            'CAT 1R-0749',     1,   'ea',  NULL),
      (v_t1000, 'Hydraulic Filter',                 'Sakura H-5517',   2,   'ea',  NULL),
      (v_t1000, 'Hydraulic Oil Shell Tellus 46 SM268', NULL,           87,  'L',   'Full drain + flush'),
      (v_t1000, 'CAT ELC Coolant 50/50',            NULL,              40,  'L',   'Full flush'),
      (v_t1000, 'Thermostat',                       'CAT 2477133',     1,   'ea',  '190°F'),
      (v_t1000, 'Coolant Hoses (set)',               NULL,              1,   'set', 'Replace if cracked/soft'),
      (v_t1000, 'Air Filter Primary Element',        'CAT 6I-2501',    1,   'ea',  NULL),
      (v_t1000, 'Air Filter Safety Element',         'CAT 6I-2499',    1,   'ea',  NULL),
      (v_t1000, 'Reduction Gearbox Oil SAE-40',      NULL,             7.6, 'L',   'Marine transmission'),
      (v_t1000, 'Winch Planetary Reducer Oil SAE 90-EP', NULL,         1.3, 'L',   '× 3 winches (Shell Omala 220)'),
      (v_t1000, 'Cutter Reducer Oil SAE 90-EP',      NULL,             1,   'L',   NULL),
      (v_t1000, 'Engine Mounts (set)',                NULL,             1,   'set', 'PN: CAT dealer lookup by SN MCW10441'),
      (v_t1000, 'Wire Rope Lubricant / Open Gear Compound', NULL,      1,   'can', 'All wire ropes'),
      (v_t1000, 'NLGI #2 EP Grease',                 NULL,             2,   'kg',  NULL),
      (v_t1000, 'Anodes (set)',                       NULL,             1,   'set', 'Haulout — check + replace'),
      (v_t1000, 'Bottom Paint',                       NULL,             1,   'set', 'Haulout — qty TBD')
    ON CONFLICT DO NOTHING;
    RAISE NOTICE 'PM parts: 1000HR (19 parts)';
  ELSE
    RAISE WARNING 'Dredge 1000HR checklist template not found — skipping parts';
  END IF;

  -- ── 9. PM Parts — 2000HR ──────────────────────────────────────────────────
  IF v_t2000 IS NOT NULL THEN
    INSERT INTO pm_parts_requirements (template_id, description, part_number, qty, unit, notes) VALUES
      (v_t2000, 'Engine Oil CAT DEO',              NULL,              30,  'L',   NULL),
      (v_t2000, 'Engine Oil Filter',                'CAT 1R-1807',     1,   'ea',  NULL),
      (v_t2000, 'Primary Fuel Filter',              'CAT 326-1643',    2,   'ea',  NULL),
      (v_t2000, 'Secondary Fuel Filter',            'CAT 1R-0749',     2,   'ea',  NULL),
      (v_t2000, 'Hydraulic Filter',                 'Sakura H-5517',   2,   'ea',  NULL),
      (v_t2000, 'Hydraulic Oil Shell Tellus 46 SM268', NULL,           87,  'L',   NULL),
      (v_t2000, 'CAT ELC Coolant 50/50',            NULL,              40,  'L',   NULL),
      (v_t2000, 'Thermostat',                       'CAT 2477133',     1,   'ea',  NULL),
      (v_t2000, 'Coolant Hoses (set)',               NULL,              1,   'set', NULL),
      (v_t2000, 'Air Filter Primary Element',        'CAT 6I-2501',    1,   'ea',  NULL),
      (v_t2000, 'Air Filter Safety Element',         'CAT 6I-2499',    1,   'ea',  NULL),
      (v_t2000, 'Engine Mounts (set)',               NULL,              1,   'set', 'PN: CAT dealer lookup SN MCW10441'),
      (v_t2000, 'Water Pump Seal Kit',               NULL,              1,   'ea',  'PN: dealer lookup'),
      (v_t2000, 'Engine Gasket Set (partial)',        NULL,              1,   'set', 'PN: dealer lookup'),
      (v_t2000, 'Cutterhead Teeth (set)',             NULL,              1,   'set', 'PN: Ellicott lookup'),
      (v_t2000, 'Anodes (set)',                       NULL,             1,   'set', NULL),
      (v_t2000, 'Hydraulic Cylinder Seal Kits',       NULL,             1,   'set', 'As needed'),
      (v_t2000, 'Fuel Polishing / Tank Cleaning Supplies', NULL,        1,   'set', 'If contamination found'),
      (v_t2000, 'NLGI #2 EP Grease',                 NULL,             2,   'kg',  NULL),
      (v_t2000, 'Loctite / Thread Sealant',           NULL,             1,   'set', NULL)
    ON CONFLICT DO NOTHING;
    RAISE NOTICE 'PM parts: 2000HR (20 parts)';
  ELSE
    RAISE WARNING 'Dredge 2000HR checklist template not found — skipping parts';
  END IF;

  -- ── 10. PM Parts — 4000HR ─────────────────────────────────────────────────
  IF v_t4000 IS NOT NULL THEN
    INSERT INTO pm_parts_requirements (template_id, description, part_number, qty, unit, notes) VALUES
      (v_t4000, 'Engine Oil CAT DEO',              NULL,              30,  'L',   NULL),
      (v_t4000, 'Engine Oil Filter',                'CAT 1R-1807',     1,   'ea',  NULL),
      (v_t4000, 'Primary Fuel Filter',              'CAT 326-1643',    2,   'ea',  NULL),
      (v_t4000, 'Secondary Fuel Filter',            'CAT 1R-0749',     2,   'ea',  NULL),
      (v_t4000, 'Hydraulic Filter',                 'Sakura H-5517',   4,   'ea',  NULL),
      (v_t4000, 'Hydraulic Oil Shell Tellus 46 SM268', NULL,           87,  'L',   NULL),
      (v_t4000, 'CAT ELC Coolant 50/50',            NULL,              40,  'L',   NULL),
      (v_t4000, 'Turbocharger (rebuild or replace)', NULL,              1,   'ea',  'PN: dealer lookup — confirm rebuild vs replace'),
      (v_t4000, 'Water Pump Assembly',               'CAT 161-5718',   1,   'ea',  NULL),
      (v_t4000, 'Thermostat',                       'CAT 2477133',     1,   'ea',  NULL),
      (v_t4000, 'Serpentine Belt',                  'CAT 349-3353',    1,   'ea',  NULL),
      (v_t4000, 'Belt Tensioners & Pulleys (set)',   NULL,              1,   'set', 'PN: dealer lookup'),
      (v_t4000, 'Coolant Hoses & Clamps (set)',      NULL,              1,   'set', 'Full replacement'),
      (v_t4000, 'Engine Mounts (set)',               NULL,              1,   'set', 'PN: dealer lookup'),
      (v_t4000, 'Crankshaft Vibration Damper',       NULL,              1,   'ea',  'PN: dealer lookup (PDI aftermarket fits C15)'),
      (v_t4000, 'Air Filter Primary Element',        'CAT 6I-2501',    1,   'ea',  NULL),
      (v_t4000, 'Air Filter Safety Element',         'CAT 6I-2499',    1,   'ea',  NULL),
      (v_t4000, 'Head Gasket',                       NULL,              1,   'ea',  'PN: dealer lookup'),
      (v_t4000, 'Valve Seals (set)',                  NULL,             1,   'set', 'PN: dealer lookup'),
      (v_t4000, 'Cylinder Head Bolts (set)',          NULL,             1,   'set', 'PN: dealer lookup'),
      (v_t4000, 'Hydraulic Cylinder Seal Kits (set)', NULL,            1,   'set', 'All cylinders'),
      (v_t4000, 'Swing Ladder Pins & Bushings (set)', NULL,            1,   'set', 'PN: Ellicott lookup'),
      (v_t4000, 'Cutterhead Teeth & Holders (set)',   NULL,            1,   'set', 'PN: Ellicott lookup'),
      (v_t4000, 'Cutterhead Bearing',                 NULL,            1,   'ea',  'PN: Ellicott lookup'),
      (v_t4000, 'Batteries 24V Bank',                 NULL,            1,   'set', 'Replace all'),
      (v_t4000, 'All Hydraulic Hoses (set)',           NULL,           1,   'set', 'Full replacement'),
      (v_t4000, 'All Fuel Lines (set)',                NULL,           1,   'set', 'Full replacement'),
      (v_t4000, 'Hull Sandblast Media + Bottom Paint', NULL,           1,   'set', NULL),
      (v_t4000, 'Weld Consumables (electrodes, wire)', NULL,           1,   'set', 'Structural repairs'),
      (v_t4000, 'NLGI #2 EP Grease (bulk)',            NULL,           5,   'kg',  'All pivot points'),
      (v_t4000, 'Loctite / Thread Sealant Set',        NULL,           1,   'set', NULL)
    ON CONFLICT DO NOTHING;
    RAISE NOTICE 'PM parts: 4000HR (31 parts)';
  ELSE
    RAISE WARNING 'Dredge 4000HR checklist template not found — skipping parts';
  END IF;

  -- ── 11. PM Parts — 5000HR ─────────────────────────────────────────────────
  IF v_t5000 IS NOT NULL THEN
    INSERT INTO pm_parts_requirements (template_id, description, part_number, qty, unit, notes) VALUES
      (v_t5000, 'Engine Oil CAT DEO',              NULL,              30,  'L',   NULL),
      (v_t5000, 'Engine Oil Filter',                'CAT 1R-1807',     1,   'ea',  NULL),
      (v_t5000, 'Primary Fuel Filter',              'CAT 326-1643',    1,   'ea',  NULL),
      (v_t5000, 'Secondary Fuel Filter',            'CAT 1R-0749',     1,   'ea',  NULL),
      (v_t5000, 'CAT ELC Coolant 50/50',            NULL,              40,  'L',   NULL),
      (v_t5000, 'Hydraulic Oil Shell Tellus 46 SM268', NULL,           87,  'L',   NULL),
      (v_t5000, 'Hydraulic Filter',                 'Sakura H-5517',   2,   'ea',  NULL),
      (v_t5000, 'Reduction Gearbox Oil SAE-40',      NULL,             7.6, 'L',   NULL),
      (v_t5000, 'Winch Planetary Reducer Oil SAE 90-EP', NULL,         1.3, 'L',   '× 3 winches'),
      (v_t5000, 'NLGI #2 EP Grease',                 NULL,             2,   'kg',  NULL)
    ON CONFLICT DO NOTHING;
    RAISE NOTICE 'PM parts: 5000HR (10 parts)';
  ELSE
    RAISE WARNING 'Dredge 5000HR checklist template not found — skipping parts';
  END IF;

  -- ── 12. PM Parts — Haulout ────────────────────────────────────────────────
  IF v_thaulout IS NOT NULL THEN
    INSERT INTO pm_parts_requirements (template_id, description, part_number, qty, unit, notes) VALUES
      (v_thaulout, 'Anodes (set)',                    NULL,            1,   'set', 'Full replacement'),
      (v_thaulout, 'Hydraulic Filter',                'Sakura H-5517', 1,   'ea',  NULL),
      (v_thaulout, 'Cutterhead Bits / Teeth (set)',   NULL,            1,   'set', 'PN: Ellicott lookup'),
      (v_thaulout, 'Bottom Paint',                    NULL,            1,   'set', 'Measure hull area for qty'),
      (v_thaulout, 'Ladder Pins & Bushings',           NULL,           1,   'set', 'Inspect, replace if worn'),
      (v_thaulout, 'Hull Weld Consumables',            NULL,           1,   'set', 'As needed'),
      (v_thaulout, 'NLGI #2 EP Grease',               NULL,           2,   'kg',  NULL)
    ON CONFLICT DO NOTHING;
    RAISE NOTICE 'PM parts: Haulout (7 parts)';
  ELSE
    RAISE WARNING 'Dredge Haulout checklist template not found — skipping parts';
  END IF;

  RAISE NOTICE '✅ Paradise Marina seed complete.';
  RAISE NOTICE 'Next steps:';
  RAISE NOTICE '  1. Set actual engine hours on asset_engines where id = %', v_engine_id;
  RAISE NOTICE '  2. Update due_at_hours on service_reminders for each interval (current hours + interval)';
  RAISE NOTICE '  3. Verify checklist templates were found (check for WARNINGs above)';

END $$;

-- =============================================================================
-- Verify — run this after the block above to confirm everything landed
-- =============================================================================
/*
SELECT p.full_name, p.role, p.subscription_tier,
       a.name as asset, ae.make, ae.model, ae.serial_number,
       count(sr.id) as reminders
FROM profiles p
JOIN assets a ON a.client_id = p.id
JOIN asset_engines ae ON ae.asset_id = a.id
LEFT JOIN service_reminders sr ON sr.asset_id = a.id
WHERE p.full_name = 'Paradise Marina'
GROUP BY p.full_name, p.role, p.subscription_tier, a.name, ae.make, ae.model, ae.serial_number;

-- Check PM parts counts per interval
SELECT ct.name, count(ppr.id) as parts_count
FROM checklist_templates ct
JOIN pm_parts_requirements ppr ON ppr.template_id = ct.id
WHERE ct.category = 'dredge'
GROUP BY ct.name ORDER BY ct.name;
*/

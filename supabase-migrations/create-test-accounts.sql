-- =============================================================================
-- create-test-accounts.sql
-- Dev/test account profiles for Vórtice Mechanical
-- =============================================================================
--
-- IMPORTANT: Supabase auth users must be created FIRST via the Auth UI or
-- Admin API before running this SQL.
--
--   Authentication → Users → Invite User (or Add User)
--   Email: <email below>   Password: vortice2026
--
-- Once all auth users exist, run this script to set their profile rows
-- (role, tier, display name). Uses ON CONFLICT so it's safe to re-run.
-- Replace the placeholder UUIDs with the actual auth user UUIDs from
-- Authentication → Users after creation.
-- =============================================================================

-- owner@vortice.dev — Business owner
INSERT INTO profiles (id, email, full_name, role, subscription_tier, created_at, updated_at)
VALUES (
  '00000000-0000-0000-0000-000000000010', -- replace with actual UUID
  'owner@vortice.dev',
  'Vortice Owner',
  'owner',
  0,
  now(),
  now()
) ON CONFLICT (id) DO UPDATE SET role = 'owner', full_name = 'Vortice Owner';

-- tech1@vortice.dev — Tech account #1
INSERT INTO profiles (id, email, full_name, role, subscription_tier, created_at, updated_at)
VALUES (
  '00000000-0000-0000-0000-000000000011', -- replace with actual UUID
  'tech1@vortice.dev',
  'Tech One',
  'employee',
  0,
  now(),
  now()
) ON CONFLICT (id) DO UPDATE SET role = 'employee', full_name = 'Tech One';

-- tech2@vortice.dev
INSERT INTO profiles (id, email, full_name, role, subscription_tier, created_at, updated_at)
VALUES (
  '00000000-0000-0000-0000-000000000012', -- replace with actual UUID
  'tech2@vortice.dev',
  'Tech Two',
  'employee',
  0,
  now(),
  now()
) ON CONFLICT (id) DO UPDATE SET role = 'employee', full_name = 'Tech Two';

-- client_planning@vortice.dev — Planning tier client
INSERT INTO profiles (id, email, full_name, role, subscription_tier, created_at, updated_at)
VALUES (
  '00000000-0000-0000-0000-000000000013', -- replace with actual UUID
  'client_planning@vortice.dev',
  'Planning Client',
  'client_admin',
  2,
  now(),
  now()
) ON CONFLICT (id) DO UPDATE SET role = 'client_admin', subscription_tier = 2;

-- client_telemetry@vortice.dev — Telemetry tier client
INSERT INTO profiles (id, email, full_name, role, subscription_tier, created_at, updated_at)
VALUES (
  '00000000-0000-0000-0000-000000000014', -- replace with actual UUID
  'client_telemetry@vortice.dev',
  'Telemetry Client',
  'client_admin',
  3,
  now(),
  now()
) ON CONFLICT (id) DO UPDATE SET role = 'client_admin', subscription_tier = 3;

-- client_mechanic@vortice.dev — Easter egg tap 6
INSERT INTO profiles (id, email, full_name, role, subscription_tier, created_at, updated_at)
VALUES (
  '00000000-0000-0000-0000-000000000015', -- replace with actual UUID
  'client_mechanic@vortice.dev',
  'Client Mechanic',
  'client_mechanic',
  2,
  now(),
  now()
) ON CONFLICT (id) DO UPDATE SET role = 'client_mechanic', subscription_tier = 2;

-- client_operator@vortice.dev — Easter egg tap 7
INSERT INTO profiles (id, email, full_name, role, subscription_tier, created_at, updated_at)
VALUES (
  '00000000-0000-0000-0000-000000000016', -- replace with actual UUID
  'client_operator@vortice.dev',
  'Client Operator',
  'client_operator',
  2,
  now(),
  now()
) ON CONFLICT (id) DO UPDATE SET role = 'client_operator', subscription_tier = 2;

-- client_admin@vortice.dev — Easter egg tap 5 (Planning tier)
-- Note: client@vortice.dev and operator@vortice.dev profiles should already
-- exist from initial seeding. Add here if re-seeding from scratch:
--
-- INSERT INTO profiles (id, email, full_name, role, subscription_tier, ...)
-- VALUES ('...', 'client@vortice.dev', 'Test Client', 'client_admin', 1, now(), now())
-- ON CONFLICT (id) DO UPDATE SET role = 'client_admin';
--
-- INSERT INTO profiles (id, email, full_name, role, subscription_tier, ...)
-- VALUES ('...', 'operator@vortice.dev', 'Test Operator', 'client_operator', 1, now(), now())
-- ON CONFLICT (id) DO UPDATE SET role = 'client_operator';

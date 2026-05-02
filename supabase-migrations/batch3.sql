-- ── Batch 3 Migrations ──────────────────────────────────────────────────────

-- 1. Add org_id to profiles (links a user to their client org)
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS org_id UUID REFERENCES client_orgs(id) ON DELETE SET NULL;

-- 2. Add org_id to org_codes (org-scoped invite codes)
ALTER TABLE org_codes ADD COLUMN IF NOT EXISTS org_id UUID REFERENCES client_orgs(id) ON DELETE CASCADE;

-- 3. Index for fast member lookup
CREATE INDEX IF NOT EXISTS idx_profiles_org_id ON profiles(org_id);

-- 4. Index for org invite code lookup
CREATE INDEX IF NOT EXISTS idx_org_codes_org_id ON org_codes(org_id);

-- 5. Update the profile creation trigger to respect org_id from metadata
-- If a user registers with an org-scoped code, the trigger should set their org_id.
-- This assumes you have a trigger on auth.users that creates profiles.
-- Update the trigger function to include org_id:
--
-- CREATE OR REPLACE FUNCTION public.handle_new_user()
-- RETURNS trigger AS $$
-- DECLARE
--   v_org_id UUID;
--   v_org_code TEXT;
--   v_intended_role TEXT;
-- BEGIN
--   -- Look up the org code if provided
--   v_org_code := NEW.raw_user_meta_data->>'org_code_used';
--   IF v_org_code IS NOT NULL THEN
--     SELECT org_id, intended_role
--     INTO v_org_id, v_intended_role
--     FROM org_codes
--     WHERE code = UPPER(v_org_code)
--     LIMIT 1;
--   END IF;
--
--   INSERT INTO public.profiles (
--     id, email, full_name, role, org_id, org_code_used,
--     preferred_language, subscription_tier, created_at, updated_at
--   )
--   VALUES (
--     NEW.id,
--     NEW.email,
--     COALESCE(NEW.raw_user_meta_data->>'full_name', ''),
--     COALESCE(v_intended_role, NEW.raw_user_meta_data->>'role', 'client'),
--     v_org_id,
--     v_org_code,
--     COALESCE(NEW.raw_user_meta_data->>'preferred_language', 'en'),
--     COALESCE((NEW.raw_user_meta_data->>'subscription_tier')::int, 0),
--     NOW(),
--     NOW()
--   );
--   RETURN NEW;
-- END;
-- $$ LANGUAGE plpgsql SECURITY DEFINER;

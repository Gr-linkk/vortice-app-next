-- Batch 1 migrations: multi-tech assignments, client orgs, meeting requests

-- Multi-tech assignment table
CREATE TABLE IF NOT EXISTS work_order_assignments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  work_order_id UUID NOT NULL REFERENCES work_orders(id) ON DELETE CASCADE,
  profile_id UUID NOT NULL REFERENCES profiles(id),
  role TEXT NOT NULL DEFAULT 'tech', -- 'tech' or 'client_mechanic'
  hours_logged DOUBLE PRECISION,
  billable_rate DOUBLE PRECISION,
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(work_order_id, profile_id)
);

-- Enable RLS
ALTER TABLE work_order_assignments ENABLE ROW LEVEL SECURITY;

-- Policies
CREATE POLICY "Owner sees all assignments" ON work_order_assignments
  FOR ALL USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'owner')
  );

CREATE POLICY "Employee sees all assignments" ON work_order_assignments
  FOR ALL USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'employee')
  );

CREATE POLICY "Tech sees own assignments" ON work_order_assignments
  FOR SELECT USING (profile_id = auth.uid());

-- Add billable_rate to profiles for per-tech rates
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS billable_rate DOUBLE PRECISION;

-- Client orgs table (needed for Planning+ tier)
CREATE TABLE IF NOT EXISTS client_orgs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  owner_profile_id UUID NOT NULL REFERENCES profiles(id),
  subscription_tier INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE client_orgs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Owner manages all orgs" ON client_orgs
  FOR ALL USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'owner')
  );

-- Add org_id to profiles
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS org_id UUID REFERENCES client_orgs(id);

-- Meeting requests table
CREATE TABLE IF NOT EXISTS meeting_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id UUID NOT NULL REFERENCES profiles(id),
  interest TEXT, -- 'routine_maintenance', 'repair', 'fleet_management', 'telemetry', 'other'
  vessel_count TEXT, -- '1', '2-5', '5+'
  contact_method TEXT, -- 'whatsapp', 'email', 'phone'
  notes TEXT,
  status TEXT NOT NULL DEFAULT 'pending', -- 'pending', 'contacted', 'closed'
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE meeting_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Owner sees all meeting requests" ON meeting_requests
  FOR ALL USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'owner')
  );

CREATE POLICY "Client creates own meeting requests" ON meeting_requests
  FOR INSERT WITH CHECK (profile_id = auth.uid());

CREATE POLICY "Client sees own meeting requests" ON meeting_requests
  FOR SELECT USING (profile_id = auth.uid());

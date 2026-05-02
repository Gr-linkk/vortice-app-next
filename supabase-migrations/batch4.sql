-- ── Batch 4 Migrations ──────────────────────────────────────────────────────

-- 1. Add alert_source and severity to telemetry_alerts if not present
ALTER TABLE telemetry_alerts ADD COLUMN IF NOT EXISTS alert_source TEXT DEFAULT 'system';
ALTER TABLE telemetry_alerts ADD COLUMN IF NOT EXISTS severity TEXT DEFAULT 'warning';
ALTER TABLE telemetry_alerts ADD COLUMN IF NOT EXISTS message TEXT;
ALTER TABLE telemetry_alerts ADD COLUMN IF NOT EXISTS acknowledged_at TIMESTAMPTZ;
ALTER TABLE telemetry_alerts ADD COLUMN IF NOT EXISTS acknowledged_by UUID REFERENCES profiles(id);

-- 2. RLS for telemetry_alerts
ALTER TABLE telemetry_alerts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Owner sees all alerts" ON telemetry_alerts;
CREATE POLICY "Owner sees all alerts" ON telemetry_alerts
  FOR ALL USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'owner')
  );

DROP POLICY IF EXISTS "Employee sees all alerts" ON telemetry_alerts;
CREATE POLICY "Employee sees all alerts" ON telemetry_alerts
  FOR ALL USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'employee')
  );

-- Clients see alerts for engines on their assets
DROP POLICY IF EXISTS "Client sees own alerts" ON telemetry_alerts;
CREATE POLICY "Client sees own alerts" ON telemetry_alerts
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM asset_engines ae
      JOIN assets a ON ae.asset_id = a.id
      WHERE ae.id = telemetry_alerts.engine_id
        AND a.client_id = auth.uid()
    )
  );

-- 3. RLS for telemetry_readings
ALTER TABLE telemetry_readings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Owner sees all readings" ON telemetry_readings;
CREATE POLICY "Owner sees all readings" ON telemetry_readings
  FOR ALL USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'owner')
  );

DROP POLICY IF EXISTS "Employee sees all readings" ON telemetry_readings;
CREATE POLICY "Employee sees all readings" ON telemetry_readings
  FOR ALL USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'employee')
  );

DROP POLICY IF EXISTS "Client sees own readings" ON telemetry_readings;
CREATE POLICY "Client sees own readings" ON telemetry_readings
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM asset_engines ae
      JOIN assets a ON ae.asset_id = a.id
      WHERE ae.id = telemetry_readings.engine_id
        AND a.client_id = auth.uid()
    )
  );

-- 4. Index for fast engine-based alert lookup
CREATE INDEX IF NOT EXISTS idx_telemetry_alerts_engine_id ON telemetry_alerts(engine_id);
CREATE INDEX IF NOT EXISTS idx_telemetry_alerts_acknowledged ON telemetry_alerts(acknowledged);
CREATE INDEX IF NOT EXISTS idx_telemetry_readings_engine_ts ON telemetry_readings(engine_id, ts DESC);

-- ============================================================
-- Telemetry Tables Migration
-- Created: 2026-04-19
-- Purpose: Add telemetry_readings and telemetry_alerts tables
--          for engine telemetry data from J1939/NMEA sources
-- ============================================================

-- ============================================================
-- TELEMETRY READINGS TABLE
-- Stores periodic engine telemetry snapshots
-- ============================================================

CREATE TABLE telemetry_readings (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  engine_id UUID REFERENCES asset_engines(id) ON DELETE CASCADE NOT NULL,
  ts TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Core engine parameters
  rpm NUMERIC(8,2),
  coolant_temp NUMERIC(6,2),          -- Celsius
  oil_pressure NUMERIC(6,2),          -- PSI or kPa
  battery_v NUMERIC(5,2),             -- Volts
  boost_psi NUMERIC(6,2),             -- PSI
  throttle_pct NUMERIC(5,2),          -- 0-100%
  fuel_rate NUMERIC(8,3),             -- L/hr or gal/hr
  torque_pct NUMERIC(5,2),            -- 0-100%

  -- Engine hours (for auto-update)
  engine_hours NUMERIC(10,1),

  -- Additional diagnostics
  intake_temp NUMERIC(6,2),           -- Celsius
  exhaust_temp NUMERIC(6,2),          -- Celsius
  oil_temp NUMERIC(6,2),              -- Celsius
  fuel_pressure NUMERIC(6,2),         -- PSI
  transmission_temp NUMERIC(6,2),     -- Celsius
  transmission_pressure NUMERIC(6,2), -- PSI

  -- Raw data for debugging
  raw_data JSONB,

  -- Source tracking
  source TEXT,                        -- e.g., 'j1939', 'nmea2000', 'modbus'
  device_id TEXT,                     -- Hardware device identifier

  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for efficient time-series queries
CREATE INDEX idx_telemetry_readings_engine_ts
  ON telemetry_readings(engine_id, ts DESC);

-- Index for querying by timestamp
CREATE INDEX idx_telemetry_readings_ts
  ON telemetry_readings(ts DESC);

-- ============================================================
-- TELEMETRY ALERTS TABLE
-- Stores diagnostic trouble codes and threshold alerts
-- ============================================================

CREATE TABLE telemetry_alerts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  engine_id UUID REFERENCES asset_engines(id) ON DELETE CASCADE NOT NULL,

  -- Alert classification
  alert_type TEXT NOT NULL CHECK (
    alert_type IN ('dtc', 'threshold', 'warning', 'critical', 'info')
  ),

  -- J1939 DTC fields (SPN/FMI)
  spn INT,                            -- Suspect Parameter Number
  fmi INT,                            -- Failure Mode Identifier

  -- Threshold alert details
  parameter TEXT,                     -- e.g., 'coolant_temp', 'oil_pressure'
  value NUMERIC(10,2),                -- Current value
  threshold NUMERIC(10,2),            -- Threshold that was exceeded
  comparison TEXT CHECK (comparison IN ('gt', 'lt', 'gte', 'lte', 'eq')),

  -- Alert metadata
  message TEXT,                       -- Human-readable description
  severity TEXT DEFAULT 'warning' CHECK (
    severity IN ('info', 'warning', 'critical')
  ),

  -- Status tracking
  acknowledged BOOLEAN DEFAULT FALSE,
  acknowledged_by UUID REFERENCES profiles(id),
  acknowledged_at TIMESTAMPTZ,
  resolved BOOLEAN DEFAULT FALSE,
  resolved_at TIMESTAMPTZ,

  -- Source tracking
  source TEXT,
  device_id TEXT,
  raw_data JSONB,

  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for unacknowledged alerts
CREATE INDEX idx_telemetry_alerts_unacked
  ON telemetry_alerts(engine_id, acknowledged, created_at DESC)
  WHERE NOT acknowledged;

-- Index for engine alerts
CREATE INDEX idx_telemetry_alerts_engine
  ON telemetry_alerts(engine_id, created_at DESC);

-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================

ALTER TABLE telemetry_readings ENABLE ROW LEVEL SECURITY;
ALTER TABLE telemetry_alerts ENABLE ROW LEVEL SECURITY;

-- telemetry_readings policies
CREATE POLICY "Owner full access" ON telemetry_readings
  FOR ALL USING (get_my_role() = 'owner');

CREATE POLICY "Client reads own asset telemetry" ON telemetry_readings
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM asset_engines ae
      JOIN assets a ON a.id = ae.asset_id
      WHERE ae.id = engine_id AND a.client_id = auth.uid()
    )
  );

CREATE POLICY "Employee reads assigned" ON telemetry_readings
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM asset_engines ae
      JOIN work_orders wo ON wo.asset_id = ae.asset_id
      WHERE ae.id = engine_id AND wo.assigned_to = auth.uid()
    )
  );

-- telemetry_alerts policies
CREATE POLICY "Owner full access" ON telemetry_alerts
  FOR ALL USING (get_my_role() = 'owner');

CREATE POLICY "Client reads own asset alerts" ON telemetry_alerts
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM asset_engines ae
      JOIN assets a ON a.id = ae.asset_id
      WHERE ae.id = engine_id AND a.client_id = auth.uid()
    )
  );

CREATE POLICY "Employee reads assigned alerts" ON telemetry_alerts
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM asset_engines ae
      JOIN work_orders wo ON wo.asset_id = ae.asset_id
      WHERE ae.id = engine_id AND wo.assigned_to = auth.uid()
    )
  );

-- ============================================================
-- AUTO-UPDATE ENGINE HOURS TRIGGER
-- When a new telemetry reading comes in with engine_hours,
-- update the asset_engines.current_hours if it's higher
-- ============================================================

CREATE OR REPLACE FUNCTION update_engine_hours_from_telemetry()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Only update if engine_hours is provided and greater than current
  IF NEW.engine_hours IS NOT NULL THEN
    UPDATE asset_engines
    SET
      current_hours = NEW.engine_hours,
      updated_at = NOW()
    WHERE id = NEW.engine_id
      AND (current_hours IS NULL OR current_hours < NEW.engine_hours);
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_update_engine_hours
  AFTER INSERT ON telemetry_readings
  FOR EACH ROW
  EXECUTE FUNCTION update_engine_hours_from_telemetry();

-- ============================================================
-- COMMENTS
-- ============================================================

COMMENT ON TABLE telemetry_readings IS
  'Periodic engine telemetry snapshots from J1939/NMEA/Modbus sources';

COMMENT ON TABLE telemetry_alerts IS
  'Diagnostic trouble codes (DTCs) and threshold-based alerts from telemetry';

COMMENT ON COLUMN telemetry_alerts.spn IS
  'J1939 Suspect Parameter Number for diagnostic codes';

COMMENT ON COLUMN telemetry_alerts.fmi IS
  'J1939 Failure Mode Identifier for diagnostic codes';

COMMENT ON FUNCTION update_engine_hours_from_telemetry IS
  'Auto-updates asset_engines.current_hours when telemetry provides a higher value';

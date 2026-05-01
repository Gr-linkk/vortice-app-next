-- ============================================================
-- Vórtice Mechanical — Pending Migrations
-- Run this in Supabase Dashboard → SQL Editor
-- Updated: 2026-04-20
-- ============================================================


-- 1. maintenance_requests — add missing client_id column
ALTER TABLE maintenance_requests
  ADD COLUMN IF NOT EXISTS client_id uuid REFERENCES profiles(id);


-- 2. telemetry_readings table
CREATE TABLE IF NOT EXISTS telemetry_readings (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  engine_id     uuid REFERENCES asset_engines(id) ON DELETE CASCADE NOT NULL,
  ts            timestamptz NOT NULL DEFAULT now(),
  rpm                   double precision,
  coolant_temp          double precision,
  oil_pressure          double precision,
  battery_v             double precision,
  boost_psi             double precision,
  throttle_pct          double precision,
  fuel_rate             double precision,
  torque_pct            double precision,
  engine_hours          double precision,
  intake_temp           double precision,
  exhaust_temp          double precision,
  oil_temp              double precision,
  fuel_pressure         double precision,
  transmission_temp     double precision,
  transmission_pressure double precision,
  source    text,
  device_id text,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS telemetry_readings_engine_ts
  ON telemetry_readings (engine_id, ts DESC);

ALTER TABLE telemetry_readings ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='telemetry_readings' AND policyname='Owner reads all telemetry') THEN
    CREATE POLICY "Owner reads all telemetry" ON telemetry_readings
      FOR SELECT USING (get_my_role() = 'owner');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='telemetry_readings' AND policyname='Client reads own engine telemetry') THEN
    CREATE POLICY "Client reads own engine telemetry" ON telemetry_readings
      FOR SELECT USING (
        EXISTS (
          SELECT 1 FROM asset_engines ae
          JOIN assets a ON a.id = ae.asset_id
          WHERE ae.id = engine_id AND a.client_id = auth.uid()
        )
      );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='telemetry_readings' AND policyname='Device can insert telemetry') THEN
    CREATE POLICY "Device can insert telemetry" ON telemetry_readings
      FOR INSERT WITH CHECK (true);
  END IF;
END $$;


-- 3. telemetry_alerts table
CREATE TABLE IF NOT EXISTS telemetry_alerts (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  engine_id     uuid REFERENCES asset_engines(id) ON DELETE CASCADE NOT NULL,
  alert_type    text NOT NULL CHECK (alert_type IN ('dtc', 'threshold', 'warning', 'critical', 'info')),
  severity      text NOT NULL DEFAULT 'warning' CHECK (severity IN ('info', 'warning', 'critical')),
  spn           int,
  fmi           int,
  parameter     text,
  value         double precision,
  threshold     double precision,
  comparison    text,
  message       text,
  acknowledged        boolean DEFAULT false,
  acknowledged_by     uuid REFERENCES profiles(id),
  acknowledged_at     timestamptz,
  resolved            boolean DEFAULT false,
  resolved_at         timestamptz,
  source    text,
  device_id text,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS telemetry_alerts_engine_id
  ON telemetry_alerts (engine_id, created_at DESC);

ALTER TABLE telemetry_alerts ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='telemetry_alerts' AND policyname='Owner full access to alerts') THEN
    CREATE POLICY "Owner full access to alerts" ON telemetry_alerts
      FOR ALL USING (get_my_role() = 'owner');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='telemetry_alerts' AND policyname='Client reads own engine alerts') THEN
    CREATE POLICY "Client reads own engine alerts" ON telemetry_alerts
      FOR SELECT USING (
        EXISTS (
          SELECT 1 FROM asset_engines ae
          JOIN assets a ON a.id = ae.asset_id
          WHERE ae.id = engine_id AND a.client_id = auth.uid()
        )
      );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='telemetry_alerts' AND policyname='Client acknowledges own alerts') THEN
    CREATE POLICY "Client acknowledges own alerts" ON telemetry_alerts
      FOR UPDATE USING (
        EXISTS (
          SELECT 1 FROM asset_engines ae
          JOIN assets a ON a.id = ae.asset_id
          WHERE ae.id = engine_id AND a.client_id = auth.uid()
        )
      );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='telemetry_alerts' AND policyname='Device can insert alerts') THEN
    CREATE POLICY "Device can insert alerts" ON telemetry_alerts
      FOR INSERT WITH CHECK (true);
  END IF;
END $$;


-- 4. notifications table
CREATE TABLE IF NOT EXISTS notifications (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid REFERENCES profiles(id) ON DELETE CASCADE,
  title         text,
  body          text,
  type          text,
  reference_id  uuid,
  read          boolean DEFAULT false,
  created_at    timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS notifications_user_unread
  ON notifications (user_id, read, created_at DESC);

ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='notifications' AND policyname='Users see own notifications') THEN
    CREATE POLICY "Users see own notifications" ON notifications
      FOR SELECT TO authenticated USING (user_id = auth.uid());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='notifications' AND policyname='Authenticated users can insert notifications') THEN
    CREATE POLICY "Authenticated users can insert notifications" ON notifications
      FOR INSERT TO authenticated WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='notifications' AND policyname='Users can mark own notifications read') THEN
    CREATE POLICY "Users can mark own notifications read" ON notifications
      FOR UPDATE TO authenticated USING (user_id = auth.uid());
  END IF;
END $$;


-- 5 & 6. Storage bucket policies
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='objects' AND schemaname='storage' AND policyname='Authenticated upload signatures') THEN
    CREATE POLICY "Authenticated upload signatures" ON storage.objects
      FOR INSERT TO authenticated WITH CHECK (bucket_id = 'signatures');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='objects' AND schemaname='storage' AND policyname='Authenticated read signatures') THEN
    CREATE POLICY "Authenticated read signatures" ON storage.objects
      FOR SELECT TO authenticated USING (bucket_id = 'signatures');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='objects' AND schemaname='storage' AND policyname='Authenticated update signatures') THEN
    CREATE POLICY "Authenticated update signatures" ON storage.objects
      FOR UPDATE TO authenticated USING (bucket_id = 'signatures');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='objects' AND schemaname='storage' AND policyname='Authenticated upload report photos') THEN
    CREATE POLICY "Authenticated upload report photos" ON storage.objects
      FOR INSERT TO authenticated WITH CHECK (bucket_id = 'service-report-photos');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='objects' AND schemaname='storage' AND policyname='Authenticated read report photos') THEN
    CREATE POLICY "Authenticated read report photos" ON storage.objects
      FOR SELECT TO authenticated USING (bucket_id = 'service-report-photos');
  END IF;
END $$;


-- 7. parts table — INSERT policy for owner + employee
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='parts' AND policyname='Owner and employee insert parts') THEN
    CREATE POLICY "Owner and employee insert parts" ON parts
      FOR INSERT TO authenticated
      WITH CHECK (get_my_role() IN ('owner', 'employee'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='parts' AND policyname='Owner and employee delete parts') THEN
    CREATE POLICY "Owner and employee delete parts" ON parts
      FOR DELETE TO authenticated
      USING (get_my_role() IN ('owner', 'employee'));
  END IF;
END $$;


-- 8. profiles — add subscription_tier column
ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS subscription_tier integer NOT NULL DEFAULT 0;

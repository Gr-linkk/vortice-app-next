-- Link service reminders to the actual maintenance-plan interval record.
-- This preserves owner edits/reordering even when multiple intervals share
-- the same hour bucket on a single asset.

ALTER TABLE service_reminders
  ADD COLUMN IF NOT EXISTS service_interval_id UUID REFERENCES asset_service_intervals(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_service_reminders_service_interval_id
  ON service_reminders(service_interval_id);

-- Best-effort backfill for legacy rows.
-- If multiple interval rows share the same asset + interval_hours, we attach the
-- reminder to the most recently updated interval so the owner's latest plan wins.
WITH ranked_matches AS (
  SELECT
    sr.id AS reminder_id,
    asi.id AS service_interval_id,
    ROW_NUMBER() OVER (
      PARTITION BY sr.id
      ORDER BY asi.created_at DESC NULLS LAST, asi.id DESC
    ) AS rn
  FROM service_reminders sr
  JOIN asset_service_intervals asi
    ON asi.asset_id = sr.asset_id
   AND asi.interval_hours = sr.interval_hours
  WHERE sr.service_interval_id IS NULL
)
UPDATE service_reminders sr
SET service_interval_id = ranked_matches.service_interval_id
FROM ranked_matches
WHERE sr.id = ranked_matches.reminder_id
  AND ranked_matches.rn = 1;

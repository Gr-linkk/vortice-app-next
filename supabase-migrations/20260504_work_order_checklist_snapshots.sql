-- Persist a stable checklist snapshot per work order so historical WOs keep the
-- exact template metadata + items they were created with, even if the source
-- checklist template changes later.

CREATE TABLE IF NOT EXISTS work_order_checklist_snapshots (
  work_order_id UUID PRIMARY KEY REFERENCES work_orders(id) ON DELETE CASCADE,
  template_id UUID,
  template_version INTEGER,
  template_name TEXT NOT NULL,
  template_description TEXT,
  checklist_type TEXT NOT NULL DEFAULT 'pm',
  asset_type_id UUID,
  interval_hours INTEGER,
  interval_label TEXT,
  source_template_updated_at TIMESTAMPTZ,
  items_json JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_work_order_checklist_snapshots_template_id
  ON work_order_checklist_snapshots(template_id);

-- Best-effort backfill for existing PM work orders. This captures today's live
-- template metadata/items for older rows; new work orders will snapshot at write time.
INSERT INTO work_order_checklist_snapshots (
  work_order_id,
  template_id,
  template_version,
  template_name,
  template_description,
  checklist_type,
  asset_type_id,
  interval_hours,
  interval_label,
  source_template_updated_at,
  items_json,
  created_at,
  updated_at
)
SELECT
  wo.id,
  ct.id,
  ct.version,
  ct.name,
  ct.description,
  COALESCE(ct.checklist_type, 'pm'),
  ct.asset_type_id,
  ct.interval_hours,
  ct.interval_label,
  ct.updated_at,
  COALESCE(items.items_json, '[]'::jsonb),
  NOW(),
  NOW()
FROM work_orders wo
JOIN checklist_templates ct ON ct.id = wo.checklist_template_id
LEFT JOIN LATERAL (
  SELECT jsonb_agg(
           jsonb_build_object(
             'id', ci.id,
             'template_id', ci.template_id,
             'description_en', ci.description_en,
             'description_es', ci.description_es,
             'category', ci.category,
             'requires_photo', ci.requires_photo,
             'sort_order', ci.sort_order,
             'created_at', ci.created_at
           )
           ORDER BY ci.sort_order, ci.id
         ) AS items_json
  FROM checklist_items ci
  WHERE ci.template_id = ct.id
) items ON TRUE
WHERE wo.checklist_template_id IS NOT NULL
ON CONFLICT (work_order_id) DO NOTHING;

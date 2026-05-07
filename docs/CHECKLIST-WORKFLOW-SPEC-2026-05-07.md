# Vórtice Checklist Workflow Spec

Date: 2026-05-07
Status: canonical product/build direction for the checklist cleanup pass

## Purpose

Make every completed checklist become a durable saved copy under the asset, without forcing all checklist activity through work orders.

The key product idea is simple:

```text
Checklist template -> user fills checklist -> saved checklist copy -> Asset Checklist History
```

Work orders, assignments, and service requests may link to a saved checklist, but they are not required for a checklist to exist.

## Core principles

1. **Saved checklist history is universal**
   - Every submitted checklist creates a saved copy for the asset.
   - This includes Vórtice work-order checklists, client admin checklists, client mechanic checklists, and operator/pre-op checklists.

2. **Work orders are optional context**
   - Vórtice PM/service work can be WO-backed.
   - Client-side checklist submissions do not create work orders.
   - Client-side checklist submissions do not update PM intervals in v1.
   - Vórtice WO PM checklist submissions may still satisfy service intervals through the existing WO/checklist path.

3. **Clients do not see internal work orders**
   - Client-facing history shows saved checklist records.
   - It must not expose Vórtice WO internals, WO status, schedules, or internal WO notes.

4. **Assignments are not permissions**
   - Asset access + role + checklist association controls access.
   - Assignments can exist as future nudges/tasks only.
   - A user does not need an assignment to open or submit an associated checklist.

5. **Submitted records are immutable**
   - Once submitted, checklist records are locked.
   - No v1 amendment/correction workflow.
   - If something is wrong, handle manually or submit a new checklist.

6. **No private/internal toggle in v1**
   - Visibility is determined by role and checklist type.
   - No per-record hide-from-client setting in first pass.

## Asset checklist access

Checklists are available from the asset only when explicitly associated with that asset.

V1 association sources:

- asset service interval linked to a checklist template -> Maintenance checklist
- operational/pre-op checklist assignment/template linkage where already present -> Operations checklist
- future explicit asset-template links can be added later

Do not show all active templates loosely. Avoid checklist soup.

## Asset Checklist History UI

Asset history uses two tabs:

### Maintenance

Contains:

- PM checklists
- inspection checklists
- Vórtice service/WO checklists
- client admin/client mechanic maintenance checklist submissions

Primary tab for:

- Vórtice staff
- client admin
- client mechanic

Hidden from:

- operators/captains

### Operations

Contains:

- pre-op checks
- daily/operator checks
- captain/operator routine checklists

Visible to:

- Vórtice staff
- client admin
- client mechanic
- operators/captains

Primary/only tab for operators.

## Role rules

### Vórtice staff

- view Maintenance and Operations history
- submit any asset-associated checklist
- WO checklist submissions save to history with `work_order_id`

### Client admin

- view Maintenance and Operations history for their assets
- submit any checklist associated with their assets

### Client mechanic

- view Maintenance and Operations history for their assets
- submit Maintenance and Operations checklists associated with their assets
- does not see Vórtice WO status/details

### Operator/captain

- view and submit Operations checklists only
- no Maintenance tab

## Saved checklist run header

Every checklist run has a small header.

### Auto-filled, not editable

- Asset
- Checklist
- Completed by

### Auto-filled, editable before submit

- Date/time

### Manual optional

- Current hours
  - nullable numeric value
  - blank by default
  - do not auto-fill from telemetry/asset hours in v1
- General notes
  - whole-checklist notes
  - not item-specific notes

### Explicitly excluded from v1 header

- location
- client signature
- billing approval
- reason/context picker
- required-hours gate
- WO internal notes

## Checklist answer options

Use these item result options:

- Pass
- Monitor
- Action
- N/A

Validation:

- Monitor requires at least one of: note or photo
- Action requires at least one of: note or photo
- Pass does not require note/photo
- N/A does not require note/photo

Do not compute or store a separate whole-checklist color/status in v1.

## Photos

- Keep existing photo upload behavior in v1.
- The canonical saved checklist stores photo URLs when already available.
- Do not redesign storage/buckets in this pass.
- Submitted photo URLs are part of the immutable saved copy.

## New canonical table/model

Name: `saved_checklists`

Use a hybrid model:

### Query/filter columns

- `id`
- `asset_id`
- client/org scope column as needed by current schema/RLS
- `template_id`
- `template_name`
- `checklist_type` with broad values:
  - `maintenance`
  - `operations`
- `source_type`
  - examples: `client`, `vortice`, `operator`, `work_order`
- `submitted_by`
- `submitted_by_role`
- `submitted_at`
- `current_hours` nullable numeric
- `general_notes` nullable text
- `work_order_id` nullable
- `assignment_id` nullable
- `snapshot jsonb` immutable full saved copy
- timestamps as needed

Do not add `service_request_id` or `maintenance_flag_id` in v1.

### Snapshot contents

`snapshot` stores the full saved copy:

- header values
- template name/type/version where available
- checklist sections/items/order/labels
- item responses
- item notes
- item photo URLs if already available
- submitter and role
- asset reference
- submitted timestamp
- source context

## Supabase/RLS direction

Create the `saved_checklists` table and RLS policies in the same migration.

RLS should be hybrid:

- DB prevents cross-client/org asset leaks.
- DB allows Vórtice staff/admin access.
- DB allows client-side users only for assets they are allowed to access.
- App code handles UX category filtering/tabs.

V1 inserts can be direct app inserts protected by RLS. No RPC unless validation becomes too complex.

## Old tables and migration stance

- Do not backfill old checklist records in v1.
- New common history starts from new submissions only.
- Existing tables remain until proven unused.
- Do not drop live Supabase tables in this pass.
- It is acceptable to mark old paths as candidates for retirement in notes/code comments if clearly safe.

## Build targets for this pass

1. Add Supabase migration for `saved_checklists` + RLS.
2. Add app model/repository/provider for saved checklists.
3. Save WO checklist submissions into `saved_checklists` with `work_order_id`.
4. Save operator/client-side checklist submissions into `saved_checklists`.
5. Add/update asset Checklist History UI with Maintenance / Operations tabs.
6. Add asset-associated checklist access where missing, without requiring assignment.
7. Remove client signature/sign-off checklist items from source checklist data.
8. Clean obvious role leaks around client mechanic routes where safe.
9. Run targeted analyze/build checks.
10. Apply Supabase migration carefully once reviewed; do not hammer remote Supabase.
11. Build and install debug APK to Garrett's phone.

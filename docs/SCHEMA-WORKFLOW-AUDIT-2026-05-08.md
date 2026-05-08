# Schema / Workflow Audit — 2026-05-08

Status: audit only; no migrations applied

## Short answer

The current schema is good enough for **Asset Detail workflow hub v1**.

Do **not** migrate yet.

The schema already has the major workflow anchors we need:

- `service_requests.generated_work_order_id` for explicit service-request → work-order bridging
- `work_orders.asset_id`, `work_orders.client_id`, `work_orders.checklist_template_id`, and `work_orders.job_type` for staff maintenance work
- `asset_service_intervals` + `service_reminders` for PM planning and due-state
- `saved_checklists` as canonical immutable asset checklist history
- `client_capabilities` as the optional-workflow switchboard
- asset-first telemetry tables for read/display use

The bigger issue is not schema shape. It is **read-model locality**: Asset Detail still has to know too many providers/routes/cards directly. The next slice should add asset-scoped summary modules behind small interfaces, then let Asset Detail compose them.

Memory hook:

> The filing cabinet exists. Now Asset Detail needs dashboard drawers, not more filing cabinets.

## Audit scope

Inspected:

- `docs/WORKFLOW-ARCHITECTURE-NOTES-2026-05-08.md`
- `docs/CHECKLIST-WORKFLOW-SPEC-2026-05-07.md`
- `supabase/migrations/20260507135000_service_requests.sql`
- `supabase/migrations/20260507183000_saved_checklists.sql`
- `supabase/migrations/20260507013000_client_capabilities.sql`
- `supabase/migrations/20260507013500_asset_first_telemetry.sql`
- workflow modules under:
  - `lib/features/assets/`
  - `lib/features/checklists/`
  - `lib/features/service_intervals/`
  - `lib/features/service_requests/`
  - `lib/features/work_orders/`
  - `lib/features/operator/`
  - `lib/features/clients/`

## Workflow-to-table map

### 1. Client service request → work order

Current path:

```text
client/admin submits service request
→ service_requests row, status = new
→ staff inbox
→ staff clicks Generate Work Order
→ CreateWorkOrderScreen receives MaintenanceWorkOrderDraft(serviceRequestId)
→ work_orders row created
→ service_requests.generated_work_order_id set
→ service_requests.status = resolved
```

Main modules/files:

- `ServiceRequestController` in `lib/features/service_requests/service_request_provider.dart`
- `StaffServiceRequestListScreen` in `lib/features/service_requests/service_request_list_screen.dart`
- `MaintenanceWorkOrderDraft` in `lib/features/service_intervals/maintenance_work_order_draft.dart`
- `CreateWorkOrderScreen` in `lib/features/work_orders/create_work_order_screen.dart`

Schema fit:

- `service_requests.generated_work_order_id` is enough for explicit bridge v1.
- `service_requests.status` is intentionally MVP-simple.
- Work order does not need a new `service_request_id` column yet because the request owns the bridge.

Awkward seam:

- `status = resolved` is overloaded in product language as “Being handled” for clients. That is acceptable for v1, but if we later need richer request lifecycle, add explicit statuses rather than relying on label translation.

Asset Detail v1 impact: **not blocking**.

### 2. PM interval → work order/checklist/history

Current path:

```text
asset_service_intervals define PM schedule/checklist template
→ service_interval summaries read service_reminders + work_orders + latest hours
→ staff creates preventative work order
→ work_order stores asset/client/template/job_type
→ staff completes checklist
→ checklist_responses saved
→ saved_checklists row filed as maintenance history
→ PreventativeMaintenanceCompletion advances service_reminders
→ work_order closes
```

Main modules/files:

- `serviceIntervalsProvider` / `serviceIntervalSummariesProvider`
- `MaintenanceWorkOrderDraft.preventativeMaintenance`
- `MaintenanceChecklistSubmission`
- `SavedChecklistHistoryWriter`
- `PreventativeMaintenanceCompletion`

Tables:

- `asset_service_intervals`
- `service_reminders`
- `work_orders`
- `checklist_responses`
- `saved_checklists`
- `telemetry_readings` / `asset_engines` for hours fallback

Schema fit:

- PM schedule and due-state are already separable: interval definition vs reminder state.
- Work order can carry `checklist_template_id` and `job_type = preventative`.
- `saved_checklists.work_order_id` links immutable history back to staff work.

Awkward seam:

- `PreventativeMaintenanceCompletion` currently derives completion hours from work order hours, telemetry by `engine_id`, then engine current hours. It does **not** consume the checklist header `current_hours` that is saved to `saved_checklists`.
- With asset-first telemetry, a work order without `engine_id` cannot use latest asset telemetry for PM completion. That is a code/interface issue more than a schema issue.

Asset Detail v1 impact: **not blocking for summaries/history**, but important before relying on client-entered checklist hours to satisfy intervals.

### 3. Operator checklist → operations history

Current path:

```text
operator/client_operator selects asset + operations template
→ operator_checklist_runs row
→ operator_checklist_responses rows
→ saved_checklists row filed as operations history
```

Main modules/files:

- `OperatorChecklistScreen`
- `OperationsChecklistSubmission`
- `SavedChecklistHistoryWriter.recordOperationsRunHistory`
- `AssetChecklistHistoryScreen`

Tables:

- legacy/current `operator_checklist_runs`
- legacy/current `operator_checklist_responses`
- canonical `saved_checklists`

Schema fit:

- `saved_checklists.checklist_type = operations` matches the product model.
- RLS allows operators/client operators to read/submit only operations history for associated assets.

Awkward seam:

- Operations still writes legacy run/response tables first, then files canonical history. That is intentional for now, but means Asset Detail should read canonical history for history display and avoid coupling to legacy run tables unless it specifically needs run-only data.
- `saved_checklists.assignment_id` is present but has no FK in the migration. Fine for v1, but if assignments become durable workflow objects, this should become explicit.

Asset Detail v1 impact: **not blocking**.

### 4. Client/admin/mechanic checklist execution

Product direction says client admin/mechanic should submit asset-associated maintenance/operations checklists without Vórtice work orders in v1, saving history only.

Current schema support:

- `saved_checklists` can represent this cleanly with:
  - `source_type = client`
  - `checklist_type = maintenance` or `operations`
  - no `work_order_id`

Current code support:

- Staff work-order checklist submission exists.
- Operator operations checklist submission exists.
- A dedicated client/admin/mechanic non-WO checklist submission module is not clearly present yet.

Schema fit:

- The schema is ready.

Missing seam:

- Need a `ClientChecklistSubmission` or similar module before building UI for non-WO client/admin/mechanic checklist execution.
- This should be a separate module/interface, not a reuse of staff PM completion, because client-side PM submissions must **not** satisfy intervals in v1.

Asset Detail v1 impact: **blocks “start client maintenance checklist from Asset Detail”**, but does not block history/summary hub v1.

### 5. Asset Detail as workflow hub

Current Asset Detail already composes cards for:

- asset facts
- checklist history
- engines
- maintenance plan/service intervals
- device status
- telemetry

Main files:

- `lib/features/assets/asset_detail_screen.dart`
- `lib/features/assets/asset_workflow_policy.dart`
- `lib/features/clients/asset_checklist_history_screen.dart`
- `lib/features/service_intervals/service_interval_provider.dart`

Schema fit:

- Asset-scoped reads are supported by current tables.
- No migration is needed to make Asset Detail a better hub.

Architecture friction:

- Asset Detail is still a shallow composition point: each card reaches directly into separate providers/routes.
- The missing depth is a read-model seam, not a database seam.

Recommended module shape:

- Add asset-scoped summary modules with small interfaces, for example:
  - `AssetChecklistHistorySummary` — latest maintenance/operations saved checklist counts/dates
  - `AssetMaintenanceSummary` — due/overdue intervals, active PM work order id
  - `AssetServiceRequestSummary` — open/new service requests for the asset
  - `AssetOperationsSummary` — latest operations checklist/run

These modules should hide table/provider details behind interfaces that Asset Detail can call. That gives leverage and locality: the hub can change layout without knowing every workflow table.

## What already matches the workflow model

1. `saved_checklists` is the right canonical filing cabinet.
   - Broad `maintenance` / `operations` types match the spec.
   - `snapshot jsonb` preserves immutable submitted copy.
   - `work_order_id` is optional, which supports non-WO checklists.

2. Service requests have an explicit bridge to generated work orders.
   - `generated_work_order_id` is enough for current v1.

3. Capability gates are separate from role policy.
   - `client_capabilities` remains the switchboard.
   - `AssetWorkflowPolicy` remains role/routing/card policy.

4. Asset-first telemetry is already schema-aligned for display.
   - Asset Detail can show telemetry without changing ingestion/polling.

5. PM completion is now a named module.
   - The workflow seam exists; it just needs one interface refinement later around completion hours.

## Gaps and risks, ranked

### P0 — Do before migrations/features that satisfy PM from client-entered checklist hours

**PM completion ignores submitted checklist `current_hours`.**

The saved checklist header stores `current_hours`, but `PreventativeMaintenanceCompletion` does not receive/use it. It only looks at work order hours, telemetry by engine, and engine current hours.

Recommendation:

- Do not migrate.
- Later, deepen the `PreventativeMaintenanceCompletion` interface so the maintenance submission can pass explicit completion hours.
- Keep the old fallback order for compatibility.

### P1 — Do before client/admin/mechanic non-WO checklist execution

**Missing client-side checklist submission module.**

Schema supports non-WO saved maintenance/operations checklists, but code needs a module distinct from staff PM completion.

Recommendation:

- Add a `ClientChecklistSubmission` module when we build that workflow.
- It should write `saved_checklists` only in v1.
- It must not update `service_reminders`, close work orders, or notify Vórtice automatically.

### P1 — Do before Asset Detail grows more cards

**Asset Detail needs summary read modules.**

Asset Detail should not know table/query details for every workflow.

Recommendation:

- Add read-model modules first, then UI cards.
- This is code-only.
- No migration needed.

### P2 — Watch before assignment/task workflows get serious

**Checklist assignment semantics are still soft.**

Assignments are not permissions, per spec. Current assignment structures can support asset/template nudges, but `saved_checklists.assignment_id` is not a declared FK in the migration.

Recommendation:

- No migration now.
- If assignments become auditable tasks, add explicit FK/indexing then.

### P2 — Future service request lifecycle

**`resolved` is overloaded as “Being handled.”**

That is fine for MVP, but if clients need “accepted / in progress / completed / declined,” create a deliberate status migration then.

Recommendation:

- No migration now.
- Keep the simple inbox until product behavior demands more states.

## Recommended next slice

Do a **code-only Asset Detail hub v1 read-model slice**.

Suggested first module:

```text
AssetWorkflowSummary
```

Interface should answer, for one asset:

- latest maintenance checklist date/name
- latest operations checklist date/name
- active/open PM work order count or next PM due summary
- open/new service request count for that asset, if role can see it
- telemetry/device availability can remain in existing telemetry modules for now

Then update `AssetDetailScreen` to render summaries/actions from that module instead of teaching the screen more workflow details.

Why this is the best next move:

- No schema migration risk.
- Makes Asset Detail more useful immediately.
- Preserves locality: workflow query knowledge moves out of the widget.
- Builds the hub without letting the hub mutate workflows.

## Migration recommendation

No migration right now.

The only migration candidates are future-triggered:

1. Richer service request lifecycle statuses.
2. Explicit assignment FK/index if assignments become durable task objects.
3. Optional service-request backpointer on `work_orders` if we need reverse lookup without joining from `service_requests`.

None of these block Asset Detail hub v1.

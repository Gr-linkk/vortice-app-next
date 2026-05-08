# Workflow Architecture Notes — 2026-05-08

## Plain-English memory hook

When we talk about this refactor later, remember it like this:

> We stopped letting screens be the mechanic, the service writer, and the filing cabinet all at once.

Before this work, checklist screens were doing too much directly: saving checklist answers, building permanent history records, satisfying PM intervals, closing work orders, and deciding who could see asset workflow cards.

This refactor did **not** redesign Vórtice. It put names on the real workflow steps so future changes have obvious places to go:

- **`SavedChecklistHistoryWriter`** = the filing cabinet. It records immutable asset history in `saved_checklists`.
- **`MaintenanceChecklistSubmission`** = the staff checklist submit workflow. It saves responses, files history, then completes PM when appropriate.
- **`OperationsChecklistSubmission`** = the operator checklist submit workflow. It saves the operator run/responses, then files Operations history.
- **`PreventativeMaintenanceCompletion`** = the PM closeout workflow. It advances reminders and closes the work order after a staff PM checklist is completed.
- **`AssetWorkflowPolicy`** = the asset-detail role rulebook. It says which roles see asset workflow cards and route prefixes. It does **not** replace capability gates.

The big idea: **Asset Detail should become the hub, but it should not become the thing that mutates everything.** Asset Detail should show actions and summaries. The workflow modules should do the work.

If we say “deepen the workflow seams,” this is what we mean: move business behavior out of widgets and into named, tested modules that match the real maintenance workflow.

## Why this exists

This note explains the May 8 workflow refactor checkpoints so future Garrett/Jasper/Casper can understand why the new seams exist. The goal was not to redesign Vórtice UI. The goal was to make existing workflow behavior easier to reason about before making Asset Detail the real workflow hub.

## Product direction

Vórtice is moving asset-first:

- Asset Detail should become the user-facing hub for maintenance and operations workflows.
- `saved_checklists` is the canonical immutable asset history.
- Maintenance and operations checklist history must stay distinct:
  - `maintenance`
  - `operations`
- Operators/client operators only see Operations history.
- Staff work-order PM submission may satisfy PM intervals and close work orders.
- Client-side PM submissions, when added, must save history only in v1; they must not satisfy intervals or notify Vórtice automatically.
- Telemetry is asset-first but should stay a bounded read/data module during workflow refactors.

## Checkpoint 1: Checklist history and PM completion workflow seams

Commit: `3467382 refactor: deepen checklist history and PM completion workflows`

### What changed

Added workflow seams:

- `lib/features/checklists/saved_checklist_history_writer.dart`
- `lib/features/checklists/checklist_submission_orchestrator.dart`
- `lib/features/service_intervals/preventative_maintenance_completion.dart`

Added tests:

- `test/features/checklists/saved_checklist_history_writer_test.dart`
- `test/features/checklists/checklist_submission_orchestrator_test.dart`
- `test/features/service_intervals/preventative_maintenance_completion_test.dart`

### Why

Before this refactor, checklist submit screens directly assembled low-level `saved_checklists` metadata and sequenced business side effects. That made UI widgets responsible for domain workflow behavior.

The refactor moved that behavior behind named modules:

- `SavedChecklistHistoryWriter`
  - records maintenance work-order history
  - records operations run history
  - hides canonical `source_type`, `checklist_type`, and history header details from screens

- `MaintenanceChecklistSubmission`
  - preserves ordering: checklist responses → saved maintenance history → PM completion

- `OperationsChecklistSubmission`
  - preserves ordering: operator run/responses → saved operations history

- `PreventativeMaintenanceCompletion`
  - owns the PM completion workflow previously inside `ServiceIntervalController`
  - preserves existing behavior: work-order lookup, matching interval lookup, hours fallback, reminder update/insert, work-order close, and service interval invalidation

### Behavior intentionally preserved

- Staff PM checklist submit still writes responses, saves maintenance history, then satisfies PM / closes the work order.
- Operator checklist submit still writes operator run/responses and saves operations history.
- Offline/pending maintenance response behavior still prevents saved history and PM satisfaction until response submission succeeds.
- Telemetry is only used as an hours fallback inside PM completion; polling/ingestion behavior was not changed.
- No schema, RLS, capability, route, or UI redesign changes were made.

## Checkpoint 2: Asset workflow role policy

Commit: pending at time of writing. Suggested message:

```text
refactor: centralize asset workflow role policy
```

### What changed

Added:

- `lib/features/assets/asset_workflow_policy.dart`
- `test/features/assets/asset_workflow_policy_test.dart`

Updated:

- `lib/features/assets/asset_detail_screen.dart`

### Why

`AssetDetailScreen` had local role logic for route prefixes and card visibility. That made the screen act as both UI and policy. This slice extracts the existing role decisions into `AssetWorkflowPolicy` so future Asset Detail hub work has a small, testable policy seam.

This is not a capability-gate rewrite. Existing capability gates still own capability checks.

### Current policy responsibilities

`AssetWorkflowPolicy` answers:

- `routePrefixForRole(role)`
- `canSeeChecklistHistory(role)`
- `canSeeMaintenancePlan(role)`
- `canManageAsset(role)`
- `canSeeEngines(role)`

### Behavior intentionally preserved

- Owner route prefix: `/owner`
- Employee route prefix: `/employee`
- Client/client admin/client mechanic/client operator route prefix: `/client`
- Operator route prefix: `/operator`
- Checklist history visible to owner, employee, client, client admin, client mechanic, operator, and client operator
- Maintenance plan visible to owner, client, client admin, and client mechanic
- Asset management and engine card remain owner-only
- No routes, labels, cards, capability gates, telemetry, checklists, PM logic, service requests, or work orders were changed

## How to continue safely

Recommended next slices:

1. Commit the asset workflow policy slice separately.
2. Add asset-scoped summary/read models only after policy is stable.
3. Make Asset Detail compose summaries/actions from deeper modules; do not let it mutate workflows directly.
4. Keep telemetry as a bounded module. Asset Detail can display telemetry, but workflow refactors should not change polling or ingestion.

Avoid these traps:

- Do not make `AssetDetailScreen` directly write saved checklist rows or PM reminders.
- Do not route future client PM submissions through staff work-order checklist behavior unchanged.
- Do not remove legacy operator run writes until all consumers are verified migrated to `saved_checklists`.
- Do not hide optional features only in nav; direct routes and backend/RLS still matter.

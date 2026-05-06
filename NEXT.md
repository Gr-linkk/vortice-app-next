# NEXT — Vórtice App

Last updated: 2026-05-06

## Start here next time

Current repo state:

- The working tree is intentionally dirty with reviewed architecture/offline-first patches. Commit/snapshot soon before stacking more work.
- A debug APK was built from this dirty tree and uploaded as a private GitHub prerelease for phone install testing:
  - https://github.com/Gr-linkk/vortice-app/releases/tag/debug-phone-2026-05-06-1312
  - asset: `vortice-debug-2026-05-06.apk`
- Latest completed offline-first patch: pending-sync visibility for checklist responses.
  - local pending/failed/conflict rows remain visible after remote reads
  - checklist UI shows `Saved locally. Sync pending.`, `Checklist has sync conflicts.`, and per-item chips
  - no replay worker/photo replay/status/close/service interval behavior was added

Before touching telemetry code, check:

- Workspace telemetry source of truth: `/home/gr_link/.openclaw/workspace/projects/vortice-supporting-projects/dredge-telemetry/STATUS.md`
- Architecture note: `/home/gr_link/.openclaw/workspace/projects/vortice-app/ARCHITECTURE-AUDIT-2026-05-05.md`

## Telemetry note

The old Pi-drive file `incoming-pi-drive-selected/projects/dredge-canbus-telemetry.md` was compared against the current telemetry project. Do **not** promote that full file or create a second telemetry spec.

Useful details were already folded into `projects/vortice-supporting-projects/dredge-telemetry/STATUS.md`, including:

- CAN/J1939 must be passive/listen-only for MVP
- Do not add a 120Ω terminator at the telemetry box
- Use fused 24V panel power, not diagnostic/AUX power
- Preserve old CAN HIGH / CAN LOW / shield pin reference as backup wiring context
- Treat the 12-zone bilge plan as future expansion unless Garrett explicitly adds it to MVP
- Collector should send `asset_id` + `device_id` first-class, with `engine_id` included only when resolved/known
- Gateway/Pi health belongs in `telemetry_gateway_health`, not mixed into engine telemetry readings

## Offline-first requirement

The app is intended to be usable offline and sync when the device comes back online. Do **not** treat Vórtice as permanently online-only.

Current Drift/local DB code is not enough yet: it is shallow cache scaffolding, not a real offline-sync architecture. Keep Drift/local storage as a candidate foundation, but formalize the offline contract before expanding it.

Offline MVP should prioritize field work:

- cached assets/work orders/checklist templates needed for assigned jobs
- offline work order execution
- checklist responses
- service report drafts
- notes/photos/parts/hours captured offline
- visible pending-sync / stale-data states
- sync queue, retry, conflict rules, and delete/prune behavior when back online

Avoid calling current cache behavior “offline mode” until those semantics exist.

## Offline checklist response replay contract

Current state after the offline read/save seams:

- checklist responses can be saved locally with `sync_status` (`synced`, `pending_create`, `pending_update`, `failed`, `conflict`)
- remote submit remains remote-first; local pending rows are a no-data-loss fallback, not proof that sync completed
- photo upload/replay, work-order close/status, service interval satisfaction, and background sync are intentionally deferred

Do **not** build a replay worker until the idempotency/conflict contract is explicit.

Checklist response replay should use `(work_order_id, checklist_item_id)` as the logical identity. The safest server contract is a unique remote constraint on that pair plus upsert by that conflict key. Without that live DB guarantee, replay must be conservative:

1. scan local `checklist_responses` rows with `sync_status in ('pending_create', 'pending_update')`
2. for each row, select remote rows by `work_order_id + checklist_item_id`
3. if no remote row exists, insert using the local UUID
4. if one remote row exists and it has not changed since `last_synced_at`, update it
5. if the remote row appears newer/conflicting, mark local row `conflict` and do not overwrite
6. if multiple remote rows exist for the same logical response, mark local row `conflict` and stop for cleanup/schema work

Replay must not:

- upload or replay photos until `LocalAttachmentsTable` handling is designed
- call service interval satisfaction or close/update work orders
- silently overwrite another tech’s response
- use `SyncOperationsTable` as a second source of truth before a broader sync engine exists
- claim “submitted” when rows are only pending local sync

Next safe patch options:

- commit/snapshot the reviewed patch stack before more implementation
- add DAO helpers for pending checklist responses and status transitions
- add a manual/invoked-only repository replay method for checklist responses, guarded by the conservative rules above
- define live DB uniqueness/upsert migration for `(work_order_id, checklist_item_id)` before automatic replay

Done after this contract:

- pending-sync visibility was added in the checklist UI: form banner plus per-item chips for pending/failed/conflict local rows

## Important unresolved app alignment

The active Flutter source still appears engine-scoped in some telemetry models/providers, while the 2026-05-05 architecture audit says the live DB was migrated toward asset-pinned telemetry:

- `telemetry_readings.asset_id`
- nullable `telemetry_readings.engine_id`
- `telemetry_alerts.asset_id`
- nullable `telemetry_alerts.engine_id`
- `telemetry_gateway_health`

Next app pass should align checked-in models, providers, repository methods, and migrations with that live asset-pinned direction before building the Pi collector around the schema.

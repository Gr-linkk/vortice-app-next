# NEXT — Vórtice App

Last updated: 2026-05-07 19:50 EDT

## Start here next time

Expected repo state after this session:

- Repo: `/mnt/c/Users/gr_link/src/vortice-app-main`
- Branch: `main`
- Expected state: clean working tree, `main` aligned with `origin/main`.
- Latest app commit: this handoff commit, `feat: add saved checklist history workflow`; verify exact hash with `git log -1 --oneline`.
- Latest feature set: service request → work order bridge, universal saved checklist history, checklist UX polish.

Verify:

```bash
git status --short
git log --oneline -5
```

## Most important next move

**Next time we work on the app, map out the workflows before coding.**

Garrett explicitly wants the next app session to step back and map workflows end-to-end. Recommended workflow map targets:

1. Client service request → staff triage → generated work order → completed work → client-visible status/history.
2. Preventative maintenance interval → generated work order → checklist completion → saved asset checklist history → interval satisfaction.
3. Operator/captain operations checklist → saved asset checklist history → exception/action visibility.
4. Client admin/mechanic checklist execution → saved asset checklist history without accidentally acting like a Vórtice work order.
5. Asset detail as the hub: maintenance plan, service requests, work orders, checklist history, telemetry, documents.

Goal: produce a simple canonical workflow map/spec before the next Flutter patch, so app screens and database seams follow the same language.

## What landed this session

### Service Request → Work Order bridge

- Staff service request cards now have **Generate Work Order**.
- The button opens the existing create-work-order form prefilled from the request.
- Backing out leaves the request unchanged.
- Saving the generated work order marks the request handled/resolved and removes it from the staff inbox.
- Client-facing semantics remain separate from work-order mechanics.
- Clients still do not see work orders or schedules.

### Universal saved checklist history

- Added canonical `saved_checklists` table/model/repository.
- Every submitted maintenance/work-order checklist now saves an immutable asset history snapshot.
- Every submitted operator checklist now saves an immutable operations history snapshot.
- Saved snapshot includes template metadata, answered items, statuses, notes, photo URLs when available, run header, source metadata, current hours, and general notes.
- Added asset-level Checklist History screen with tabs:
  - Maintenance
  - Operations
- Operators/client operators only see Operations history.
- Owner/employee/client admin/client mechanic can see Maintenance + Operations where RLS permits.
- Normal app users can insert/read saved checklist history; app users do not update/delete immutable rows.

### Checklist execution UX

- Checklist answer options are now `PASS / MONITOR / ACTION / N/A`.
- Monitor/Action require a note or photo before submit.
- Run header includes:
  - Asset
  - Checklist
  - Completed by
  - Editable date/time
  - Optional current hours
  - Optional general notes
- Header now scrolls away with checklist content instead of trapping screen space at the top.

### Work order checklist picker cleanup

- When creating a work order for an asset, the checklist picker shows asset-type-specific maintenance checklists first/exclusively.
- If an asset has no specific checklists, it falls back to general maintenance checklists.
- Service-hour templates sort low → high, e.g. 250 → 500 → 1000 → 2000, with non-hour/general items last.
- Changing the selected asset clears the previous checklist selection to avoid wrong-template carryover.

### Supabase live state

Live Supabase project: Vortice `REDACTED_SUPABASE_PROJECT`

Live migrations applied / verified:

- `20260507013000_client_capabilities`
- `20260507013500_asset_first_telemetry`
- `20260507135000_service_requests`
- `20260507183000_saved_checklists`

Remote migration history was previously repaired for already-existing old migrations:

- `20260419`
- `20260423`

Verified after saved checklist apply:

- Supabase CLI migration list showed local/remote `20260507183000` matched.
- No fake telemetry was inserted.
- No live tables were dropped.

### Phone state

Latest debug APK from this session was installed successfully on Garrett's `SM_S928W`.

Wireless Debugging ports are ephemeral. Recent successful ports:

- `100.78.40.20:46529`
- `100.78.40.20:39043`

Do not assume either port persists. If ADB refuses connection, open Android Developer Options → Wireless debugging and read the current IP/port.

Useful install path from WSL using Windows Flutter/ADB:

```powershell
cd C:\Users\gr_link\src\vortice-app-main
flutter build apk --debug
& "C:\Users\gr_link\AppData\Local\Android\Sdk\platform-tools\adb.exe" connect <current-phone-ip-port>
& "C:\Users\gr_link\AppData\Local\Android\Sdk\platform-tools\adb.exe" install -r "C:\Users\gr_link\src\vortice-app-main\build\app\outputs\flutter-apk\app-debug.apk"
```

## Verification from this session

- Targeted `flutter analyze` for touched saved-checklist/checklist/operator/work-order files: clean.
- Debug APK build: successful.
- APK install to `SM_S928W`: successful.
- Full repo analyze still reports pre-existing warnings/infos in unrelated areas; no blocking analyzer errors were introduced by this patch.
- Repo has no `test/` directory, so `flutter test` remains unavailable.

## Hard guardrails

- Test/bench telemetry stays in its separate table and must not feed app screens or production app flows.
- Do not seed fake telemetry into `telemetry_readings` / `telemetry_alerts`.
- Do not mix Pi/collector runtime changes into app work unless explicitly scoped.
- Gateway/Pi health belongs in `telemetry_gateway_health`, not engine telemetry readings.
- Collector should send `asset_id` + `device_id` first-class, with `engine_id` only when resolved/known.
- Do not build telemetry UI on engine-first assumptions. Ask: “Is this treating the asset as the telemetry owner?”
- Capability switches gate new workflow access; they do not justify deleting history.
- Service requests are baseline portal workflow; do not hide them behind paid capability toggles.
- Service requests remain distinct from work orders.
- Saved checklist records are immutable in app UX for v1; do not add amendments/corrections casually.
- Client-side PM checklist submissions save to asset history only; they do not satisfy intervals or notify Vórtice in v1.
- Work-order create/complete/reopen/edit should fail fast offline for now, not pretend to be safely pending.
- No-data-loss wins over cleanup.

## Best next work

1. **Map workflows before coding**
   - This is the next-session priority.
   - Capture the map in docs before another large UI/data patch.

2. **Phone smoke test the new flow**
   - Generate WO from service request.
   - Create dredge WO and confirm checklist picker shows dredge-specific options sorted by hours.
   - Complete maintenance checklist and confirm saved Maintenance history appears on asset.
   - Complete operator checklist and confirm saved Operations history appears on asset.
   - Confirm operator cannot see Maintenance history.

3. **Review saved checklist history UX**
   - Decide whether detail cards need a dedicated detail screen.
   - Decide whether photos should open full-screen.
   - Decide whether clients need filters by source/type/date.

4. **Workflow polish after mapping**
   - Service request ↔ generated work order audit/link visibility.
   - Checklist exception/action surfacing.
   - PM interval satisfaction semantics.
   - Assignment/task nudges, but not as permissions.

## Offline-first reminder

Offline checklist response replay contract remains deferred.

Checklist response replay should use `(work_order_id, checklist_item_id)` as the logical identity. Safest server contract is a unique remote constraint on that pair plus upsert by that conflict key. Until then, replay must be conservative and manual/invoked-only.

Replay must not:

- upload/replay photos until attachment handling is designed
- call service interval satisfaction or close/update work orders
- silently overwrite another tech’s response
- use `SyncOperationsTable` as a second source of truth before a broader sync engine exists
- claim “submitted” when rows are only pending local sync

# NEXT — Vórtice App

Last updated: 2026-05-07 01:55 EDT

## Start here next time

Expected repo state:

- Repo: `/mnt/c/Users/gr_link/src/vortice-app-main`
- Branch: `main`
- Latest pushed commit: `17534ea feat: add client service switchboard and asset-first telemetry seam`
- Expected state: clean working tree, `main` aligned with `origin/main`.

Verify:

```bash
git status --short
git log --oneline -3
```

## What is now live

Supabase project: Vortice `REDACTED_SUPABASE_PROJECT`

Live migrations applied:

- `20260507013000_client_capabilities`
- `20260507013500_asset_first_telemetry`

Remote migration history was repaired for already-existing old migrations:

- `20260419`
- `20260423`

Verified live after apply:

- `public.client_capabilities` exists.
- `telemetry_readings.asset_id` is `NOT NULL`.
- `telemetry_alerts.asset_id` is `NOT NULL`.
- telemetry `engine_id` remains nullable.
- telemetry app tables had `0` rows after apply.
- `client_capabilities` had `0` rows after apply.
- no test telemetry was inserted or bridged into app tables.

## What landed in app

- Dev Persona Switchboard in login.
- Owner-facing Service Switchboard in client detail.
- `client_capabilities` model/provider/controller and migration.
- Asset-first telemetry model/provider/repository/screen seam:
  - `assetId` first-class on readings/alerts
  - `engineId` nullable
  - `deviceId` first-class
  - optional `rawData`
  - asset latest/history/alerts providers
  - `/telemetry/assets/:assetId/history`
  - vessel telemetry fetches by asset
  - dashboard alert taps prefer asset route
  - asset detail telemetry card uses asset telemetry/alerts

## Hard guardrails

- Test/bench telemetry stays in its separate table and must not feed app screens or production app flows.
- Do not seed fake telemetry into `telemetry_readings` / `telemetry_alerts`.
- Do not mix Pi/collector runtime changes into app work unless explicitly scoped.
- Gateway/Pi health belongs in `telemetry_gateway_health`, not engine telemetry readings.
- Collector should send `asset_id` + `device_id` first-class, with `engine_id` only when resolved/known.
- Do not build telemetry UI on engine-first assumptions. Ask: “Is this treating the asset as the telemetry owner?”
- Do not build replay worker/photo replay/work-order close sync until idempotency/conflict semantics are safe.
- Work-order create/complete/reopen/edit should fail fast offline for now, not pretend to be safely pending.
- No-data-loss wins over cleanup.

## Best next Casper job

**Casper Scout — capability enforcement**

Goal: map remaining legacy tier gates before edits.

Inspect:

- `SubscriptionTier.*`
- `hasTier(...)`
- `tier_gate.dart`
- dashboard routing
- bottom nav / app shell
- client dashboard variants
- telemetry gates
- service interval / maintenance planning gates
- owner/client screens that still assume Free/Managed/Planning/Telemetry tiers

Return:

1. exact call sites
2. recommended capability-gate adapter shape
3. smallest safe patch scope
4. what must stay owner/admin accessible regardless of client switches
5. history/read-only behavior when a capability is disabled
6. checks to run

Scout only first; no edits until Jasper reviews.

## Likely next implementation patches

1. Capability enforcement adapter + selected nav/dashboard gates.
2. Phone smoke test against live Supabase.
3. Service Requests schema/model/provider + owner inbox.
4. Mechanic PM bridge aligned with work orders/checklist engine.
5. Checklist assignment completion lifecycle.
6. Telemetry pairing replace/unpair lifecycle.

## Phone smoke test path

Use Windows-side Flutter/ADB from WSL.

Known ADB target:

- `100.78.40.20:35313`

Useful commands:

```powershell
cd C:\Users\gr_link\src\vortice-app-main
flutter build apk --debug
& "C:\Users\gr_link\AppData\Local\Android\Sdk\platform-tools\adb.exe" connect 100.78.40.20:35313
& "C:\Users\gr_link\AppData\Local\Android\Sdk\platform-tools\adb.exe" install -r "C:\Users\gr_link\src\vortice-app-main\build\app\outputs\flutter-apk\app-debug.apk"
```

Test:

- dev personas log in
- owner can open client detail Service Switchboard
- toggles read/write live Supabase rows
- dashboards do not show fake/test telemetry
- telemetry empty states are honest: no paired device / no readings yet / telemetry not enabled

## Offline-first reminder

Offline checklist response replay contract remains deferred.

Checklist response replay should use `(work_order_id, checklist_item_id)` as the logical identity. Safest server contract is a unique remote constraint on that pair plus upsert by that conflict key. Until then, replay must be conservative and manual/invoked-only.

Replay must not:

- upload/replay photos until attachment handling is designed
- call service interval satisfaction or close/update work orders
- silently overwrite another tech’s response
- use `SyncOperationsTable` as a second source of truth before a broader sync engine exists
- claim “submitted” when rows are only pending local sync

# NEXT — Vórtice App

Last updated: 2026-05-07 15:20 EDT

## Start here next time

Expected repo state:

- Repo: `/mnt/c/Users/gr_link/src/vortice-app-main`
- Branch: `main`
- Latest pushed commit: `16223a8 feat: add service requests mvp`
- Previous capability enforcement commit: `e9b9d33 feat: enforce client capability switchboard`
- Expected state: clean working tree, `main` aligned with `origin/main`.

Verify:

```bash
git status --short
git log --oneline -5
```

## What is now live

Supabase project: Vortice `REDACTED_SUPABASE_PROJECT`

Live migrations applied / verified:

- `20260507013000_client_capabilities`
- `20260507013500_asset_first_telemetry`
- `20260507135000_service_requests`

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
- `public.service_requests` exists and REST returned HTTP 200 with `[]` immediately after apply.
- no test telemetry was inserted or bridged into app tables.

## What landed in app

- Dev Persona Switchboard in login.
- Owner-facing Service Switchboard in client detail.
- `client_capabilities` model/provider/controller and migration.
- Capability switchboard enforcement for workflow access:
  - new optional workflow access is capability-gated
  - owner/employee bypass remains for internal operations
  - historical/read-only visibility is preserved where appropriate
  - live/dashboard telemetry remains gated while read-only history can remain visible where role/RLS allows
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
- Service Requests MVP:
  - dedicated `service_requests` table
  - baseline always-on client portal flow, not capability-gated
  - `client` / `client_admin` submit and read
  - `owner` / `employee` staff inbox read/manage
  - `client_operator` / `client_mechanic` do not directly submit in MVP
  - statuses: `new`, `resolved`, `declined`
  - client labels: `Sent`, `Being handled`, `Declined`
  - request intake is separate from work orders; linkage remains a future explicit seam

## Current phone state

Latest debug APK with commit `16223a8` was installed successfully on Garrett's `SM_S928W`.

Wireless Debugging ports are ephemeral. The last successful install used:

- `100.78.40.20:46529`

Do not assume that port persists. If ADB refuses connection, open Android Developer Options → Wireless debugging and read the current IP/port.

Useful install path from WSL using Windows Flutter/ADB:

```powershell
cd C:\Users\gr_link\src\vortice-app-main
flutter build apk --debug
& "C:\Users\gr_link\AppData\Local\Android\Sdk\platform-tools\adb.exe" connect <current-phone-ip-port>
& "C:\Users\gr_link\AppData\Local\Android\Sdk\platform-tools\adb.exe" install -r "C:\Users\gr_link\src\vortice-app-main\build\app\outputs\flutter-apk\app-debug.apk"
```

## Smoke test checklist

Check on phone:

- dev personas log in
- owner can open client detail Service Switchboard
- switchboard toggles read/write live Supabase rows
- client dashboard has Requests
- client/client admin can submit request
- client/client admin can view request history
- owner/employee can open Service Requests inbox
- owner/employee can mark request `resolved` / `declined`
- dashboards do not show fake/test telemetry
- telemetry empty states are honest: no paired device / no readings yet / telemetry not enabled
- capability-off states hide/block new workflow access without deleting history

## Hard guardrails

- Test/bench telemetry stays in its separate table and must not feed app screens or production app flows.
- Do not seed fake telemetry into `telemetry_readings` / `telemetry_alerts`.
- Do not mix Pi/collector runtime changes into app work unless explicitly scoped.
- Gateway/Pi health belongs in `telemetry_gateway_health`, not engine telemetry readings.
- Collector should send `asset_id` + `device_id` first-class, with `engine_id` only when resolved/known.
- Do not build telemetry UI on engine-first assumptions. Ask: “Is this treating the asset as the telemetry owner?”
- Capability switches gate new workflow access; they do not justify deleting history.
- Service requests are baseline portal workflow; do not hide them behind paid capability toggles.
- Service request `resolved` means handled/accepted in the inbox flow, not mechanically complete.
- Do not build replay worker/photo replay/work-order close sync until idempotency/conflict semantics are safe.
- Work-order create/complete/reopen/edit should fail fast offline for now, not pretend to be safely pending.
- No-data-loss wins over cleanup.

## Best next work

1. **Finish phone smoke test**
   - Use the checklist above and note anything that feels awkward.

2. **Clean remaining tier ghosts**
   - Active workflow tier gates are mostly gone, but these still exist as legacy/business-label code:
     - `lib/features/subscription/tier_gate.dart`
     - `lib/features/subscription/upgrade_prompt.dart`
     - `lib/models/subscription_tier.dart`
     - `subscriptionTier` fields/localized labels
   - Decide whether to keep tier as business metadata only or remove/hide it from app UX entirely.

3. **Service Request → Work Order bridge**
   - Add explicit staff action to generate/link a work order from a service request.
   - Populate `generated_work_order_id`.
   - Preserve request/inbox semantics separately from work-order mechanical completion.

4. **Service Request polish**
   - optional request photos/attachments
   - better urgent visual treatment
   - possible owner bottom-nav entry for Requests if dashboard card is not discoverable enough

5. **Telemetry pairing lifecycle**
   - Pair / Replace / Unpair device flow
   - one-active-device-per-asset enforcement
   - pairing history / inactive-replaced-unpaired tracking
   - telemetry RLS/client-role visibility review

6. **Checklist / PM work**
   - mechanic PM bridge aligned with work orders/checklist engine
   - checklist assignment completion lifecycle
   - historical checklist visibility polish
   - offline replay only after idempotency/conflict contract is safe

## Offline-first reminder

Offline checklist response replay contract remains deferred.

Checklist response replay should use `(work_order_id, checklist_item_id)` as the logical identity. Safest server contract is a unique remote constraint on that pair plus upsert by that conflict key. Until then, replay must be conservative and manual/invoked-only.

Replay must not:

- upload/replay photos until attachment handling is designed
- call service interval satisfaction or close/update work orders
- silently overwrite another tech’s response
- use `SyncOperationsTable` as a second source of truth before a broader sync engine exists
- claim “submitted” when rows are only pending local sync

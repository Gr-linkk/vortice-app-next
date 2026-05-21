# Service Report Flow Notes — 2026-05-12

Status: parked; come back later.

## What we attempted

- Wrote the working spec: `docs/SERVICE-REPORT-FLOW-SPEC-2026-05-12.md`.
- Changed service-report policy intent:
  - create/edit: `owner`, `employee`
  - view: `owner`, `employee`, `client`, `client_admin`, `client_mechanic`
  - denied: `operator`, `client_operator`
- Started converting from one service report per work order to many reports per work order.
- Added first-pass local/offline row support:
  - Drift sync fields on service reports
  - app-generated UUIDs
  - local-first create/update path
  - pending sync chips/retry attempts on fetch
- Added RLS/migration work for operator visibility and possible legacy work-order uniqueness.
- Tried to fix navigation from work order → service report form.

## What went badly

- The UI still produced a blank/dead-feeling `Service Report` screen from an in-progress work order on the phone.
- The route/card behavior was confusing: the “Add Service Report” affordance could still land on an empty list/hallway instead of the form.
- Some failure states were hidden with `SizedBox.shrink()`, making debugging from the phone painful.
- APK delivery was a mess:
  - wireless ADB was unreliable for large APK transfer
  - GitHub release asset download failed on the phone/network
  - zip workaround was irritating
  - wired USB install finally worked

## Current local state to review before resuming

Dirty/uncommitted files include service report flow, database, migrations, router, work order/asset cards, tests, and docs. Do not assume this patch is ready to commit.

Important untracked files:
- `docs/SERVICE-REPORT-FLOW-SPEC-2026-05-12.md`
- `docs/SERVICE-REPORT-FLOW-NOTES-2026-05-12.md`
- `lib/features/service_reports/service_report_repository.dart`
- `supabase/migrations/20260512120000_service_report_operator_visibility_fix.sql`
- `supabase/migrations/20260512123000_service_reports_allow_multiple_per_work_order.sql`

## Gates that passed during the attempt

At various points after patches:
- targeted `flutter analyze` passed
- `test/features/service_reports/service_report_workflow_test.dart` passed
- debug APK builds passed, including split-per-ABI ARM64 builds
- wired USB install to `SM_S928W` succeeded

## Do next when resuming

1. Reproduce the blank Service Report screen with a deterministic UI or integration test if possible.
2. Stop routing “Add Service Report” through the generic list path. Staff work-order action should open the form directly.
3. Add a visible, testable empty/error state wherever a list or form provider fails.
4. Verify role/profile on the phone account used for testing; owner/employee only should see authoring.
5. Consider a dedicated `WorkOrderServiceReportEntryPoint` widget test: empty reports + staff + in-progress work order must route to `/service-reports/new?workOrderId=...`.
6. Do not continue deeper offline attachments until basic authoring/navigation is boring and proven.

## Temporary APK delivery notes

- Phone target: `SM_S928W`, ARM64.
- Wired ADB succeeded; prefer USB for future installs.
- GitHub release asset CDN failed on phone with `release-assets.githubusercontent.com` unreachable.
- Temporary raw branch `apk-download` was created with a plain APK; clean it up later if not needed.

## 2026-05-13 Jasper audit — service report authoring actions

Garrett hit a phone-layout failure where the 5C form rendered but the lower page became janky/sticky around Job Photos, leaving Signature and Submit effectively unreachable.

Decision added to spec: Signature and Submit are required reachable actions on the authoring page, not optional controls buried at the bottom of a long scroll. They must behave like primary workflow actions:
- Signature opens capture, saves into draft/report payload, and shows captured state.
- Submit validates required 5C fields and creates/syncs or leaves an explicit retryable pending/failed state.
- Scrollable photos/signature/attachment areas must not trap the user away from the 5C fields.

Implementation direction in this pass: keep the 5C content scrollable, move signature capture into a modal sheet, and expose Signature/Submit both in a persistent bottom action bar and as app-bar fallback actions so they remain reachable on phone screens even if shell/bottom-nav layout gets weird.

## 2026-05-13 Casper/Jasper audit follow-up

Scout audit found the main remaining phone UX risk: `ServiceReportScreen` lives inside `AppShell`, and both had bottom bars. That stacked the shell tab bar under the service-report Signature/Submit action bar, reducing viewport height and likely causing the sticky/janky bottom behavior Garrett saw.

Follow-up patch direction:
- Hide `AppShell` bottom navigation on `/service-reports/new` authoring routes.
- Keep the service-report page's own Signature/Submit action bar as the only bottom bar on that page.
- Keep app-bar Signature/Submit icon actions as fallback reachability.
- Fix signature pad empty-state tracking so Save/Clear enable only after the technician draws.

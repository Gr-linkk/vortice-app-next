# NOW-013: Forward maintenance planning

## Outcome and authority

Garrett approved a substantial slice of fleet planning, explicitly centered on
the inherited Maintenance Plan section where appropriate, with free commits and
pushes. Build on verified Build 15. Preserve the navy design, English/Spanish,
company access, component-linked plans, service approval and account-owned queues.

## Connected journey

- Managers enter Maintenance planning from Home, the primary Planning tab,
  existing Maintenance Plan or an asset. Mechanics enter My schedule.
- Existing `asset_service_intervals` and component readings remain the source
  of upcoming services. Due services, future hour thresholds and missing setup
  are visible; there is no fabricated calendar forecast from hours alone.
- Plan service carries the asset and existing interval into the existing work
  creation form, then opens booking. A plan with open work leads to that work;
  the existing server rule prevents duplicate active maintenance jobs.
- Day, week and month views show bookings. Unscheduled and Needs attention
  expose jobs without times, overdue deadlines, overlaps, blocked work and review.
  Search, asset and assignee filters stay within the server-authorized records.
- Managers book/reschedule a start instant, duration, assignee, priority and
  separate deadline. A reason is recorded; clearing a booking preserves the job.
  Overlap warnings cover the same assignee or asset and are rechecked at save.
- Mechanics follow the existing work-order/report/labour flow. Approval still
  advances only the linked component service. Fault verification and asset
  availability remain explicit. Provider billing retains its existing routes.

## Rules

Bookings are timestamps stored in UTC and displayed in device-local time.
Deadlines remain date-only values in the inherited `scheduled_date` column;
existing dates are not silently converted into bookings. Duration is an estimate,
15 minutes to seven days. Weekly totals are booked hours, not capacity promises.
There is no staff working-calendar, automatic resource optimizer or purchase-order
scope. Planning is online; saved work remains accessible through All work offline.

Server operations require management, planning and execution capabilities, check
revision and assignee scope, serialize scheduling decisions and record immutable
operation payloads for exact retries. Overlaps require explicit acknowledgement
and a reason. Running labour prevents reassignment. Pending field operations
must be resolved before scheduling on that device. Closed/review jobs cannot be
rescheduled. Unauthorized job details are never included in conflict messages.

## Acceptance

Exercise a linked service -> create -> book -> reschedule -> mechanic execution
-> review journey; weekly/monthly discovery, overlap acknowledgement, stale
revision, duplicate retry, invalid assignee, other-company denial and date/time
boundaries. Inspect English and narrow Spanish large-text native renders. Run
guarded Flutter and all isolated SQL suites; build internal 1.7.0+16. Record
actual results here. Deployment uses only the guarded Next migration path;
physical Android evidence is separate from the native test host.

## Verification

Guarded verification against Build 15 commit `742abfe` passed repository guards,
code generation, clean Flutter analysis and 446 tests with 204 existing skips.
The 18 planning tests are included in that total. Final preview confirms hosted
Supabase is up to date. Evidence: `outputs/NOW-013-verify.log` and
`outputs/NOW-013-preview.log`.

The planning migration `20260906200000` is active on the dedicated Next project
`hkjpojobdbbtjkhaudki`. The guarded preview contained only that migration. All
12 SQL contract suites passed both in isolated PostgreSQL and in rollback-only
hosted checks; the local bootstrap was not run against hosted Supabase.

The connected native journey passed all seven steps: existing interval to work
creation, native date/time booking, server overlap rejection and explicit
acknowledgement, rescheduling and unscheduling, mechanic execution/report,
approval advancing the original interval from 250 to 500 hours, and denial for
another company. Exact marked fixtures were removed with unrelated counts
preserved. Evidence: local `outputs/NOW-010-planning013.json`,
`outputs/NOW-013-connected.log` and `outputs/NOW-013-cleanup.log`.

Focused coverage includes half-open time boundaries, missing assignments,
date-only provider services, week-clipped hours, same-payload retries, stale
revision reload and booking navigation when the router reuses the planner.
English and Spanish at 360 px with 1.35 text scale were rendered with real fonts
and visually inspected; calendar and service-plan screenshots are retained in
`outputs/screenshots/planning16/` and `outputs/screenshots/audit010/`.

Review corrected reused-route booking state and preserved the existing
blocked-category payload and provider access filters. Connected tests also
exposed nested text-field scrolling in the test driver; the driver now scrolls
the enclosing list. No physical Android installation, notification delivery or
device permission acceptance is claimed by this native-host evidence.

Internal ARM64 debug Build 16 (`1.7.0+16`) is retained at
`outputs/builds/vortice-next-android-debug-20260906-224339.apk`.
SHA-256: `62f5448318af7b7c55884cd8437d970208667e6d2480fbad479752bdb20d3ddd`.
Package `com.example.vortice_app_next`, the existing Next signing certificate,
dedicated Firebase identifiers, messaging service and recovery callback all
passed APK inspection. The retained artifact matches the inspected build hash.
The build reports the existing future Kotlin-plugin compatibility warning for
`share_plus` and `shared_preferences_android`; it completed successfully.
No phone transfer or installation was performed in this slice.

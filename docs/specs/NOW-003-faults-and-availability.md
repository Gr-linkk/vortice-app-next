# NOW-003: faults and asset availability

Selected 2026-09-05 under Garrett's authorization to choose and build two
features autonomously and deliver an APK to his phone's Downloads folder.

## Outcome

An operator reports a defect. A company manager or provider owner triages and
assigns it. The assigned mechanic records repair progress and submits it for
review. A manager verifies resolution and explicitly returns the asset to
service. All permitted fleet members can follow the status and history.

## Rules

- Existing whole-fleet client organization membership is preserved. Owner
  role means provider owner; client/client_admin means company manager. No
  access to another company's records or attachments is granted.
- Fault intake and availability are baseline fleet capabilities. Existing
  optional checklist capabilities and blocked client work-order routes remain
  unchanged. A fault can be assigned directly to a company mechanic; this
  slice does not introduce a full internal work-order/invoicing system.
- Fault states: open, acknowledged, in_progress, pending_review, resolved,
  dismissed. Legacy converted faults remain active and keep their job links.
- Company managers/provider owner triage, assign, resolve, dismiss and reopen.
  Assigned mechanics/employees can start work, add notes and request review.
  Operators report and read. Resolution, dismissal and reopening need reasons.
- Provider owner can create one linked repair work order atomically from a
  fault. Creating or closing a work order does not resolve the fault or return
  the asset to service automatically.
- Unassessed assets show Not assessed, not an assumed Available status.
  Managers set available, restricted, out_of_service or under_maintenance,
  always with a reason. Availability and history are server authoritative.
- Out of service and under maintenance count as downtime. Switching between
  them preserves the start time. Returning to restricted/available ends that
  episode; previous downtime is retained. Unresolved urgent faults prevent
  Available until reviewed/resolved or dismissed with a reason.
- State changes are transactional, actor-attributed and protected by expected
  version checks. Report and mutation operation IDs make retries idempotent.
- New writes require connectivity. Failed saves retain form input and display
  retry guidance. No new offline-write queue or false offline-success claim.

## Scope and persistence

Extend maintenance_requests with assignment, revision and closure fields;
append-only fault events. Add asset operating-state and state-event tables.
Use guarded RPCs for writes and scoped RLS/read RPCs for reads. Add one fleet
screen, fault report/detail screens, availability editor/history, and entry
points in existing dashboards/assets/operator navigation. Existing visual
language and English/Spanish support are retained.

Code inspection also found signup trusted user metadata for role, org and
subscription. As a prerequisite to the new permissions, signup now derives
these from a validated server-held invite or server-managed app metadata.
Invite expiry, usage and checklist-role capability are checked and consumed
transactionally; the app no longer attempts to repair its own role after signup.
Existing profiles are not reassigned.

## Acceptance proof

- Multi-role SQL tests run within a transaction and roll back synthetic data.
- Tests cover cross-company access, direct-write denial, stale edits,
  duplicate retry, role transitions, linked-job behavior and downtime.
- Flutter tests exercise report validation, status actions, empty/error
  states and phone-width layouts; screenshots render actual Flutter widgets.
- Run scripts/verify.cmd and guarded Android build against Vortice Next.
- Deliver a versioned internal APK plus checksum; verify the file on the phone.

Production signing, branding overhaul, push notifications, inventory, telemetry
runtime changes and the original Vortice environment are outside this slice.

## Deployment and recovery

The only target is Next `hkjpojobdbbtjkhaudki`. The migrations
`20260905120000_faults_and_availability.sql` and
`20260905121000_signup_role_boundary.sql` were deployed through the guarded
helper after Garrett's explicit hosted approval on September 5 (2026-09-06 UTC).
The first adds workflow data and replaces direct
fault mutations with checked RPCs. The second corrects signup role assignment;
existing profiles are not rewritten. Neither migration deletes existing rows.

The new APK and backend changes form one activation. Older APK fault writes will
be denied after migration; use this APK for the new workflow. Do not revert to
the insecure signup function or drop history tables as an automatic rollback.
If validation fails, pause use of the new workflows and prepare a reviewed
forward correction preserving recorded data. A database-wide restore is a
separate explicitly approved operation.

## Current verification record

2026-09-05: prescribed verification passed (analyzer clean, 289 tests passed,
204 existing skips). Both database contract suites passed on the complete
baseline plus these migrations in isolated PostgreSQL 17. Six rendered Flutter
screenshots were inspected, including Spanish and enlarged text. Direct review
was performed; no independent review is claimed.

Internal APK 1.1.0+2 (`com.example.vortice_app_next`) built successfully and was
copied to Garrett's S24 Downloads folder. Phone-side SHA-256 verification passed.
The build and screenshots are in ignored `outputs/`; details are in
`outputs/NOW-003-build-notes.md`. This original build has been superseded by
1.2.2+7. Physical-device workflow testing remains pending.

Hosted activation completed 2026-09-06 at approximately 01:00 UTC, after
Garrett explicitly approved both migrations. The guarded helper targeted only
Next `hkjpojobdbbtjkhaudki`; remote migration history matches all three local
versions. Both hosted SQL contract suites passed and rolled back their fixtures.
A follow-up query confirmed zero remaining synthetic test users.
HTTP checks passed for all six existing internal personas: Auth login, profile
read and the new `maintenance_fleet` RPC. No app data was changed by these HTTP
checks. Build 7 already includes the matching client; no rebuild is required.

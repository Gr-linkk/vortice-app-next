# NOW-011: trusted field work and access recovery

Garrett authorized all six recommendations after NOW-010, including free commit
and push of the work. Continue from audited commit `c6d42e0` on an isolated branch.
The existing appearance and English/Spanish support remain the UI baseline.

## Delivery stages

1. Close the request-photo privacy gap and isolate local databases, profile
   snapshots and drafts by authenticated account. Retain unattributed legacy
   local files without exposing or silently assigning them to another user.
2. Persist field submissions and their media before uploading. Reopening after
   restart shows pending/failed/synced status. Retrying an acknowledged or
   interrupted submission must not create duplicate records.
3. Complete operator checklist evidence and atomic run/response/history writes.
   Required answers, notes and evidence are validated on the server; no complete
   run is exposed before all required pieces are committed.
4. Deliver assignment, urgent-fault, review and approaching-inspection push
   notifications using a dedicated Next Firebase project, scoped device tokens,
   delivery retries and authorized deep links. Surface notification readiness
   and permission state honestly when device/service setup is absent.
5. Replace access-help-only password recovery with reset email, app callback,
   validated new password, expired-link/error handling and return to work.
6. Build and verify the Android package, and exercise physical-device camera,
   permissions, Back, keyboard, restart and interrupted-upload behavior whenever
   an authorized device is available. Record any unavailable external dependency.

## Required contracts

- Only independent origin and Supabase `hkjpojobdbbtjkhaudki`; no credentials,
  identities or services from the original application.
- Each queued operation belongs to the account that created it; sign-out or
  switching accounts never uploads another account's work. No last-write-wins
  overwrite of revision-controlled maintenance actions.
- The server authorizes every submitted subject, item and attachment. Private
  media remains private after a public-URL migration and after account changes.
- Distinguish saved locally, pending upload, uploaded and needs-attention states.
  A local save cannot claim server completion. Preserve user input on failure.
- Notifications use server-selected recipients and minimal lock-screen content;
  opening a notification rechecks current access. Token reassignment and sign-out
  cannot route a previous account's notification to the next user.
- Password recovery uses the Next auth provider; email responses do not disclose
  whether an account exists. Build configuration and callbacks stay separate from
  the original application.

## Validation

Use failing behavior tests before each reliability/privacy fix, then focused
regressions, server permission/replay contracts, connected saved-workflow tests,
English/Spanish phone-size rendering and the guarded complete verification.
Use synthetic records and remove fixtures. Commit and push checked stages;
record activation, external delivery and physical-device proof separately.

No original-project changes, main merge, public store release or telemetry
collector work is included. Selecting a separate Firebase project and connecting
the S24 are requested early while independent implementation continues.

## Implemented and activated, September 6

- Account-owned databases, profile/fleet/job/checklist caches and report drafts;
  durable photo and field-operation queue with pending/synced/attention states,
  foreground retries, restart recovery and correction of rejected submissions.
- Mechanic start/pause/block, parts and reports use immutable operation IDs and
  revision checks. Device labour timestamps survive replay. Account changes
  cannot send an old account's queue using a new account's session.
- Operator photos upload before one atomic run/answers/history transaction.
  Accepted photo retries verify exact bytes even when the finalized checklist's
  write policy has closed. Replaying a run creates no duplicate history.
- Request photos use authenticated reads, including existing Next public-URL
  references. Private operator and maintenance photos reject other companies.
- Dedicated Firebase project, Android registration and a sender role containing
  only `cloudmessaging.messages.create`. The Next worker and one-minute schedule
  are active. Google OAuth and FCM validation pass; unauthorized worker calls
  return 401. The cron health check reports an active schedule and a successful
  recent run; there are zero registered devices. No real device delivery is claimed.
- Password-reset request, recovery callback, new-password form, one-use-link
  handling and return to sign-in. Next's redirect allowlist is active. A live
  synthetic recovery account passed exchange, password change, old-password
  denial, new-password login and consumed-link denial, then was removed.

Garrett explicitly approved all four migrations. Versions `20260906090000`,
`20260906091000`, `20260906092000` and `20260906093000` are applied to Next.
All ten hosted SQL contract suites pass, including permission, revision,
transaction and notification-delivery contracts. The original services remain
outside this change.

Connected Flutter validation passes four field reliability steps and nine
existing maintenance/fault/availability/handover/history steps. The new field
test closes/reopens actual SQLite files and wraps the production network sender
to simulate offline work and lost acknowledgements. It checks hosted records,
photo bytes and cross-company denial. The report Back/reopen test preserves the
local diagnosis. The operations harness scroll reset was corrected to avoid
leaving a test-induced overscroll animation active during route disposal.

English and Spanish saved-work screens pass at 320 px with 1.3x text and real
Android fonts. Screenshots are in `outputs/screenshots/field011/`. This run's six
synthetic assets, their dependent records and 63 photo objects were removed;
unrelated assets, work, requests, invoices, operator history and other tracked
counts remained unchanged. The cleanup manifest also retains prior audit IDs.

Final `scripts/verify.cmd` passes repository guardrails, generation, clean
analysis and 407 Flutter tests with 204 existing skips. Two notification-payload
Node tests also pass. The PowerShell capture appended an informational native
stderr record after the helper printed `Project verification passed`; every
required command inside the guarded helper succeeded.

Internal Build 13 is `1.6.0+13`, package `com.example.vortice_app_next`, file
`outputs/builds/vortice-next-android-debug-20260906-064318.apk` (174,134,338 bytes).
SHA-256: `f796fefaca66a2ec32b5d59405ad82bbb80876037fa920da0753be300a195f3a`.
APK inspection confirms the signature, version, all four native Firebase
options, Android messaging service, notification permission and recovery
callback. Client options are distinct from the private sender key.

## Remaining acceptance dependencies

- Garrett has no sending domain yet. Customer reset-email delivery requires a
  domain and SMTP provider; Supabase's default service is limited to authorized
  team addresses. No customer email delivery was claimed or tested.
- Windows and WSL ADB have no connected device. Physical installation, camera,
  permission prompts, Android Back/keyboard, forced process restart, interrupted
  upload and a notification while the app is closed remain device acceptance.
  Native host tests and APK contents are not substitutes for those checks.
- Garrett requested the phone Downloads copy. Build 13 was transferred to
  `/storage/emulated/0/Download/INSTALL-Vortice-Next-Build-13.apk` on the verified
  S24 and its SHA-256 matches the inspected APK. The extra computer Downloads
  copy was removed at Garrett's request. Installation and physical acceptance
  remain separate; no main merge or store release was requested.

Setup and future operations: `supabase/operations/README.md`. Durable decisions:
`docs/decisions/0008-field-reliability.md`.

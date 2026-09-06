# Product Backlog

This is the only live project priority list. Detailed specifications may live
elsewhere, but every active task must be represented here with a stable ID.

## Now

### NOW-008 — Connected workflow audit

Garrett requested an end-to-end audit of all features built today: interact with
the real app, fill and submit forms, create and remove test data, exercise
requests, work orders and reports, and inspect persisted results. Continue from
Build 10 and fix confirmed problems within these workflows. Track tested
journeys, defects, retests and device limits in `outputs/NOW-008-e2e-audit.md`.
Use clearly marked disposable records in the isolated Next environment.

The connected audit found and corrected report discovery/sync/media/date issues,
cost precision, reapproval copy, provider hour validation and operator checklist
validation/serialization. Five local and hosted SQL suites and the populated
report upgrade pass; full native verification passed 380 tests with 204 existing
skips. Results and exact live-versus-contract coverage:
`docs/specs/NOW-008-connected-audit.md`. Concurrent client sessions and the
cross-company direct-link denial passed; the E2E-008 fixture and its uploaded
images were removed with unrelated record counts preserved. Device checks and
legacy operator photo support/transactional retries remain open.
Build `1.4.1+11` is delivered to Samsung Downloads as
`INSTALL-Vortice-Next-Build-11.apk`; phone checksum and media indexing passed.

### NOW-007 — Asset history, handovers and fleet decisions

Garrett delegated selection and complete delivery of three further features,
including review, tests and an APK. Selected original areas 14, 15 and 16: one
asset history, job/fault discussion and shift handover, and an actionable fleet
dashboard. Extend the current maintenance, fault and availability workflows.
Scope, access rules and observable acceptance:
`docs/specs/NOW-007-fleet-coordination.md`. Build from verified `1.3.1+9`.

Deliver the integrated native UI, checked server operations and migration,
English/Spanish render and interaction proof, SQL authorization contracts, full
Flutter checks, and the next internal APK in the phone's Downloads. The three
additive migrations are active only on the guarded Next project. All four
hosted rollback suites and six persona HTTP checks pass. Native analysis is
clean; 360 tests pass with 204 pre-existing skips. Package and device-delivery
evidence is recorded in `outputs/NOW-007-build-notes.md`. Build `1.4.0+10`
is delivered to the Samsung Downloads folder as
`INSTALL-Vortice-Next-Build-10.apk`; the phone copy passed its checksum check.
Physical installation and device review remain open.

### NOW-006 — Continue the remaining feature areas

Outcome: choose and deliver the next useful end-to-end feature from the 20
remaining areas in the original 22-item assessment. Garrett requested a new
project task for this continuation after the initial two features and UX work.
Inventory, existing foundations and proposed next discussion:
`docs/specs/NOW-006-feature-continuation.md`.

Garrett selected original items 1, 4 and 5 together: company-owned maintenance,
mechanic execution, and trustworthy maintenance completion. Implement one
connected journey under this ID. Scope and acceptance:
`docs/specs/NOW-006-company-maintenance.md`. NOW-007 owns the next three;
the other 14 areas remain intake.
The Build 7 device review remains open; it does not block this authorized work.

Items 1, 4 and 5 are implemented and verified for internal build `1.3.0+8`:
clean analysis, 337 passing tests, 204 existing skips, all three isolated SQL
contract suites, and English/Spanish rendered maintenance screens. Garrett
approved hosted activation; the maintenance migration deployed to Next on
2026-09-06 UTC. All three hosted SQL suites and six persona HTTP checks passed.
Physical-device review remains open. Evidence and limits are recorded in the
company-maintenance specification.

### NOW-005 — Make the whole app easier to navigate and use

Outcome: existing and new workflows feel like one app for less technical users.
Garrett authorized a broad UX pass, including removal of unnecessary duplication.
Specification: `docs/specs/NOW-005-ux-cohesion.md`.

Completed spacing follow-up for `1.3.1+9`: restored maintenance-form gaps,
standardized all 38 form dropdowns, audited expanded menus, and protected bottom
actions from Android system bars. Native English/Spanish and large-text renders,
clean analysis, and 343 passing tests (204 existing skips) verify the changes.
Build 9 is in phone Downloads with checksum and media indexing verified;
physical-device review remains open. Evidence: `outputs/NOW-005-form-build-notes.md`.

Implementation is verified for internal build `1.2.2+7`: clean analysis and
328 passing tests (204 existing skipped walkthrough checks). Awaiting Garrett's
device review; findings and evidence are recorded in the specification.
Build 7 is in phone Downloads; its checksum and media indexing are verified.

Follow-up: restore Sign out at the top right of every profile's home dashboard
while retaining it in More. Both entry points share the same confirmation.

Completed follow-up: standardized every dashboard around a shared Home header,
greeting, fleet status, action cards, and section headings. Keep role-specific
work and capability gates while removing redundant shortcut layouts.

- Consistent role-aware navigation exposes the main work and a searchable tools
  directory without losing existing functionality or bypassing capability rules.
- Fix misleading routes, duplicate dashboards and inert controls; use plain
  language, actionable errors and recoverable empty/search states.
- Asset, fault, checklist, work-order, report, invoice and request journeys keep
  clear context and protect entered work from accidental navigation.
- Verify role routing and changed interactions, render phone/large-text states,
  run prescribed checks, and deliver an internal APK for review.

### NOW-003 — Fault-to-repair tracking and asset availability

Outcome: report an asset fault, assign and track its repair, verify resolution,
and explicitly record availability and downtime in an internal Android build.

Selected by Garrett's September 5 request to autonomously build two features
and deliver an APK to his phone. Specification:
`docs/specs/NOW-003-faults-and-availability.md`.

Both backend migrations are deployed to Next after Garrett's explicit approval.
Hosted SQL contracts and six internal persona HTTP fleet checks passed on
2026-09-06 UTC. Build 7 is delivered; physical workflow review remains open.

Acceptance criteria:

- Fleet-scoped fault reporting, assignment, progress, review and event history
  work for company owners/admins, mechanics, operators and provider staff.
- Authorized managers record availability changes with reasons and history;
  downtime survives transitions between unavailable states.
- Cross-company access, invalid transitions, stale edits and duplicate retries
  are rejected or handled safely by the backend, not only the UI.
- Flutter verification, database authorization tests and rendered UI checks
  pass; the isolated internal APK is copied to the phone's Downloads folder.

### NOW-001 — Choose the product identity

Outcome: replace the working Vortice Next name with the chosen product name.

Acceptance criteria:

- Product name and customer-facing language are approved.
- Android and iOS application IDs are selected intentionally.
- Repository, app metadata, icons, documentation, and backend naming impacts
  are inventoried before implementation.
- Production signing remains out of scope unless separately approved.

## Next

### NEXT-001 — Audit invoice authorization before real client data

Confirm invoice RLS, client scoping, export authorization, and role-based UI
behavior together before non-mock invoice data is introduced.

## Later

### LATER-001 — Establish production mobile identity and signing

Replace placeholder application IDs and debug signing, then establish a
repeatable signed release process. Until this is complete, builds are internal
or test artifacts only.

### LATER-002 — Define the app/telemetry runtime boundary

Document ownership, contracts, environments, and deployment flow before adding
collector or Raspberry Pi runtime work to this repository.

## Intake rules

- Add new ideas to `Later` unless Garrett explicitly changes priority.
- Moving work into `Now` requires an outcome and acceptance criteria.
- A pull request names one primary backlog ID; incidental fixes are called out.
- Remove completed items in the same pull request that delivers them and record
  durable outcomes in a decision or current specification when needed.
- Do not create competing priority lists in session notes, issues, or plans.

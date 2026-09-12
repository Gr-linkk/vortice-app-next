# Product Backlog

This is the only live project priority list. Detailed specifications may live
elsewhere, but substantive product/implementation tasks must be represented
here with a stable ID. Incidental mechanical fixes may reference existing scope
without creating a new backlog item.

## Now

### NEXT-002 — Human-centered workflow consolidation

Garrett authorized autonomous execution, review, commits/pushes and necessary
Next Supabase migrations on September 12, 2026. The board and dependency order
are `docs/specs/NEXT-002-human-workflow-kanban.md`; decision 0016 owns the
organization-membership direction. Garrett subsequently requested the entire
board and APK delivery to S24 Downloads. Whole-board scope, integration evidence
and remaining external/physical acceptance are recorded in
`docs/specs/NEXT-002-whole-board-delivery.md`. Email/SMS provider setup is deferred
at Garrett's request. Existing accounts and the Ellicott graph are preserved;
the transition is additive and does not perform the proposed account reset.

## Prior delivery and acceptance references

NOW-022, NOW-023 and NOW-024 are merged, verified and delivered as Build 27.
Integration evidence: `docs/specs/NOW-022-024-integration.md`.


### NOW-022 — PM kits, parts readiness and stock

Garrett approved building the connected kit-to-stock workflow, verification,
commit, push and APK delivery to S24 Downloads. Job-specific requirements,
location stock, reservations, purchase tracking, receipts, use and returns build
on the existing PM kits. Scope and acceptance: `docs/specs/NOW-022-parts-readiness.md`.

Implemented and active on Next. Clean analysis and 593 Flutter tests pass,
alongside all 21 hosted SQL suites and eight connected native stages, including
Spanish dark mode at 200% text and company isolation. Exact test fixtures are
removed with unrelated counts preserved. Build 26 (1.13.0+26) is verified and
delivered to S24 Downloads with matching SHA-256; code is pushed on
`codex/parts-readiness`. APK and delivery evidence are in the specification.
Physical Android installation and interaction remain separate acceptance.

### NOW-023 — Configurable maintenance recurrence

Garrett approved flexible hours/calendar recurrence, completion-based schedules,
fixed milestones and explicit transition targets, with adjustable settings for
each component and optional included services. Preserve appointment separation,
checked completion and company isolation. Scope and verification:
`docs/specs/NOW-023-maintenance-recurrence.md`; decision 0015.
Developed independently of the concurrent NOW-022 parts workstream.
### NOW-024 - Equipment cost, downtime and repeat-fault report

Garrett selected equipment reporting after deferring QR labels. Deliver a
manager-only report with month/quarter/custom periods, recorded internal and
outside-service costs, interval-correct downtime, possible repeat faults,
source drill-down and CSV export. Missing data remains explicit.
Scope and acceptance: `docs/specs/NOW-024-equipment-reporting.md`.

Implemented, integrated and active on Next in Build 27. Combined verification,
hosted contracts and delivery evidence are recorded in
`docs/specs/NOW-022-024-integration.md`; physical phone review remains separate.

### NOW-021 — Populate the existing app for a demo

Garrett requested a populated demonstration that retains the Ellicott dredge and
uses local manuals where available. Hosted demo data is populated and 130 role
and route checks pass. The existing Ellicott identity, components and history are
retained. Follow-up located the WSL unit manual, verified its cover serial and
ladder-servicing page, and added source pages plus a linked checklist/plan/job.
Four focused company-manager screen checks pass. The requested heavy-use
expansion now includes 32 assets, 154 work orders, 124 operator checklist runs,
89 reports, 52 inspection requirements and 31 invoices. Mechanics, both operator
profiles, inspection attachments, parts, faults and histories are populated.
The expanded data passes 130 route checks and seven focused screen checks;
pre-expansion rows were preserved. Scope, saved evidence and demo entrypoints:
`docs/specs/NOW-021-demo-population.md`.

### NOW-020 — Simplify existing code without losing behavior

Garrett requested a whole-code simplification pass, verification, push and a new
APK in S24 Downloads. Consolidate exact duplicate implementations and remove
verified unreachable remnants; preserve active features, presentation, data,
role checks and recovery behavior. Scope and results:
`docs/specs/NOW-020-code-simplification.md`.

Implemented: 729 net production Dart lines removed, with all existing workflows
retained. Clean analysis and 583 Flutter tests pass with zero skips. Build 25
(`1.12.2+25`) is pushed and delivered to S24 Downloads with a matching checksum;
inspection and delivery evidence are in the specification. Installation and
physical-device acceptance remain separate.

Connected follow-up passes all eight journeys (48 workflow steps plus seven
custody checks) and 260 role/route checks across both themes, English/Spanish and
200% text. A test-only save/dismissal timing correction passed its rerun; Build 25
app code is unchanged. Exact fixture cleanup and coverage limits are in the spec.

September 7 stress-audit corrections to NOW-016/NOW-017 are integrated into
Build 23 from `codex/stress-audit-fixes`. Scope and verification:
`docs/specs/2026-09-07-stress-audit-fixes.md`.

### NOW-018 — Broader equipment catalog and complete category artwork

Add practical small-boat, commercial-fishing and land-equipment types while
preserving existing type IDs and assets. Every standard type must have a distinct
bundled technical illustration, including in the add/edit type picker. Scope,
catalog and acceptance: `docs/specs/NOW-018-equipment-catalog.md`.
Implemented 19 additions (32 standard types total), including distinct marine,
mobile and tower cranes plus davits. Clean analysis, 519 Flutter tests (204
existing skips), 18 local SQL suites and native artwork/form checks pass.
The catalog is active on Vortice Next; hosted checks confirm all 32 choices and
preservation of the original 13 rows. Build 21 is delivered to S24 Downloads with
matching SHA-256. Physical-device acceptance remains separate; see the spec.
Follow-up adds LV / Light Vehicle and Highway Truck (34 types total) and fixes
floating-button text/icon contrast throughout the app. Clean analysis, 535
Flutter tests, and local/hosted catalog checks pass for Build 22; see the spec.

### NOW-019 — Scoped agent access

Build fleet-scoped agent access through a restricted API and local MCP adapter.
Scan/import manuals, combine them with component hours and task-specific service
history, and produce editable PM/pre-op and maintenance-plan drafts. Users
review/publish/apply in the app. Separate permissions allow creating work drafts
and assigning, scheduling or editing work. Preserve live role/capability checks,
expiry, revocation and activity history.
Scope and acceptance: `docs/specs/NOW-019-agent-access.md`; decision 0014.
Originally developed separately from equipment/UI and stress-test work; now
integrated below. Real agent/device acceptance remains separate.

Integrated with all completed worktrees for Build 23 (`1.12.0+23`). Owner keys
require MFA. Next agent migrations/proxy are active; 561 Flutter tests pass
without skips. Real agent/device acceptance remains; see the spec.
Follow-up Build 24 adds the agent workspace, source/equipment/service evidence,
before-and-after interval review and a live preview while editing.

### NOW-017 — Field Notes UI and saved appearance

Garrett approved implementing the rendered UI audit and Field Notes concept.
Apply native light/dark themes, saved System/Light/Dark settings, fine offline
equipment art, work-first Home, schedule-first Planning and form/navigation
refinements. Preserve the concurrent NOW-016 workflow fixes. Scope and acceptance:
`docs/specs/NOW-017-field-notes-ui.md`; accepted decision 0013.
Integrated NOW-016 and packaged Build 20 (`1.10.0+20`). Combined verification
passes: clean analysis, 506 tests and 204 existing skips. Connected audits pass
130 role/routes in each appearance. Native renders include Spanish and enlarged
text. APK identity, signature and Next services are verified; physical device
acceptance is separate. Build 20 was delivered to S24 Downloads at Garrett's
request, with matching source/phone SHA-256; installation was not performed.

### NOW-016 — Existing workflow closeout

Finish and stabilize existing invoicing, saves, evidence recovery, offline access,
notifications and customer UI before adding features. Scope and fresh acceptance
evidence: `docs/specs/NOW-016-existing-workflow-closeout.md`. Build and inspect an
internal Android APK; do not transfer or publish it.

Implemented and packaged as Build 19 (`1.9.1+19`). Four Next migrations and the
event-specific notification titles are deployed. Clean analysis, 474 Flutter
tests (204 existing skips), 17 local/hosted SQL suites, connected workflows and
130 route checks passed; the saved workflow timing assertion was corrected and
its full journey rerun successfully. Exact test fixtures were removed. APK
identity/signature/hash are checked; no transfer or installation occurred.
Garrett confirmed existing phone alert receipt. Build 19 physical acceptance is
pending his morning testing; exact steps and release dependencies are in the spec.

### NOW-015 — Checklist builder and connected PM/pre-operation workflows

Implemented the checklist builder Garrett approved for client companies and
the owner. Shared starters and private company copies support drafts, immutable
publications, rich steps, PM plans/work orders and assigned pre-operation checks.
Failed pre-op results connect to faults, corrective work and explicit verification.
Scope and evidence: `docs/specs/NOW-015-checklist-builder.md`; decision 0012.

All three Next migrations are active, with 14 local and 14 hosted SQL suites
passing. Connected acceptance passes 54 workflow checks and 130 role/route checks.
Guarded verification passes with clean analysis, 467 tests passed and 204 existing
skips. Build 18 (`1.9.0+18`) is packaged and its Next identity/signature and
checksum are verified. Physical phone installation and
camera/permission checks remain separate from automated evidence.

### NOW-014 — Company internal work orders

Garrett approved giving each client company internal work orders modeled on the
owner's workflow, including preventive maintenance, repairs, inspections and
general work. Align creation, editable preparation, details, reports and planning
while preserving company isolation, internal costs and checked completion.
Scope and evidence: `docs/specs/NOW-014-internal-work-orders.md`; decision 0011.

Implemented in Build 17 (`1.8.0+17`). The Next migration is active; all 13 local
and 13 hosted SQL suites pass, alongside six connected internal-work-order steps
and seven planning regression steps. Guarded verification has clean analysis and
458 passing Flutter tests (204 existing skips). Exact fixtures were removed.
Physical-device acceptance remains separate.

### NOW-013 — Forward maintenance planning

Garrett authorized a substantial planning slice built around the existing
Maintenance Plan/service-interval section, with free commits and pushes.
Make planning prominent: week/month/day views, unscheduled and attention queues,
existing service plans, mechanic booked hours, assignment and conflict-aware
scheduling. Preserve component-specific completion, billing, role boundaries
and offline execution. Scope and acceptance: `docs/specs/NOW-013-maintenance-planning.md`.
Bookings and deadlines are distinct; an overlap requires an explicit reason.
Hosted activation and physical-device acceptance are reported separately.

Implemented in Build 16 (`1.7.0+16`). The Next planning migration is active;
12 local and 12 hosted SQL suites plus all seven connected planning/execution
steps pass. Guarded verification has clean analysis and 446 Flutter tests
(204 existing skips). Marked fixtures are removed. Physical-device acceptance
remains separate; artifact details and review evidence are in the specification.

### NOW-012 — Direct workflows and fewer competing actions

Garrett requested a simpler fault screen that clearly leads into work orders,
followed by an audit for similar simplifications. Create or link a managed repair
from a fault, show its progress and open the right workflow for company/provider
teams, and keep fault verification and asset availability explicit. Simplify job
action hierarchy and audit adjacent entry points. Scope, audit and verification:
`docs/specs/NOW-012-direct-workflows.md`. New hosted activation is separate from
local implementation and validation.

Garrett approved the remaining audit simplifications and connected E2E testing:
asset action hierarchy, direct service-report entry, and one scoped Work list
with distinct maintenance/service routes. Continue this slice on the current
branch; preserve billing, role access and field queues. The Build 14 migration
is active; subsequent UI verification and connected results belong in NOW-012.

Build 15 closeout is committed as `742abfe` and included in the NOW-013 branch.
Fresh baseline verification passed with clean analysis and 428 Flutter tests
(204 existing skips); the full current slice is verified again under NOW-013.

### NOW-011 — Trusted field work, notifications and account recovery

Garrett authorized all six post-audit recommendations and free commits/pushes.
Continue from verified audit commit `c6d42e0`: repair private request evidence and
account-isolated offline data first; implement durable/retryable field submissions,
complete operator checklist photos and atomic completion, real push delivery,
password recovery and Android acceptance. Stages, access rules and verification:
`docs/specs/NOW-011-field-reliability.md`. External service activation and actual
device evidence must be reported separately from code and synthetic tests.

Implemented in internal Build 13 (`1.6.0+13`). The four approved Next migrations,
Firebase notification sender/worker schedule and recovery callback are active.
Ten hosted SQL suites, four connected field-reliability steps, nine operations
regressions and live synthetic recovery pass. Test assets and photos are removed.
Open acceptance: customer SMTP/domain setup and physical Android testing. APK
inspection passes; Build 13 is in the S24 Downloads folder with a verified hash. Full evidence
and artifact hash are in the specification.
Final guarded verification passes with clean analysis, 407 Flutter tests and 204
existing skips; two notification-payload tests also pass.

### NOW-010 — Whole-app workflow audit

Garrett requested end-to-end testing across the whole app to find broken or
incomplete workflows. Continue from Build 12 (`4084d19`) in an isolated audit
branch. Exercise actual native screens against Next with disposable E2E-010
records, including role navigation, assets/plans, maintenance, provider work,
reports, faults, coordination, inspections, operator checks, parts, invoices,
team/invites and telemetry read states. Verify saved outcomes, permissions,
validation and recovery. Fix confirmed in-scope defects with regression proof.
Record coverage, findings, retests, cleanup and limits in
`docs/specs/NOW-010-full-app-audit.md` and local `outputs/NOW-010-*` evidence.

Audit evidence: 122 role/route visits, nine request-to-billing/isolation steps,
nine maintenance/fault/availability/handover steps, the custody/renewal journey
and all six hosted SQL suites pass. Confirmed online account-cache, invoice
labour/validation and direct-entry navigation defects are repaired locally.
All 12 test assets and four synthetic uploads were removed.
Guarded verification passed with clean analysis and 390 tests (204 existing skips).

The audit's P1 request-photo privacy, P1 offline account ownership and P2 atomic
operator checklist/photo transport findings are implemented under NOW-011. Physical-device
and uncovered legacy save workflows must not be inferred from route coverage.

### NOW-009 — Asset custody and inspection renewals

Selected under Garrett's delegated feature choice: original areas 19 and 20.
Build on verified Build 11, commit `655f96b`, in an isolated feature branch.
Scope and acceptance: `docs/specs/NOW-009-custody-inspections.md`.

- Managers record an asset's site, responsible company member and lifecycle,
  with a required reason and immutable transfer history; stale edits fail.
- Teams register inspections, attach private evidence and submit renewals.
  Managers approve or return a renewal; prior approved evidence stays visible.
- Asset navigation and a fleet register expose upcoming, expired and
  review-needed inspections in English and Spanish.
- Server permissions, validation, retry handling, persistence and connected
  workflows pass, including other-company denial and test-record cleanup.
- Run guarded verification and deliver internal Build 12, commit and push the
  feature branch. No main merge or production release.

Implemented and verified: clean analysis, 388 passing tests (204 existing skips),
all six hosted SQL suites, and connected native save/reopen, return/resubmit,
approval, renewal, role and cross-company media journeys. Test records and
objects were removed with unrelated counts preserved. Evidence and device
coverage limits are recorded in the specification.
Internal `1.5.0+12` is delivered to Samsung Downloads as
`INSTALL-Vortice-Next-Build-12.apk`; its phone SHA-256 matches the verified APK.
Physical installation and interaction remain for device review.

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
`docs/specs/NOW-006-company-maintenance.md`. NOW-007 owns the next three and
NOW-009 owns areas 19 and 20; NOW-022 owns area 12 and the other 11 remain intake.
Area 12 is now selected under NOW-022. The Build 7 device review remains open;
it does not block this authorized work.

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

## Pending product decision

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

### NEXT-002 — Board reference (active under Now)

Garrett initially saved the workflow-simplicity Kanban from the September 10-11
app review, then authorized execution on September 12. Make work
orders the common work hub; connect planning, recurring maintenance,
inspections, faults, service requests, checklists, service reports, parts and
record discussions through clear next actions. The board also records
onboarding, flexible meters, additional land-equipment artwork, personal agent
access and later messaging/managed-agent ideas.

Execution status is recorded on the board. Consolidated priorities, decisions, acceptance criteria and
open choices: `docs/specs/NEXT-002-human-workflow-kanban.md`. The accepted
organization membership and role direction is decision 0016.

NEXT-002 takes priority over the unselected feature inventory retained under
NOW-006. Keep those older ideas as reference; do not select additional feature
expansion until Garrett revisits that direction after this workflow board.

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

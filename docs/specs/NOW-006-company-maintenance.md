# NOW-006: Company maintenance, execution and completion

Garrett explicitly selected original assessment items 1, 4 and 5 together.
Build on the current navy dashboard and fault/availability workflows.

## Outcome and rules

- Company managers manage their fleet's assets, components and hour-based plans;
  create internal work orders with priority, due date, instructions and assignee.
- Mechanics see My Work; start/pause separate labour sessions, record parts and
  internal costs, diagnosis, repair notes, checklist answers and private photos;
  block/resume work and submit it for manager review.
- Managers approve or return with a reason, reopen repairs, and create linked
  follow-up jobs. Completion never requires an invoice or automatically returns
  an asset to service. Fault resolution remains a separate explicit review.
- Each scheduled job references one exact plan and component. Its checklist is
  snapshotted at creation. Approval requires completed answers/evidence, repair
  notes, stopped labour and a valid completion meter. It atomically closes the
  job, records history and advances only that plan. Repeated requests have the
  same result; stale edits and mismatched retry payloads fail explicitly.
- A reopened approved job does not rewind a service baseline or advance it twice.
  A fresh service uses a new linked job. Company and provider teams use the same
  completion operation. Unlinked checklists remain inspection history, never an
  inferred service completion based on a template name.

## Implementation boundaries

Reuse assets, components, work orders, service reports and parts. Add operational
metadata, labour sessions, immutable events and completion receipts. New managed
jobs use transactional RPCs and cannot be mutated by legacy direct table writes.
Legacy provider records retain their read/history workflows; invoice creation
must reject internal jobs. New private evidence has job-scoped storage policies.

Company fleet membership follows CONTEXT.md. Company execution respects the
existing pm_checklists capability; plan management respects maintenance_planning.
Managers retain history when a capability is disabled. UI gates mirror server
checks; operators cannot perform mechanic work or manage plans.

Writes require connectivity. Forms keep failed input and a stable operation ID;
visible saved drafts and explicit retry cover interrupted submissions. A full
offline work/download queue remains original item 7. Never claim a partial save
completed a service. No calendar-based scheduling expansion (item 8), inventory
transactions (12), invoice redesign, or production release.

## Observable acceptance

1. Company A manager creates/assigns a job; A mechanic completes two labour
   sessions, logs a part and evidence, submits, and receives an approval/return.
   Company B cannot read/change its records or evidence, including direct calls.
2. Closing internal work creates no invoice; costs show as internal labour/parts.
3. A generator service advances its selected plan while the propulsion engine
   remains unchanged. Required checklist/evidence and meter checks run on server.
4. Retry after an uncertain response creates one job, labour event, report and
   completion. A rejected approval leaves both job and due-state unchanged.
5. Company and provider execution use the same service-completion rules; reopened
   jobs and follow-ups retain truthful history.
6. Role tests, SQL contracts, narrow English/Spanish large-text widget rendering,
   and scripts/verify.cmd pass. Produce an internal APK; report hosted activation
   separately. The previous hosted approval covered NOW-003's two migrations;
   this build prepares the separate maintenance migration for activation review.

## Implementation and verification, 2026-09-06 UTC

- Implemented native English/Spanish assets, components, plans, work list,
  creation, labour/parts execution, report/evidence, supervisor review, reopen
  and linked follow-up journeys. Primary Work navigation covers both company
  and provider teams; existing billed service work remains in More.
- Added `20260906010000_company_maintenance.sql`. Isolated PostgreSQL 17
  contracts passed for the full migration chain and all three SQL suites.
  These include company separation, company-admin ownership, mechanic/provider
  execution, evidence, null/stale revision denial, stable retries, failed
  approval rollback and exact-plan advancement.
- `scripts/verify.cmd -BaseRef main` passed: clean analysis, 337 passing tests,
  204 existing skipped walkthrough checks. The 14 focused maintenance tests
  cover costs, uncertain create/report retries, capability/role controls and
  photo removal without mutating previously saved input.
- Rendered seven production widgets in English at 390px and Spanish at 320px
  with 1.5x text. Inspected the screens and lower form/report content; shortened
  labels and corrected photo selection and scrolling interactions.
- The implicit checklist-to-service completion helper and its obsolete tests
  were removed. The replacement requires explicit plan linkage and a server
  approval transaction; see decision 0005.

Internal build: `1.3.0+8`. Local evidence is under `outputs/NOW-006-*` and
`outputs/screenshots/maintenance-*`. Hosted activation and physical-device
workflow review are still pending; no new migration has been deployed in this
build task. Connectivity is required for server saves; the separate durable
offline workflow remains item 7.

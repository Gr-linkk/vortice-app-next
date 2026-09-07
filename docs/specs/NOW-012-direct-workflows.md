# NOW-012: Direct workflows

## Requested outcome

Fewer competing buttons, with labels that explain which workflow opens next.
A reported fault leads to one managed work order for planning and execution.
The existing navy visual language and English/Spanish support are retained.

Integration base: shipped Build 13 (`9f5e3e6`, `1.6.0+13`). Preserve its custody,
inspection, private evidence, offline queue, notification and recovery work.
This slice is internal `1.6.1+14`; the earlier Build 11-based local packages are
superseded and must not be delivered.

## Scope and rules

- Managers create a managed repair with fault/asset/urgency prefilled, or link an
  existing open managed job on the same asset. Creation and linking are atomic,
  scoped and retry-safe. A fault cannot silently switch to another work order.
- Faults show the linked job's status and assignee. Job progress updates active
  linked faults; job approval requests fault verification. It never resolves a
  fault or returns an asset to service automatically.
- The fault screen exposes one primary next step, an open-work-order link where
  useful, and a secondary actions menu. Legacy independent repairs remain
  reviewable; historic provider work orders retain their existing access rules.
- Job details lead into the report workflow. Labour and parts controls belong
  with their records. Review decisions sit with the saved report. Assignment,
  blocking, reopening and follow-up actions are grouped and clearly named.
- Operators can follow fault progress without receiving private job access.
  Company capability checks remain enforced by the server.
- Planning/linking and manager decisions require connectivity. Existing field
  execution keeps its account-owned queue under decision 0008. Uncertain
  create/link retries preserve the exact payload and operation ID; cancellation
  does not create or link anything.

## Verification and audit

Cover company/provider role boundaries, same-asset linking, stale revisions,
duplicate retries, lifecycle propagation and explicit resolution in SQL tests.
Exercise native create/link/navigation/menu/review interactions and render
English and narrow Spanish large-text views. Run the guarded project checks.
Audit faults, jobs, asset entry points, reports, requests and fleet decisions.
Record source-only findings separately from rendered/interaction evidence.

Hosted activation of the new migration is a separate reviewable step. No
production release, original-app changes or unrelated feature expansion.

## Implemented simplifications

- Fault: **Plan repair** opens creation or existing-order selection. Once linked,
  **Open work order** replaces parallel assignment/start/submit controls.
  **Verify & resolve** becomes primary after job approval, followed by **Review
  asset availability**. Less frequent fault decisions remain under More actions.
- New jobs lead with **Assign work order**, assigned jobs with **Start work**,
  and ongoing repairs with **Continue repair report**. Submitted jobs show the
  saved report before approval/return. Assignment changes, blocking, reopening
  and follow-ups are in More actions. Labour/parts controls sit with their data.
- History and discussion are compact secondary links below the main action on
  the fault and managed-job screens.
- Provider service requests say **Create work order**, replacing **Accept + WO**.
  The existing prefilled request conversion remains intact. Decline is secondary.

Durable linking and lifecycle rules: `../decisions/0009-fault-work-order-workflow.md`.

## Adjacent workflow audit

| Area | Finding | Outcome |
| --- | --- | --- |
| Faults | Assignment/start/progress controls duplicated job execution; company managers lacked the linked-job entry | Connected and simplified; native interactions and SQL contracts exercised |
| Managed jobs | Assignment, reporting, parts, blocking and follow-up competed in one action group | State-based primary action and contextual controls implemented; native interactions exercised |
| Service requests | Accept + WO did not explain that a creation form would open | Clear Create work order label and secondary decline; English/Spanish route/form-draft handoff exercised |
| Reports | Save draft and Submit for review already express different outcomes | Retained; report entry and existing retry tests exercised |
| Asset maintenance | View work, New repair and Edit asset share a button group; history can precede operational work | Implemented in Build 15: View work leads, Edit asset is in More actions, support links follow; native and connected asset-to-work navigation checked |
| Legacy provider work orders | Complete can redirect to report creation when the report is missing | Implemented in Build 15: Continue service report until completion is available; connected reporting, completion and billing passed |
| Work navigation | Internal maintenance and legacy billed service orders remain separate destinations | Implemented in Build 15: one scoped Work list for staff, clear source labels and original detail routes; company access remains unchanged |
| Fleet decisions | Indicators already open filtered underlying records | Retained; source route review found no additional competing-action change needed |

This is a targeted workflow audit, not a new live-data end-to-end audit of every
feature. The remaining source-review suggestions are intake under this document,
and were subsequently approved for implementation in the continuation below.

## Approved audit continuation — Build 15

Garrett requested the remaining simplifications, then connected E2E testing.
Internal `1.6.2+15` keeps the existing design and deployed backend contracts:

- Asset maintenance leads with View work. New repair is secondary; Edit asset
  is in More actions. Custody/inspections and history remain available below.
- In-progress provider orders lead into Continue service report until a saved
  submitted report allows completion. Loading/error states cannot complete a job;
  report errors expose a retry. The duplicate empty-report card is removed.
- Work combines managed maintenance and provider service orders for provider
  staff, with clear source labels, shared search/status filters and asset scope.
  Each entry opens its original detail workflow. Company roles retain managed
  work only, since provider-order detail routes are not authorized for them.
  Existing role and billing rules, assigned-contributor filtering, account-owned
  caches and manager/field mutations are unchanged. Source failures remain visible
  instead of presenting an incomplete list as complete.
- Connected acceptance uses production Flutter screens and the real Next backend:
  fault-to-repair/report/approval/verification, scoped work discovery and provider
  request-to-report-to-invoice. Exact synthetic fixture manifests drive cleanup.

This continuation requires no additional migration. Physical Android acceptance
remains distinct from the native Flutter test-host journeys.

Connected testing found that report submission could be attempted while labour
was running, producing a server-rejected queued change. Build 15 disables that
submission and provides Open labour timer with a retained draft. The connected
journey proves draft text survives returning, pausing the timer and reopening the
report before successful submission. The server's timer rule is unchanged.

## Verification result — 2026-09-06

- Integrated on shipped Build 13 commit `9f5e3e6`, preserving custody, private
  evidence, account-owned field queues, notifications and account recovery.
- `scripts/verify.cmd -BaseRef 9f5e3e6` passed: identity/guardrails, generation,
  analysis with no issues, and 418 passing tests (204 existing skips).
- All 11 local SQL suites passed against the complete migration chain, including
  direct fault workflows, field actions, custody, privacy and push contracts.
- All 11 focused native workflow tests passed with real fonts; rendered English
  and narrow Spanish large-text screens were inspected. Images are in ignored
  `outputs/screenshots/direct-workflows14/`.
- The linked Next deployment dry-run shows exactly one pending migration:
  `20260906183000_direct_fault_workflows.sql`. This preview preceded the approved
  hosted activation recorded below.
- Internal ARM64 Build 14 (`1.6.1+14`) built successfully. APK package identity,
  matching Next signing certificate, dedicated Firebase identifiers, messaging
  service and password-recovery link were checked. Build evidence is in ignored
  `outputs/NOW-012-build-notes.md`.
- No new physical-device or hosted end-to-end verification is claimed. Build 14
  has not been installed or transferred to the phone by this task.

## Hosted activation — 2026-09-06

After Garrett's explicit approval, applied only
`20260906183000_direct_fault_workflows.sql` to verified Next project
`hkjpojobdbbtjkhaudki` using the guarded deployment helper. Hosted
`direct_fault_workflows`, `company_maintenance`, `faults_and_availability` and
`field_maintenance_actions` suites passed with fixture transactions rolled back.
The final deployment dry-run reports the remote database is up to date.
Build 14 installation and physical-device end-to-end verification remain pending.

## Build 15 verification — 2026-09-06

- Guarded verification passed: generation, clean analysis and **428 passing
  tests with 204 existing skips**. The focused native suite passed all 37 tests,
  including the ten new discovery/report/timer cases; final real-font screenshots
  are in ignored `outputs/screenshots/direct-workflows15/`.
- **15 connected saved-workflow steps passed with zero issues**: six direct
  fault/repair steps and nine provider request/report/billing/isolation steps.
  Real Next persistence and production router/screens were used. Initial harness
  account ownership and abandoned synthetic timer issues were corrected before
  the clean run; the report/timer UX defect was fixed and retested as above.
- Cleanup removed the final two synthetic assets and their dependent records;
  earlier failed-attempt fixtures were also removed. The final manifest found no
  remaining fixture records and preserved unrelated counts: five assets, 21 work
  orders, five requests, five invoices and four operator runs.
- Internal ARM64 `1.6.2+15` built and passed package/version/signature checks,
  including retained dedicated Firebase identifiers and messaging/recovery
  declarations. Artifact and SHA-256 are in `outputs/NOW-012-build15-notes.md`.
- No additional backend migration was required. No physical phone installation,
  camera/keyboard/background/notification acceptance is claimed for Build 15.

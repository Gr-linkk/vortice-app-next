# NOW-010 whole-app workflow audit

Date: 2026-09-06. Baseline: Build 12, `4084d19`.
Branch: `codex/now-010-full-app-audit`.
Target: isolated Vortice Next, `hkjpojobdbbtjkhaudki` only.

## Result

The broad route audit and the selected connected business journeys pass after
the fixes below. This is **not a clean bill of health**: public request photos,
unscoped offline work-order data, and the inherited operator checklist submission
limitations remain open. Do not describe this audit as exhaustive physical-device
E2E coverage or as closing those findings.

## Confirmed defects repaired in this branch

| Finding | Before | Change and verification |
| --- | --- | --- |
| P1: private data retained across account changes | After owner data was loaded, another company could see cached invoice and asset/work details even though fresh server queries denied those rows. | Invoice list/detail, asset list/detail/assigned profiles, engine list/detail and work detail/context providers now depend on the current profile. Connected same-container account switching passes; a focused invoice regression reproduced the old behavior and passed with the fix. This does not fix the separate disk-cache finding below. |
| P1: logged provider labour omitted from invoices | A technician logged two hours through the real job UI; invoice generation produced zero because assignment rows existed with null hours. | Invoice generation uses the work-order hours when no technician assignment has an explicit hours value. Explicit assignment values, including zero, retain their meaning. The connected request-to-invoice journey now produces two hours. |
| P2: invalid invoice values persisted | Entering negative labour saved negative invoice amounts. | Screen and service reject negative and nonfinite values before saving; the screen also rejects malformed input and keeps the form. Connected negative-value rejection preserves saved amounts; focused service tests cover negative/NaN/infinite values. |
| P2: success followed by navigation exception | Direct-entry service report submission and job completion saved successfully, then threw `GoError: There is nothing to pop`. | Submission/completion now pop only when a route is available, otherwise navigate to the relevant work page. The same guard covers work-order creation. Direct-entry connected workflows pass. |

Invoice editing also now sends an empty notes value when notes are cleared and
shows a save error instead of failing silently. These two small corrections
were identified by code inspection; the connected test proves valid/invalid
amount editing, not a separately injected notes or save-error scenario.

## Open findings and follow-up priority

1. **P1 — Service-request evidence is public.** The live request-photo bucket
   permits anonymous retrieval. A single synthetic PNG was uploaded through the
   existing company account and downloaded without an API key or session: HTTP
   200 with identical bytes. The baseline marks `service-request-photos` public,
   its read policy is broad, and the app stores public URLs. Follow-up requires
   scoped object policies, a private bucket, authorized image loading and a
   compatibility plan for existing URLs. No storage policy was deployed in this
   audit. Evidence: `outputs/NOW-010-request-photo-privacy.json`.
2. **P1 — Offline work-order cache lacks account ownership.** A deterministic
   probe inserted Company A data into a disposable local database, removed any
   authenticated user and simulated a failed network request. The production
   repository returned both the cached list and direct detail. This proves the
   repository fallback is unscoped; it is not a claim that the signed-out router
   exposes a screen. Signing into another account does not partition that
   database. Follow-up must scope cached reads/writes to account identity and
   define safe handling of pending local work across account changes. The asset
   fallback has a similar unscoped structure and needs coverage in that work.
   Evidence: `outputs/NOW-010-offline-privacy.json` and its log.
3. **P2 — Operator checklist completion still has partial-write/retry gaps.**
   Current code creates a run, writes responses, then records history in separate
   requests. Failure between them can leave incomplete records; retries lack a
   single stable server transaction. Daily checklist photos are deliberately
   rejected while preserving the draft. These were already documented in
   NOW-008 and remain present in the current code; this audit did not repeat a
   hosted mid-request disconnect or implement the missing photo transport.

These are the next repair priorities, not claims that the untested areas below
are otherwise correct. A passing local suite does not close a live privacy
finding or a missing device test.

## Coverage actually executed

| Area | Evidence and depth |
| --- | --- |
| Role navigation and discovery | 122 route visits across owner, provider technician, company manager, company mechanic, operator and another company account. Production router and screens; no detected error text, Flutter exception or stuck circular loader. Includes dashboards, assets, work, requests, reports, parts, invoices, team/invites, history, fleet, assurance and telemetry read/gated states. Requested and actual routes are both recorded. |
| Client request to provider billing | Nine connected steps: required asset validation, asset creation, component and 1250.5-hour meter persistence, service request validation/save, provider acceptance and assignment, technician start/two-hour log/report, completion and generated invoice, valid invoice edit, negative rejection, and account isolation. Saved database results checked. |
| Company maintenance and operations | Nine connected steps: assigned job creation, labour start/pause/block/resume, parts quantity/cost, report draft/reopen, submit/return/correct/approve, operator fault reporting, acknowledge/assign/start/progress/review/resolve/reopen/dismiss, required-reason availability change, handover/acknowledgement and asset history. Saved results checked after transitions. |
| Custody and inspection renewals | Real feature screens against hosted data: custody transfer/reopen, inspection registration, evidence upload with byte comparison, manager return, correction/resubmission, approval, second renewal preserving old evidence, operator read-only controls and other-company row/direct-link/media denial. |
| Database contracts | All six hosted rollback-only suites pass: company maintenance, custody inspections, faults/availability, fleet coordination, provider reports and signup role boundaries. |
| Local regressions | `scripts/verify.cmd` completed generation, clean analysis and **390 passing tests, 204 existing skips**, including the two new invoice regression tests. The log ends with `Project verification passed.` |

The route sweep is navigation/read coverage, not a saved workflow for every
destination. In particular, this run does **not** claim connected create/edit/
delete coverage of every legacy checklist template, service plan, invitation,
team administration option, catalog part or telemetry device. The focused
contract/unit tests supplement those screens; they do not replace device E2E.

## Host substitutions and limits

- Flutter native test host with production widgets, routing, real authentication
  and real Next database/Storage. Router journeys use an in-memory local database
  and disposable preferences. Account switching intentionally reuses one provider
  container to exercise stale state.
- Phone-sized router view: 390 by 844 logical pixels. Roboto/MaterialIcons are
  explicitly loaded because test-only Ahem produced false overflow reports.
  Those reports disappeared with the corrected font setup; no speculative layout
  fixes were made. The final operations-history screenshot was visually inspected.
- The custody photo picker supplies a synthetic local image; network upload,
  stored bytes and access denial are real. Camera capture and permissions are not.
- No physical Android install/interaction, keyboard/insets, background recovery,
  OS share recipient, signature gesture, push delivery, telemetry collector or
  real hardware pairing was exercised. English connected journeys do not prove
  every Spanish layout or large-text setting.
- Existing skipped tests must remain visible in reported counts. External email
  delivery and signup confirmation were not exercised by creating real users.

## Evidence, cleanup and reruns

Reusable tests and instructions: `tool/e2e/README.md`. Connected tests require
explicit opt-in and are outside the default local test directory.

Local ignored evidence:

- `outputs/NOW-010-routes.json` and route log.
- `outputs/NOW-010-journeys.json` / `.log` (9 steps, zero issues).
- `outputs/NOW-010-operations.json` / `.log` (9 steps, zero issues).
- `outputs/NOW-010-custody.log` and custody manifest (passed).
- `outputs/NOW-010-hosted-contracts.log` and `outputs/NOW-010-verification.log`.
- `outputs/screenshots/audit010/` (earlier failure images are diagnostic artifacts,
  not evidence that the final run still fails).
- Privacy probes and exact cleanup manifest described above.

Cleanup removed **12 exact E2E-010 assets and four synthetic Storage objects**,
including dependent requests, jobs, invoices, reports, faults and inspection
evidence. Final queries found no fixture assets/jobs/requests/objects. Unrelated
counts remained: five assets, 21 work orders, five requests, five invoices,
zero inspections and zero coordination posts. No accounts were created. The
cleanup transaction removes child history sources before deleting their assets,
so history triggers cannot reference an already-deleted parent.

Garrett subsequently authorized committing and pushing these fixes and building
the recommended reliability, privacy, notification and account-recovery work.
The audit fixes are preserved on the audit branch before that next slice. The
audit itself does not create a new APK, merge main, deploy schema changes or
modify the original Vortice repository or services.

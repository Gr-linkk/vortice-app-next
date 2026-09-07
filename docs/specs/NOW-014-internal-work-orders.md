# NOW-014: Company internal work orders

## Outcome

Garrett approved aligning each client's internal work-order experience with the
owner's work orders after reviewing Build 16. The existing navy UI and planning
remain. Work orders cover preventive maintenance, repairs, inspections and general
work. Client managers create and prepare orders for their own assets and team;
mechanics record labour, parts, findings and work performed; managers approve.

## Connected slice

- Replace repair-only entry language with work orders across asset, list,
  creation, planning, detail and reporting. Keep a fault's repair context explicit.
- Share work-type values and labels with provider work orders. Allow preventive
  work without a recurring plan; a linked plan fixes the type to preventive.
- Creation includes asset/component, type, title, instructions, optional existing
  checklist, expected materials, assignee, priority, deadline and internal cost.
- Managers can revise the scope of a draft/assigned internal order before work
  starts. Preserve the selected asset, plan and checklist snapshot. Checked
  revisions and stable operation identities protect edits and retries.
- Details, discovery and planning show the work type. General/inspection reports
  ask for findings and work performed instead of assuming a failed machine.
- Preserve company/role/capability isolation, existing report drafts and field
  queues, component-specific approval, fault verification and provider billing.

## Data and access

Extend the existing work-order type vocabulary, with matching Dart decoding.
Keep the existing work-order/report/labour/parts records and checked internal
mutation path. Store expected materials with internal work-order metadata.
New creation defaults to general work; omitted type in an older caller retains
its existing repair/preventive behavior. Managers edit online; pending field
operations must be synced/resolved first. Internal orders do not create invoices.

This slice does not add customer billing to client accounts, change company
membership, add multi-mechanic scheduling, or replace service intervals.

## Acceptance

Exercise every work type, checklist/plan linkage, editing/replay/stale revisions,
company A manager -> mechanic report -> approval, company B denial, and original
provider/service-plan regressions. Inspect native English/Spanish narrow screens.
Run guarded Flutter verification and all SQL suites; activate only on Next,
run connected tests with exact removable fixtures, and package Build 17.

## Evidence

The guarded deployment activated only `20260907050000_internal_work_orders.sql`
on Next (`hkjpojobdbbtjkhaudki`). All 13 isolated SQL suites and all 13 hosted
rollback suites pass. The local bootstrap was not executed on hosted Supabase.

The connected native test passed six steps: client creation with its component,
assignee and materials; scope editing and type discovery in Planning; preventive
work without a recurring plan plus repair creation; mechanic inspection/report;
manager approval; and other-company read/edit denial. The existing seven-step
service-plan -> booking/conflict/rescheduling -> mechanic -> approval journey
also passes. Both exact marked assets were removed with unrelated counts
preserved. Evidence: `outputs/NOW-010-internal014.json`,
`outputs/NOW-010-planning013.json`, `outputs/NOW-014-connected.log` and
`outputs/NOW-014-planning.log`.

Seventy focused Flutter checks pass, including shared type JSON/draft decoding,
client inspection/checklist creation, plan linkage, pre-work edit gating,
same-input retry and stale revision behavior. Native English and Spanish
large-text screens were rendered with real fonts; inspected asset, creation and
detail views. Fresh settled report captures confirm populated field labels and
the approval footer; the narrow Spanish creation header fits at 1.35 text scale.
Retained captures: `outputs/screenshots/internal17/` and
`outputs/screenshots/audit010/internal014-*`.

Direct review followed creation, checked editing, read payloads, field-queue
guards, approval and provider decoding. The report's existing storage keys stay
compatible with saved drafts and queued field submissions; the visible labels
describe findings and work performed. Scope editing preserves its previous
values in an immutable event, and cannot change the asset, service plan or
checklist snapshot. No physical installation or phone workflow validation is
claimed by these native-host tests.

Final guarded verification passed with clean static analysis and 458 Flutter
tests (204 existing skips), recorded in `outputs/NOW-014-verify.log`. A final
Next-only migration preview reports the remote database is up to date.

Build 17 (`1.8.0+17`) is retained at
`outputs/builds/vortice-next-android-debug-20260907-011930.apk`, SHA-256
`8743ccbc9e68ad83b38c8332b36d5a80a1ac69e0757d8c909630454bc7b0d134`.
The retained copy matches the build output. APK inspection confirms
`com.example.vortice_app_next`, ARM64, the existing Next signing certificate,
dedicated Next Firebase identifiers, and messaging/recovery declarations.
The build retains the existing nonfatal Kotlin plugin migration warning for
`share_plus` and `shared_preferences_android`. This APK has not been transferred
or installed on the phone as part of this slice.

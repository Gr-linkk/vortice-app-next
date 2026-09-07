# NOW-015: Checklist builder and complete execution workflows

## Status

Garrett approved implementation after the checklist investigation. The native
builder and connected PM/pre-operation paths are implemented and pass connected
acceptance and guarded verification. Build 18 (`1.9.0+18`) is packaged and verified. The three
Next migrations are active and all 14 local and hosted SQL suites pass. Audit base: `2d14395`.
Existing visual language and service isolation apply. Decision 0012 records the
accepted publication, authorship and execution rules.

## Investigation baseline and gaps addressed

- `checklist_templates` and `checklist_items` support PM and `operator_daily`,
  asset type, ordered instructions, Spanish text, categories and required photos.
  There is no native authoring/publishing UI. The org admin checklist tab assigns
  existing templates; it is not a builder.
- Baseline template policies give the owner write access and other roles broad
  type-based reads. Templates have no company ownership boundary. Client
  authoring requires database isolation, not just another screen.
- PM selection feeds provider work orders and internal maintenance plans/jobs.
  Internal jobs copy items into `maintenance_job_records`; provider work uses
  a separate snapshot repository. Preserve both execution paths.
- Operator submission is atomic and validates answers, notes, photos, asset
  type and template version. Accepted results include a saved snapshot. Existing
  field operations have account-scoped durable queues and retry identities.
- The operator selector falls back to all templates if no operator template
  exists and does not consistently filter active templates for the asset. An
  unavailable checklist needs an empty state, never a PM fallback.
- The operator dashboard marks assignments in progress and passes asset/template
  IDs to the runner, but no assignment ID. Submission cannot close the assignment;
  `ChecklistAssignmentController.markComplete` has no app caller. Completion must
  be tied to an accepted run, including retries and offline sync.
- Flagged operator answers require notes and remain in history; the checked
  submission does not create a linked fault/follow-up. Connect manager review
  to the existing fault and internal work-order workflow.
- Mutable versions can cause a changed template to reject queued pre-op work.
  Published versions must remain addressable and immutable. Retirement prevents
  new starts while retaining history and supporting already-started work.
- Older PM code filters instructions containing `signature` or `sign-off`. A
  builder must not silently hide authored steps. Replace this heuristic with
  explicit supported item types; approvals remain workflow actions.

## Accepted product rules

The owner publishes shared starters; client managers create
private company templates or copy a starter and customize it. Copies remain
independent with source/version attribution. This working default is included in
the approved implementation scope. Owner access to
client copies follows existing fleet access and never silently changes a client's
published procedure. Mechanics/operators execute the relevant published checks;
authoring belongs to managers under existing company and capability rules.

One Checklist library provides PM and Pre-operation filters. Builder flow:
purpose -> name/instructions -> asset type and optional asset/component scope ->
ordered sections/steps -> preview actual execution -> save draft -> publish.
Steps support instructions, guidance, pass/fail/not applicable, numeric readings
with units/limits, text responses, critical flags and required evidence. Enforce
requirements on the server too. English or Spanish authoring should not require
a fabricated translation.

Published versions are immutable. Editing creates a draft version; publishing
selects the version for future starts. Copy and archive are explicit. Never
delete referenced versions or rewrite completed answers. Conflicting edits and
publishes require reload rather than silent overwrite.

## PM workflow

1. Owner/client manager builds, previews and publishes a PM procedure.
2. Manager attaches it to the appropriate component maintenance plan, or selects
   it for a one-off work order. Check purpose, asset and company compatibility.
3. Work-order creation freezes the procedure version and instructions.
4. Mechanic records results, readings, evidence, labour and report. Failures remain
   visible and lead to linked corrective work; required unresolved work cannot
   be silently signed off.
5. Manager reviews and approves under existing completion rules. Only approval
   of linked component service advances its interval. Standalone checks never
   infer service completion. History keeps the version and evidence.

## Pre-operation workflow

1. Manager publishes a pre-op and makes it available for matching equipment;
   optionally assigns a check to an operator with a due date.
2. Operator starts from the asset or assignment, with matching asset/procedure
   selected. Starting pins the published version; interrupted work resumes.
3. Operator records results/readings, notes and photos. Submission atomically
   saves run/history and completes the assignment. Offline work remains pending
   upload until accepted; retries have one effect. Keep an assignment/run link.
4. Failed/critical results produce visible linked manager follow-up, with a direct
   path to an existing/new fault and corrective work. Deduplicate retries.
   Critical results require review; they do not claim equipment is safe.
   Availability and return to service remain explicit manager decisions under
   the existing fault workflow.
5. Asset history and manager lists show version, author, findings, evidence and
   follow-up state. Corrective completion does not rewrite the original check.

## Implementation and acceptance

Use additive migrations for ownership, immutable publications, assignment/run
and follow-up links. Change RLS and every security-definer template reader
(maintenance context/create/plan and operator submit) together. Company templates
must not leak through selectors, caches, snapshots, direct IDs or provider routes.
Authoring/publishing is online; cached procedures and active execution retain
durable offline support. Exclude arbitrary scripting, conditional page builders,
AI/document import and automated compliance/return-to-service claims.

Acceptance uses owner and two independent client companies: draft/preview/publish/
copy/archive; cross-company read/edit/use denial; invalid publication rejection;
concurrent edits and exact retries; start version 1 while publishing version 2;
offline version-1 submission; PM plan -> work -> approval advances only its
component; pre-op assignment -> accepted result completes exactly once; critical
finding -> manager follow-up -> corrective work -> explicit verification; retained
history/photos. Inspect native EN/ES narrow/large-text views. Run full guarded
verification and SQL contracts, connected Next-only tests with fixture cleanup,
then package and separately verify phone delivery.

Audit verification: 54 existing checklist/operator/field-queue tests pass in
`outputs/checklist-builder-audit-tests.log`. This is baseline evidence, not proof
of the proposed builder or missing connections. No app/backend changes were made
during this investigation.

## Implementation and connected evidence (2026-09-07)

The Checklist library is available from More for managers. Authoring includes
draft/reload/retry, publishing, copying, archiving, preview and equipment/component
scope. Immutable publication IDs and frozen job snapshots preserve old work while
new starts use the latest publication. Authored instructions, including signature
wording, remain visible. Numeric/text rules and required evidence are validated
by the server as well as the app.

The direct review found and fixed a capability-read policy gap: company operators
could submit through the server but the native gate could not read their company's
enabled switches. Company members now read only their own switches and cannot
change them. The connected audit also corrected the operator header's Material
surface, readable history timestamps and Spanish history text. Older workflow
tests were updated for the accepted work-order labels and actions; the route
audit now uses the same account-isolated database model as the app.

Connected Next-only acceptance passes 54 workflow checks across eight suites:
6 builder, 6 direct fault/work-order, 4 field reliability, 6 internal work-order,
9 operations/handover, 7 planning, 9 provider/request/invoice, and 7 custody and
inspection checks. A separate audit passes 130 routes across six accounts with
no visible errors, loading failures or framework errors. Final per-suite evidence
is in `outputs/NOW-010-{builder015,direct012,field011,internal014,operations,
planning013,journeys,routes}.json`; custody evidence is in
`outputs/NOW-015-regression.log`. Retried affected suites are recorded in
`outputs/NOW-015-retry.log`, `outputs/NOW-015-operations.log` and
`outputs/NOW-015-connected.log`.
The consolidated final check summary is
`outputs/NOW-015-connected-verification.json`.

Builder tests cover exact lost-acknowledgement retry, scope predicates, reading
validation, real preview controls, SQLite v6-to-v7 cache preservation and frozen
rich definitions. EN/ES previews plus the Spanish library/editor/step validation
were inspected at 320px and 1.5 text scale. Screenshots are under
`outputs/screenshots/checklist-builder/` and `outputs/screenshots/audit010/`.

Full guarded verification passes: no analysis issues, 467 tests passed and 204
existing skips (`outputs/NOW-015-verify.log`). The new builder suite passes nine
tests. This includes actual large-text Spanish navigation and step validation,
not only static previews.

Cleanup removed 19 exact test assets, 18 fixture procedures and 59 media objects;
unrelated asset/work/history/template counts were preserved. The final migration
preview reports the hosted database up to date. Evidence:
`outputs/NOW-015-cleanup.log`, `outputs/NOW-010-cleanup.json`,
`outputs/NOW-015-sql.log`, and `outputs/NOW-015-hosted.log`.

Automated upload/download, restart and retry checks do not prove Android camera
permissions, physical installation, device network interruption or closed-app
push delivery. These remain physical-device checks.

## Build 18

Internal debug ARM64 APK: `outputs/builds/INSTALL-Vortice-Next-Build-18.apk`
(`1.9.0+18`, 103,516,845 bytes). Package `com.example.vortice_app_next`, displayed
version, dedicated Next Supabase/Firebase identifiers, existing Next signing
certificate, recovery links and messaging declarations are verified from the APK.
SHA-256: `255c64f4c0027fc2709520293df0cb3a25763b3a1f8c5aab557b5c23f7ff5393`.
See `outputs/NOW-015-build-verified.json`, `outputs/NOW-015-apk.txt` and
`outputs/NOW-015-signature.txt`. No Build 18 phone transfer or installation is
claimed by this evidence.

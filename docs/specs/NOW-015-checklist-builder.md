# NOW-015: Checklist builder and complete execution workflows

## Status

Garrett requested an investigation of checklists to prepare a builder for client
companies and the owner, covering PM and pre-operation checks, with the whole
workflow accounted for. This is the audited implementation scope, not a delivered
builder. Audit base: `2d14395`. Existing visual language and service isolation apply.

## Verified current implementation and gaps

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

## Proposed product rules

Working default: the owner publishes shared starters; client managers create
private company templates or copy a starter and customize it. Copies remain
independent with source/version attribution. The user was asked whether entirely
separate libraries are preferred; no answer is recorded yet. Owner access to
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

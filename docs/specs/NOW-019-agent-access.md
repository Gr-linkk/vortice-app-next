# NOW-019: Document-backed agent maintenance workflows

Authorized 2026-09-07. Implemented in the isolated `codex/now-019-agent-access`
worktree while equipment/UI and stress-test tasks use other checkouts.

## User workflow

Owners, clients and client admins select one fleet in More > Agent access.
Connections default to maintenance reads, with separate opt-ins for work-order
creation, document/maintenance drafts, and work management. Owners verify TOTP.
Keys are shown once, expire after seven days and can be disconnected in the app.

Scan pages with the camera, select photos, or import a PDF under Maintenance
documents. Review page order and legibility before saving. PDF pages are rendered
on-device; a vision-capable MCP agent reads the actual page images. Documents
remain private to the selected fleet. The app is not an embedded AI/OCR service.

The connected agent combines source pages with component hours, meter-log dates,
per-task plan baselines and approved service history. It can propose PM/pre-op
checklists and hour-based plan intervals with page references and source quotes.
A recorded zero does not prove new equipment; a missing baseline stays unknown.
The reviewer opens the source, edits the proposal, confirms current readings and
last-service hours, then publishes the checklist or activates the plan. Linked
checklist drafts must be published before plan activation. Existing plans retain
their own service baseline and use revision checks when edited.

With management permission the agent can edit unstarted managed work orders,
assign eligible people and schedule work. Existing role, capability, revision
and overlap checks remain in force. It cannot complete, sign, approve, invoice,
publish checklists, activate plans or change permissions.

## Boundaries and limits

- Hash-only opaque keys; live role, fleet, capability, owner-factor, expiry and
  revocation checks on every action. No user session or service key in MCP.
- Source pages are immutable after finalization. Drafts retain their source
  references through checklist editing. Quotes are unverified until reviewed;
  storing a quote does not prove that a model transcribed it accurately.
- Stable operation UUID plus exact payload prevents duplicate writes on retries.
  Account changes discard fetched information and pending UI operations.
- Reads and writes are bounded and audited. Ten live grants per user, 60 recorded
  actions/minute per key, 20 work-order drafts/day, and 100 extended workflow
  writes/day. Invalid-key traffic also needs hosted perimeter limits.
- Up to 30 pages/document, 5 MB/page, 500 document records/fleet. PDF input is
  limited to 20 MB and rendered imports to 40 MB. Split larger manuals into
  clearly titled sections; do not silently omit pages.
- Automatic due calculations remain hours-based. Calendar/mixed conditions need
  explicit review and separate follow-up; they are not converted into hours.
- Manual stdio connection keys are implemented. Remote HTTP MCP/OAuth is not.

## Verification and activation

Local SQL suites cover fleet isolation, source immutability, capability removal,
forged page/asset references, retries, assignment/revision/overlap checks, human
plan activation, changed meters and existing-plan baseline preservation. Node
checks cover MCP transport and the guarded image proxy. Widget checks exercise
account changes, upload recovery, source review and English/Spanish large text.
See the local report in `outputs/NOW-019-agent-access-report.md` for final counts.
Fixture screenshots do not prove native camera/PDF behavior or model accuracy.

Before release, integrate with the current Next base and rerun guarded checks.
The previously undeployed access migration was renamed to
`20260907170000_agent_access.sql` to avoid the catalog migration timestamp;
`20260907171000_agent_workflows.sql` follows it. Verify the linked project ref is
exactly `hkjpojobdbbtjkhaudki` and use `scripts/supabase-push.sh` for migrations.
Deploy `agent-document-page` to that same verified Next project with the checked-in
function configuration. It validates scoped keys through SQL before downloading
an exact private object using its server-only service credential. Configure
hosted request limits and include document Storage objects in backup planning.

Then build through the guarded Android helper. On a physical device test camera
permission/recovery, photos, text and scanned PDFs, page zoom/order, interrupted
uploads and account switching. With a trusted vision-capable MCP host test a real
manual, compare every proposed interval/checklist item to its source, verify
current hours and task-specific service history, edit and activate a plan, and
assign/schedule actual test work. Check replay and disconnect denial. Verify
hosted MFA, Storage RLS and Edge deployment. Keep real keys out of evidence.

This branch has not been merged, pushed, deployed or installed. Local validation
is not hosted or physical-device acceptance.

Local results on 2026-09-07: guarded verification passed with clean analysis,
533 Flutter tests and 204 existing skips. All 19 local SQL suites passed; the
extended existing-plan baseline/revision scenario was rerun successfully.
All 16 Node MCP/proxy tests passed. The concurrent retry/revocation harness
passed. Direct review and representative EN/ES 320px, 200% light/dark screenshots
were inspected; no independent reviewer or real manual/phone run was used.

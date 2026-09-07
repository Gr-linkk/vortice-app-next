# NOW-019: Document-backed agent maintenance workflows

Authorized 2026-09-07. Implemented in the isolated `codex/now-019-agent-access`
worktree while equipment/UI and stress-test tasks use other checkouts.

## User workflow

Owners, clients and client admins select one fleet in More > Agent workspace.
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

At the isolated checkpoint this branch had not been merged or deployed. Local validation
is not hosted or physical-device acceptance.

Local results on 2026-09-07: guarded verification passed with clean analysis,
533 Flutter tests and 204 existing skips. All 19 local SQL suites passed; the
extended existing-plan baseline/revision scenario was rerun successfully.
All 16 Node MCP/proxy tests passed. The concurrent retry/revocation harness
passed. Direct review and representative EN/ES 320px, 200% light/dark screenshots
were inspected; no independent reviewer or real manual/phone run was used.

## Integrated Build 23 (2026-09-07)

Garrett authorized merging all worktrees, fixing integration issues, activating
necessary services, and building/delivering the APK to his S24. The integration
branch `codex/integrated-agent-release` contains the field-reliability, Field Notes,
equipment catalog (including road vehicles), stress fixes, and agent branches.
No worktree was deleted and no original Vortice repository/service was used.

Added a paginated Plans to review list, separate from the bounded activity feed,
so unapplied proposals remain discoverable. It shows equipment and interval,
opens the existing source/plan editor and refreshes after returning. Live session
changes invalidate its actor-bound queries. Pagination and error retry are tested;
English/light and Spanish/dark 320px/200% renders were inspected.

Final guarded verification: clean analysis, 561 Flutter tests, zero skips. All
20 combined local SQL suites passed; both agent suites passed again after local
MFA fixtures were aligned with the hosted auth schema. Both rollback-only hosted
agent suites pass without retained fixture data. Sixteen Node tests and the
concurrent retry/revocation harness pass. The two agent migrations and document
proxy are deployed to Next. Live HTTP checks verify invalid-key denial through
both PostgREST and the Edge proxy.

Build 23 is version 1.12.0+23, ARM64 internal debug. Build and verification evidence
are under `outputs/integrated-*` and `outputs/agent23-*`. A real user's MFA setup,
valid-key document upload/read through a chosen MCP host, native camera/PDF and
manual interpretation remain physical/end-to-end acceptance checks. The app does
not automatically connect or enroll a third-party agent for the user.
Build 23 was delivered to the verified Samsung SM-S928W Downloads as
`INSTALL-Vortice-Next-Build-23.apk`. Local and final phone SHA-256 match:
`68047a461a956ba8bf93b759f6f483ecee930737834284698218fdd531b18648`.
APK identity, signing certificate, Next backend/Firebase, ARM64, notification/
recovery declarations and all 19 artwork files pass inspection. Evidence:
`outputs/build23-build-verified.json` and `outputs/agent23-phone-checksum.txt`.
Installation was not performed. All worktree branch tips are ancestors of the
integration branch; worktrees remain available. No remote push was performed.

## Evidence workspace refinement (2026-09-07)

Garrett requested building the proposed agent interface. Continue NOW-019 in the
accepted Field Notes design: a fleet-scoped workspace opens on pending reviews;
connection-key administration stays in Connections. Plan review presents the
current/proposed interval, component meter and date, task baseline, due arithmetic,
source quote/page and bounded approved service history. Other tasks' services
remain explicitly distinct and never become an inferred baseline. The same
evidence remains available while editing. Refresh, missing-source/history,
permission-loss, empty/loading/error and successful activation states must work
in English/Spanish, both themes, narrow screens and large text.

The only backend addition is an authenticated read-only review-context RPC using
existing live fleet/asset access checks. Plan publication/activation, capability,
revision, meter and retry rules stay authoritative. No embedded chat, automatic
agent enrollment or model-generated rationale is simulated. The interface shows
actual proposals and recorded evidence; calendar scheduling is still separate.

The refinement is packaged as Build 24, version 1.12.1+24. Navigation is More >
Agent workspace; connection administration remains under Connections. Native
phone/wide and English/Spanish light/dark renders are in
`outputs/agent-workspace-screens/`; inline source-page renders use a clearly
marked synthetic manual. Visual inspection corrected clipped large-text status
labels and added image decoding/error feedback. Service dates include the year.
The read-only review RPC is deployed to Next. Its hosted rollback-only contract
passes and the fixture cleanup check returns zero retained users/documents.
Build 24 verification: clean analysis, 571 Flutter tests, zero skips; all 20 local
SQL suites pass, including source/fleet restrictions and matching-vs-other-task
service evidence. The updated agent workflow contract also passes on hosted Next
with transaction rollback and zero retained fixture users/documents. Phone and
wide native render checks passed; source previews were inspected after decoding.
APK inspection confirms the Next package, expected signing certificate, ARM64,
backend/Firebase configuration, recovery/notification declarations and all artwork.

Build 24 was transferred to the S24 Downloads folder as
`INSTALL-Vortice-Next-Build-24.apk`; the device SHA-256 matches the inspected
local APK: `56f2ab776006351fa9fb6fc90df2ebe9b32ad7fe6e683c48c3149d4e3dba36b0`.
It was not installed. Physical acceptance with a real manual, external agent,
source-page loading and plan review/save remains outstanding.

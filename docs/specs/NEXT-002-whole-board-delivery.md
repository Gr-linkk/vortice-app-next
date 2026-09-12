# NEXT-002 — Whole-board delivery

Status: implemented scope delivered as internal Build 29 (`1.16.0+29`),
September 12, 2026. External setup and physical acceptance remain open below.
The independent branch is `codex/kanban-workflows`. The APK is in S24 Downloads
and its checksum matches the inspected local artifact. Installation and human
phone acceptance have not been performed by this delivery.

## Scope

The board now joins work discovery, asset context, automatic maintenance and
inspection cycles, frozen checklist procedures, original meter units, parts,
reports, discussions and company membership. Fleet decisions and Fleet
inspections are no longer competing More destinations. Existing deep links
remain reachable for history and notifications.

The work hub distinguishes booking dates from due dates and assignments. Its
counts and Home links use the same scoped filters. Assets provide current work,
inspection state/history, readings and maintenance setup without reselecting
the asset. Six deliberately selected land-equipment types are bundled with
distinct Field Notes drawings and searchable Add/Edit choices.

Organization membership is additive: Company Owner, Supervisor, Mechanic and
Operator may be combined, with explicit delegated permissions. Invites,
revocation, company switching and customer/provider relationships are checked
on the server. Existing identities, the Ellicott graph and legacy access remain
preserved. No account reset or record deletion was performed.

The final provider execution adapter retains canonical work/report IDs and
the publication boundary while adding the same checklist, procedure, evidence,
meter and labour requirements used by the work journey. Provider inventory
belongs to the provider company, separate from customer stock and legacy stock.

Offline readiness refreshes during normal connected foreground use. The read
cache and outbox remain account-owned, and permission changes invalidate stale
reads. Assigned retired checklist versions and their exact procedure pages
remain available for their authorized work. Local saves are not described as
server submissions or approvals.

## Verification record

Focused SQL and Flutter checks have verified recurrence replay, explicit meter
units, frozen procedures, company boundaries, asset/component rollback and
retry, catalog stability, native navigation and permissions. The real SDK
restart test closes the HTTP server and reopens SQLite/preferences, retaining
cached Assets/work/procedure pages and drafts while testing account isolation
and denied-access invalidation. These are automated checks, not phone evidence.

The guarded code generation, analysis and full Flutter suite passed: **718
tests**, including the real SDK/SQLite offline restart. All five focused
provider tests passed; eight native screenshots were inspected at 320 px,
Spanish, 200% text in both themes. The five new demo identities passed real
password sign-in and switching through the app, including customer-fleet
isolation and the original 62,000 km meter. The personal-agent suite passed
15 tests covering protocol and checked backend calls.

The connected legacy audit exposed a real hub timeout that unit fixtures did
not reveal. A parameterized database plan scanned the same 147 work rows once
for each of 34 assets. The query now materializes visibility and shared asset
permissions once. A rollback comparison preserved exact JSON and function
grants for five roles: the owner hub fell from 3,189 ms to 181 ms, and the modern
company owner from 7,183 ms to 46 ms. These are database timings from that
comparison, separate from end-to-end network/UI measurements.

All **45 SQL contracts** passed across the local full run and focused reruns,
and all 45 passed on hosted Next. The 24 migrations through
`20260912233500_work_hub_visibility_cache.sql` are deployed only to
`hkjpojobdbbtjkhaudki`; its hourly recurrence job is active. The final connected
audit passed **114 routes across six existing roles**, with no error text,
framework error or hidden provider failure. After deployment, authenticated
REST hub loads measured 0.738 s for the existing owner and 0.287 s for the new
company owner.

Source commit: `a7109a5` on `codex/kanban-workflows`. Final local evidence:

- `outputs/kanban/final-verify.log`: generation, clean analysis, 718 tests.
- `outputs/kanban/hosted-contracts-final.json`: 45 passing contract files/hashes.
- `outputs/kanban/hub-candidate-comparison.json`: exact five-role responses and
  access properties, with before/after timing.
- `outputs/kanban-live-Vuyiw23r/`: final connected legacy route audit.
- `outputs/modern-connected-LcFWJJJ9/`: five modern role/picker checks.
- `outputs/kanban/provider-ui/`: inspected native provider screenshots.

Earlier logs include failed attempts; they are not the final release result.

## Build 29 delivery

- APK: `outputs/builds/INSTALL-Vortice-Next-Build-29.apk`.
- Version/package: `1.16.0+29`, `com.example.vortice_app_next`, ARM64 internal debug.
- Size: 139,024,493 bytes.
- SHA-256: `1f253324d8ca5023a71fb7e68f0372415104c5a2f2f363a3d0b3288272a4029b`.
- S24 model/destination: `SM-S928W`, `/storage/emulated/0/Download/INSTALL-Vortice-Next-Build-29.apk`.
- Device checksum verified: `2026-09-12T10:47:15.846769+00:00`.
- Next backend, dedicated Firebase project, signing certificate, notification
  service, recovery deep link and bundled equipment artwork were inspected.
- Receipts: `outputs/build29-build-verified.json` and
  `outputs/build29-phone-delivery.json`.

Open the APK from **My Files → Downloads** to install the update. Then use
**More → Switch test account → Demo fleet owner** (or the supervisor,
mechanic, operator or service-company demo) for the checks below. Existing
accounts remain available. Keep existing app data so draft recovery can be tested.


## Explicit remaining boundaries

- Garrett deferred email and SMS provider setup. Code entry and onboarding are
  implemented, but this internal build explains that code sign-in is unavailable
  and retains password/test-account entry. See `NEXT-002-code-sign-in-setup.md`.
- Personal-agent tooling has local protocol and authorization tests; a real
  user-selected Codex/OpenClaw/other host connection remains to be exercised.
- Managed-agent exploration produced a working local budget/dispatcher spike
  with synthetic token envelopes. Actual model quality, latency and billed
  usage require an authorized API credential. No allowance or price was chosen;
  see `NEXT-002-managed-agent-exploration.md`.
- Physical Android installation, permissions, airplane-mode/process-kill/
  reconnect, evidence capture, notification delivery/taps and human workflow
  acceptance remain separate from automated verification and APK transfer.

## Phone acceptance checklist

September 12 follow-up: `NEXT-003-workflow-follow-through.md` records the later
Build 33 install and completed native S24 demo journey. It covers provider work
creation/assignment, checklist/report/photo recovery, review return/correction,
approved customer publication and an issued zero-dollar invoice. A fresh unsent
photo survived force-stop with Wi-Fi and mobile data disabled on Build 32;
the final form fix passed on Build 33. The customer could not see the report
before approval and could read the report, evidence and invoice afterward.
The checklist below remains the broader role/field acceptance reference;
unexercised recurrence, source-page, parts and notification cases remain open.

Use the new demo company entries in **More → Switch test account** after
installing the delivered build. Existing test accounts remain available too.

1. Owner/supervisor: create work from an asset, keep its context, schedule and
   assign it, open a record, and return to the same filter/calendar date.
2. Mechanic: start work and its timer, open a pinned procedure, retain answers,
   readings, notes and photos, pause/resume, and submit complete work for review.
3. Reviewer: return work with a comment, confirm the previous input remains,
   approve the correction and verify the next recurring target advances once.
4. Operator: choose among authorized assets, preserve multiple drafts, report a
   failed step with urgency/safe-operation information and follow the linked
   fault/discussion into work.
5. Company/provider: accept a request, perform assigned work, review/publish the
   report and issue the invoice with explicit billing permission. Verify that
   customer views omit private notes and internal costs.
6. Offline: use the app connected, enable airplane mode without preparation,
   force-close and reopen, open cached work/assets/source pages, record supported
   field work and photos, restart again, then reconnect and observe one upload.
7. Switch accounts and companies, exercise a revoked assignment, open long
   labels at enlarged text, and follow a closed-app notification to its subject.

Do not clear the app's data to test recovery; that destroys the local drafts
whose persistence is being checked.

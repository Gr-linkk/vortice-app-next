# NEXT-009: Production-readiness housekeeping

Authorized September 14, 2026. Base: `430f7a0`, internal Build 39 (`1.18.1+39`).
Branch: `codex/production-readiness-closeout`. BACKLOG.md owns priority.

September 24 update: Garrett selected Android Google Play and Canadian general
construction, including customer invoicing for Service provider and Both.
NEXT-011 and NEXT-012 now own these release blockers; this document retains
operating closeout and earlier verification evidence. The province, pilot,
identity and final offer remain open.

September 24 continuation: the independent Next debug key is recovered, Build 40
is installed in place, all 26 persisted files survived unchanged, and Home opens
with the retained session. NEXT-012 has the recovery receipt. Earlier mismatch
statements below describe the initial audit and are resolved. Google Play work
is deferred; continue app completion, then E2E and a final polish review.

## September 25 connected verification continuation

NEXT-011 now supplies native CAD billing and explicit CAD/USD cost snapshots;
its three migrations are deployed to the authorized Next project. The current
hosted operational check passes migration parity, RLS and private Storage. A
fresh backup verifies six database/access files and 78 objects, using the
checksum-verified user-local PostgreSQL 17.11 client. All 51 SQL contracts and a
populated local restore pass on that same major version. This remains local
plaintext staging, not encrypted off-device recovery or hosted restoration.

A separate internal E2E mechanic preserves the existing demo accounts' active
timers. Connected scripts use account-owned memory databases on Linux, current
visible control labels and exact manifest cleanup, including generated recurring
cycles. The native CAD connected job-to-customer workflow passes; further broad
workflow and French rendered evidence is being consolidated before delivery.

## Linux tooling and workflow audit — September 24, 2026

This audit continued `codex/canada-play-readiness` from `4310fa3` in
`/home/garrett/projects/vortice-app-next`, after reading the previous task,
PROJECT.md, BACKLOG.md, current scopes and company-purpose/access decisions.
The Documents checkout remains a reference copy. All repository checks found
only the independent `vortice-app-next` origin. GitHub CLI sign-in as `Gr-linkk`
and write permission to that repository now pass. Supabase CLI authentication
and a guarded management query against `hkjpojobdbbtjkhaudki` also pass.

### Tooling now usable

- Flutter 3.44.0/Dart 3.12.0, JDK 17, Android SDK 36, accepted SDK licences,
  ADB, native Flutter rendering and browser tooling pass `flutter doctor -v`.
- Installed checksum-verified official PowerShell 7.6.6 and Supabase CLI 2.117.0
  under the user's local tools directory. The existing guarded `verify.ps1`
  runs on this Linux machine; a second verification implementation is unnecessary.
- Docker is installed but this login cannot access its socket. Added an explicit
  native backend to `scripts/test-database.sh`, sharing the same migrations,
  contracts and restore checks as Docker. The user-local PostgreSQL 18.6 runner
  starts a fresh cluster with TCP disabled and a private Unix socket, and stops
  it on exit. CI retains Docker/PostgreSQL 17. Extra remote URLs are rejected;
  deliberately invalid external PG connection variables cannot redirect tests.
- The first Android build failed because migrated Flutter cache files still
  named `/mnt/c/...`. Moved `.dart_tool/flutter_build` into ignored
  `work/linux-migration-cache/` and regenerated it. The guarded Linux build passes.
- Recovered the four public Next Firebase client defines from the verified
  installed Build 39 APK. Exact project/app/sender IDs were checked before
  storing ignored `config/vortice-next-firebase.local.json`; values were not
  printed. Verified they are packaged in the rebuilt APK. This restores build
  configuration, not proof of notification receipt.
- The S24 is authorized over ADB. Its installed app is `1.18.1+39`, API 36.
  The new Linux debug certificate **does not match** the installed Next signer.
  No replacement, uninstall, data clearing or production signing was performed.
  Recover the old independent Next debug key before an in-place phone upgrade.
  Final production identity/signing is still a separate NEXT-012 decision.

Repeatable commands and tool locations are in `docs/DEVELOPMENT-WORKFLOW.md`.

### Ordinary workflow findings

Fresh connected renders used the existing Fleet owner, supervisor, mechanic,
operator and Service provider demo accounts. Each starts at Home and uses real
navigation to Assets, Work orders, Faults and More (operators use Checks), then
opens equipment, fault entry, company settings and the existing completed
customer job as applicable. Operator checks were opened without submitting.
The provider job shows its checklist, meter, labour, photos, report, internal
costs and issued invoice together. Opening a customer's equipment directly as a
provider remains denied; access through the authorized job is intentional.

| Workflow | What the current implementation supports | Remaining production proof or correction |
|---|---|---|
| New company and team | Purpose and organization permissions; owner, supervisor, mechanic and operator entry points | Fresh external signup/invite/recovery receipt and ordinary-user onboarding; prepared demo login is not that proof |
| Equipment setup/import | Own-equipment access for all company purposes; reviewed import and meter/component setup | Fixed Home's misleading "Contact Vórtice" dead end with a permission-aware Add asset action; physical Android picker/import acceptance remains |
| Equipment → work → calendar | Existing asset context, checklists, assignment, schedule and separate own/customer focus | Current connected renders and local contracts pass; repeat creation/save/reopen on the eventual signed candidate |
| Execution → review → history | Labour, parts, evidence, return/correction, approval and recurrence contracts; existing completed provider job readable | Real camera, permissions, correction loop and recurrence acceptance on the final phone build |
| Operator → fault → corrective work | Checklist entry and explicit fault/repair/verification lifecycle | Fresh failed-check-to-repair physical journey; opening the form alone does not prove submission |
| Parts and internal cost | Reservations, receipts, consumption/returns and equipment reports have passing contracts | USD entry/reporting remains in `parts_readiness_screen.dart`, `maintenance_create_screen.dart` and `maintenance_job_screen.dart`; NEXT-011 needs a stored-currency contract, not relabelled historical amounts |
| Provider → customer invoice | Billing permission, private drafts, approved customer work and issued history | `organization_provider_work_panel.dart` still asks for USD/hour, USD parts and a single tax percentage; PDF/XLSX still hard-code the Mexico issuer. Native CAD, explicit tax lines, issuer/customer snapshots and export agreement remain release blockers |
| Fleet owner billing boundary | Local purpose migration and contracts pass | Hosted Next lacks migration `20260924100000`; this audit does not claim it is deployed. Fleet owners may still read invoices received for outside service; that differs from issuing customer invoices |
| Offline and account isolation | Current queue/restart/revocation tests and company/access contracts pass | Final Android process-kill/restart, unsent camera evidence and account-change acceptance; no phone data reset |
| Offboarding and Play | Production Release tasks are guarded; no account-deletion request implementation was found in app/function code | NEXT-012 must provide in-app/web deletion requests with a reviewed ownership/retention process, release identity and signed AAB. Garrett confirmed no Play Console account yet |

Visual inspection of the actual Add asset screen at 320 pixels/200% text also
found Manufacturer and Location reduced to "Man…" and "Lo…". Field pairs now
stack at narrow widths or enlarged text, including component fields. Normal
390-pixel layout keeps paired fields. The connected audit now taps Add asset
from Home, verifies the real form is on top, and scrolls to Location. Its route
receipt records the top pushed route separately from the underlying router URL.
No synthetic assets, jobs, invoices or messages were submitted by these rendered
journeys. This is a walkthrough and targeted correction, not a claim that every
saved workflow was repeated on a physical phone.

### Verification and remaining limits

Evidence is under ignored `outputs/next009-linux-audit/`:

- Full guarded verification: clean analysis and 790 passing Flutter tests
  (`verify-delivery.log`). Earlier baseline and first-fix logs are retained.
- All 64 migrations load; all 49 database contracts and populated archive restore
  pass (`database.log`). The restore checks frozen invoices, correction history
  and restored access rules; it does not restore hosted Auth/Storage/files.
- The 340-asset/1,500-job Work hub performance guard passes (`performance.log`).
  Ten operations-tool tests and three cleanup-option tests pass. The native runner
  also passes with deliberately conflicting external connection variables.
- Five-role connected walkthroughs pass at 390×844/100% and 320×844/200% text.
  Final screenshots/step receipts are in `asset-fix-normal/` and
  `asset-fix-large/`; every completed run has an empty issues list. Images were
  visually inspected. Existing test-host multiple-database diagnostics were
  retained, not suppressed. These account-isolated test databases are disposable.
- Physical Build 39: captured Home and navigated to the customer-work Month
  calendar; confirmed the obsolete empty-equipment instruction on the device.
  Later capture during account sign-in was outside the app and excluded from
  acceptance. No physical completion, camera, picker, offline restart or new
  build acceptance is claimed.
- Guarded Android build with restored Firebase defines passes. The local
  diagnostic artifact retains version `1.19.0+40` and placeholder package
  `com.example.vortice_app_next`; it is not a new delivered release. File:
  `outputs/builds/vortice-next-android-debug-20260924-203645.apk`, SHA-256
  `8998ce18081b0a056b0c5e7310945f8fd3d4af169df4119b41a76b3ba1ed123b`.
  Signer mismatch blocks an in-place S24 update; Firebase resources were checked,
  but no push was sent. The compiler's future Kotlin compatibility notice remains.
- Authenticated hosted operational snapshot: all public tables have RLS, all
  Storage buckets are private with file limits, 78 Storage objects, one enabled
  push device, 19 sent deliveries, no failed/overdue deliveries, and a recent
  successful push schedule. Migration parity correctly fails for the one pending
  purpose/billing migration. `hosted-operations.log` and
  `outputs/next009/operations.json` retain the receipt. No hosted schema deployment
  occurred; these aggregate counts do not prove phone notification receipt.

### How this changes the launch work

BACKLOG.md's order remains appropriate. Begin NEXT-011 with company currency and
issuer/tax configuration, then connect stored CAD costs, server-calculated frozen
invoices and exports; preserve historical USD/MXN documents. Continue the small
workflow fixes under NEXT-006 as evidence exposes them. NEXT-012 can advance its
release/deletion implementation alongside that work, while identity, signing and
Play account setup are settled. NEXT-009 still owns encrypted off-device recovery,
real delivery channels, support, commercial rights and pilot acceptance.

Do not count old APK deliveries as separate outstanding feature implementations
or start more feature expansion. The remaining human inputs are the old Next
debug key's location; final business/app identity and Play account registrant;
real issuer/tax review; email/domain and recipient; backup destination/custodian
and recovery budgets; support/privacy/retention and rights decisions; and an
actual pilot. Province remains configurable. Tool access now permits further
local implementation and guarded hosted inspection without repeated sign-in.

## Outcome and boundaries

Complete the independently verifiable housekeeping and leave Garrett one
actionable set of release decisions. Preserve the existing product and data.
No production release, paid service purchase, customer communication, account
reset, original-project operation or unapproved price activation is included.

The accepted product is an equipment-centered maintenance workspace for marine
and heavy/land equipment. Company owners maintain their own equipment; service
providers can also work on customer equipment in the same workspace. One Work
order connects planning, procedures, field evidence, review and history; provider
invoicing has separate permissions. Field Notes, saved work focus, checked
completion and company-isolated offline drafts remain core behavior.

The proposed first commercial approach is an assisted small-company pilot.
Android through Google Play and Canadian general construction were selected on
September 24. The actual pilot, pricing and support promises remain open.
The proposed C$99 founding /
C$149 standard subscription, five users and C$20 additional seats are unapproved
hypotheses. Free operator scope, storage allowance and taxes are unresolved.
Do not add billing restrictions or subscription automation during this closeout.
Hosted AI, telemetry expansion, iOS delivery and major redesign remain outside
the initial offer until separately selected and proven.

## Completed technical housekeeping

- Removed Android's release-to-debug signing fallback. Gradle refuses Release
  tasks until production identity/signing is deliberately implemented. Verified
  the actual Release task fails for that reason and the debug task graph passes.
- Added runtime and build-test validation of the exact Next URL and public-client
  key type. Rejects privileged/wrong-project JWTs, malformed keys and other hosts
  without printing keys. The existing private Next build configuration passes.
- Confirmed the test-account switcher already requires debug mode and the exact
  Next backend; existing widget tests cover hiding its entry points. No demo
  accounts or existing data were removed.
- Strengthened repository helpers to inspect all fetch/push URLs, ignore signer
  files anywhere in the checkout and scan tracked Python files for secret patterns.
- Added all database contracts and a populated archive restore to CI. The restore
  exercises frozen invoice/correction history and restored company/customer RLS.
- Added guarded one-shot aggregate operational reporting, local backup-export
  tooling with incomplete receipts/checksums, and resolved dependency licensing
  inventory. No scheduled monitor or third-party error collector is activated.
- Reconciled NEXT-001's automated invoice audit with current local/hosted evidence;
  consolidated external acceptance rather than treating every old build's pending
  line as a separate test request.
- Prepared the [operations/recovery runbook](../operations/PRODUCTION-RUNBOOK.md),
  [pilot onboarding/offer worksheet](../operations/CUSTOMER-PILOT.md) and
  [commercial/data-handling review packet](../operations/COMMERCIAL-REVIEW.md).

## Verification receipt — September 14, 2026

| Check | Actual result | Local evidence |
|---|---|---|
| Guarded Windows verification | Clean analysis; all 781 Flutter tests pass; command exit 0 | `outputs/next009/verify-final.log` |
| Full local DB suite | 48 contracts pass | `outputs/next009/database.log` |
| Populated PostgreSQL archive restore | Pass: original invoice snapshot, correction history, restored RLS and other-company/customer privacy | Same database log |
| Hosted rollback contracts | Eight pass: invoice_closeout, organization_memberships, organization_provider_execution, organization_provider_work, request_photo_privacy, signup_role_boundary, company_purpose, customer_work_creation | `outputs/next009/hosted-contracts.json` |
| Actual private build configuration | Pass; values not printed | `outputs/next009/backend-config.log` |
| Release refusal / debug task graph | Expected refusal / pass; no APK produced by this check | `outputs/next009/release-guard.log`, `debug-graph.log` |
| Operational tool safeguards | Ten offline tests pass for target checking, safe local object names, hashes, missing/corrupt files, changed inventory, private download/redirect refusal and real local Git remote/link guards | `outputs/next009/operations-tools-tests.log` |
| Work hub performance | Populated 340-asset/1,500-job role scopes and unrelated-company overhead pass the existing budgets | `outputs/next009/performance.log` |
| Live backup staging integrity | Six database/access-history files and all 78 Storage objects verified: 84 recorded files | `outputs/next009/backup-verification.json` |
| Guardrail/migration immutability | Pass against base `430f7a0` | Direct guarded command |

The hosted aggregate snapshot reports matching migration versions, no public
tables without RLS, no public buckets, no buckets missing file limits, one enabled
push device, 19 sent deliveries, no failed/overdue deliveries and no failed push
schedule runs in the preceding 24 hours. It inventories 78 Storage objects.
These are server observations, not proof of phone receipt or notification taps.
No migration deployment or customer message was performed during this closeout.

The first Windows log-redirection wrapper returned a shell error despite the
child verification passing; the final run above uses native cmd redirection and
returns 0. The initial restore-run ordering was corrected before the clean run.
The direct self-review covered the final code and tooling; it is not an
independent security assessment. Hosted rollback tests preserve live data.

Completed local backup: `outputs/backups/20260914T102246737585Z/manifest.json`.
It includes roles, app schema, data (including Auth users and Storage metadata),
migration-history schema/data, managed access-rule metadata and all 78 private
file objects. Every recorded file's size/hash passed the standalone verifier.
The CLI Storage copy process timed out; its validated database exports were
retained, and Storage capture was completed through the fixed-host authenticated
API with before/after inventory checks. The manifest records the resumed Storage
time. This is a staged, non-atomic export across services, not proof of an accepted
hosted restore. It is plaintext local material, not encrypted off-device retention.
Four superseded incomplete copies from this task remain under `outputs/backups/`.
Automatic approval review rejected their recursive deletion with "blocked by
policy" and provided no more specific reason. Their manifests remain incomplete;
use only the completed manifest named above. A small index is retained in
`outputs/next009/backup-attempts.json`.
The isolated database restore does not close hosted Auth/Storage/file recovery;
the selected recovery target, configuration/secrets and encrypted retention must
still be exercised before customer reliance. No full managed-system schema restore
or encryption-root-key recovery is claimed.

## Product/commercial findings that affect the next decision

1. NEXT-010 adds saved CAD alongside USD/MXN to customer-job screens and
   PDF/XLSX exports following Garrett's September 14 request. The older invoice
   service applies fixed IVA/consumables; the organization flow accepts explicit
   tax/charge inputs. Neither is a completed Canadian invoicing implementation.
   Subscription pricing is a different decision. Canada and provider invoicing
   are now selected; NEXT-011 owns the remaining currency/issuer/tax implementation.
   CAD valuation support itself is implemented.
2. Signature capture uses Syncfusion SignaturePad/core licensing. The generated
   inventory covers 156 resolved runtime-graph packages and 31 tracked assets,
   retaining package license texts and file hashes. Obtain applicable entitlement or select a replacement. The fork
   provenance document does not prove all inherited contribution/artwork rights.
3. Account-owned offline behavior has substantial automated and prior S24
   evidence; latest-build phone acceptance and the final signed-release upgrade
   remain distinct gates. Do not wipe app data to test recovery.
4. Current invoice/report exports are not a full company export/deletion service.
   Retention, offboarding and support-access procedures need selected policy and
   verified execution before being promised to customers.

## Garrett's next actions, in order

| # | What Garrett needs to supply/complete | Prepared next step |
|---|---|---|
| 1 | Canada/general construction and provider invoicing selected; choose the actual pilot and reviewed transaction/tax case | Complete NEXT-011's configurable Canadian billing before issuing customer invoices |
| 2 | Android/Google Play selected; choose final product/business name, domain and package identity; create a Play account | Implement protected signing, Firebase/recovery alignment and signed install/upgrade once selected |
| 3 | Confirm code/artwork/manual rights and Syncfusion entitlement or replacement | Review the dependency inventory and commercial packet; prepare applicable notices |
| 4 | Select a sending domain/provider and real test recipient; decide whether SMS stays deferred | Configure only Next, then verify invite/code/recovery receipt and retries |
| 5 | Select backup destination/encryption custodian, recovery target/budget and acceptable data-loss/recovery windows | Finish hosted DB + private-file export/restore and off-device retention acceptance |
| 6 | Name the support/incident owner and alert destination; choose crash-monitoring service/budget | Activate reviewed diagnostics/alerts and verify a controlled failure reaches the owner |
| 7 | Approve/revise the offer, price/currency, included users/storage and payment account | Start with the selected simple collection process; no charges or tiers activated yet |
| 8 | Supply legal business/contact details and select retention/export/deletion/cancellation/support terms | Complete/review the draft packet and verify the selected offboarding process |
| 9 | Complete the phone checklist below and the real recipient tests | Record actual device/build, observed result and any reproduction details |
| 10 | Select the first pilot company and obtain its workflow acceptance | Follow the prepared onboarding session; measure support effort, usage and willingness to renew |

NEXT-011 is the selected next substantial coding slice. Account setup can follow in parallel
with the phone checks. These are prerequisites and execution steps within
NEXT-009, not a competing backlog. No production release is approved by this list.

## Phone checklist for the next session

Latest previously delivered artifact: `INSTALL-Vortice-Next-Build-39.apk` in S24
Downloads (see NEXT-008 for checksum). No newer APK is delivered by this source
housekeeping itself. The subsequent NEXT-010 request produces Build 40 in Windows
Downloads; transfer and install it for CAD acceptance. Record the installed version before testing; repeat release-specific
checks on the final signed candidate later. Preserve current app data/drafts.

1. **Owner:** From equipment, create/schedule/assign work with a published
   checklist; reopen from Month on the correct day. Check spreadsheet import using
   the Android system picker and a small reviewed sample.
2. **Mechanic:** Open assigned work, start/pause labour, complete procedure steps,
   capture a real camera photo, submit; have a reviewer return one item and approve
   the correction. Verify saved evidence/history and one next recurring target.
3. **Operator:** Complete a pre-operation check with a failed step; follow the
   resulting fault into corrective work and explicit verification.
4. **Offline:** Start from ordinary connected use, disable both networks,
   force-stop/reopen, open supported cached work/manual pages, record notes/photo,
   restart again and reconnect. Confirm one upload and retained evidence.
5. **Access:** Switch accounts/companies with unsent work; confirm no previous
   company's records leak. Exercise revocation through the normal owner flow and
   reconnect; rejected evidence must remain recoverable by its owner.
6. **Notification:** With permission enabled and app closed, receive an authorized
   assignment notification and tap into the correct permitted record. Also check
   denial/re-enable and account switching. Server 'sent' is not this proof.
7. **Customer:** If provider billing is selected, prove private drafts/notes stay
   hidden, approved evidence is visible, and the customer gets the same permitted
   issued/void invoice/export. On Build 40, select CAD and verify the stored rate and
   matching PDF/XLSX total; historical invoices without CAD should show it unavailable.
8. **Usability:** Repeat the ordinary path with large text; check labels, scrolling,
   keyboard/system bars and the selected supported languages.

Record each as pass/fail/not exercised with build, role and action. User/customer
acceptance and final signed upgrade remain open even when automated checks pass.

## Build 41 delivery — September 25

Internal Android `1.20.0+41` passed guarded verification (814 tests, clean
analysis) and was installed in place on S24 `R3CX906TS9X` with the recovered Next
debug signer. All 26 existing private files were byte-identical immediately
after installation; the original install time was preserved. The app launches
and the APK is also in S24 Downloads as `Vortice-Next-Build-41.apk`.
Local artifact: `outputs/builds/vortice-next-android-debug-20260924-223621.apk`.
SHA-256: `9c145906e04cd6699f8f602f25166c4c8fff99d5880d54625949d5dc76484773`.
Receipts: `outputs/build41/upgrade.json`,
`outputs/next011/native-cad/verify-build41-final.log` and `build41.log`.

The connected PM journey exposed a real offline projection defect: completion
meter text was copied into a numeric display field before server acknowledgement.
The projection now parses it as a number without altering the durable request;
pending and acknowledged replay are regression-tested. Final connected reruns
and the remaining production/physical acceptance gates are tracked below; this
internal debug build is not a production release.

### Build 42 and web continuation — September 25

The authorized office + field companion is one Flutter web workspace (NEXT-014).
Build 42 (`1.20.1+42`) includes the shared operator-resume and permission-refresh
fixes plus browser layout/storage/export support. Guarded verification passes
with **818 tests and clean analysis**, plus two real Chromium storage tests and
two public-build configuration/security checks. Evidence:
`outputs/web/verify42.log`, `preferences-tests.log`, `build-security-tests.log`.

The S24 update succeeded with the independent signer. All 26 pre-existing
private files remained byte-identical before first launch, and install time was
preserved (`outputs/build42/upgrade.json`). APK:
`outputs/builds/vortice-next-android-debug-20260924-232030.apk`, SHA-256
`6a395532a21b8f520ed9ac91215d1ca0b0bc0872d623de67b9ed7067f407617a`.
The APK is also in phone Downloads as `Vortice-Next-Build-42.apk`.
This is an internal debug build; installation evidence does not replace
Garrett's physical workflow, camera or notification acceptance.

Connected completion receipts after Build 41 cover saved workflows, operations,
direct work, field reliability, fleet import/calendar, parts readiness, custody,
internal work and planning under `outputs/e2e/completion-20260925T*/`.
The isolated mechanic avoids other users' running timers. Every mutating suite
uses exact fixture manifests and verifies unrelated counts during cleanup.
Planning retains closed history; custody now follows the actual generated
inspection workflow. Browser evidence and remaining limits are owned by NEXT-014.

Still external: final name/domain and provider-email setup; reviewed issuer,
province and tax treatment; hosted off-device recovery proof and operating/
rights/support decisions; physical acceptance. Google Play remains deferred.

The final six-step connected checklist-builder journey and exact cleanup both
pass: `outputs/e2e/completion-20260925T061933Z/checklist_builder_workflows/`.
It covers shared/private publication, older assigned-version resume, critical
finding → corrective work → verification, PM snapshot/version independence,
next-service advancement and private evidence access denial across companies.
The harness now waits for visible save/approval acknowledgements before checking
server state, avoiding timing-dependent assertions on unacknowledged operations.

Build 43 (`1.20.2+43`) supersedes Build 42 after the real browser offline test
exposed out-of-scope checklist reference prefetch. Scope-aware preparation is
regression-tested and the mechanic browser can now reload its report offline.
French sign-out confirmation is also localized and no longer implies that
password login is mandatory. Final guarded verification passes **819 tests** with
clean analysis (`outputs/web/verify43.log`). The preserving S24 update again
kept all 26 private files and install time (`outputs/build43/upgrade.json`).
APK: `outputs/builds/vortice-next-android-debug-20260924-233035.apk`, SHA-256
`29a00cb12482828a4f74b7cd3b41f6446003f6782967bdf10bebe85b7b260d51`.
Phone Downloads contains `Vortice-Next-Build-43.apk`.

Build 44 (`1.20.3+44`) adds the final calendar search improvement and repairs
procedure-page requests from older saved snapshots by retaining their parent
publication ID. Details, browser acceptance and remaining website polish are in
NEXT-014 and NEXT-006. This supersedes the intermediate Build 43 artifact.

Final guarded verification: **821 tests, clean analysis**, including persisted
read scopes, source identity and calendar-search regressions
(`outputs/web/verify44-final.log`). Build 44 was installed with the recovered Next
signer and again preserved all 26 existing private files and install time.
APK: `outputs/builds/vortice-next-android-debug-20260924-234324.apk`, SHA-256
`d0816dd151eadcbdcb07c273bb92d16a03c123be445e79f8854737bb0b999307`.
Receipts: `outputs/build44/upgrade.json`, `settled-home.png`.
Phone Downloads contains `Vortice-Next-Build-44.apk`.

### Final Build 45 delivery — September 25

Build 45 (`1.20.4+45`) supersedes the intermediate candidates above. A rendered
browser replay exposed an unused signed-photo URL request starting even when the
photo was available in the durable local outbox. Evidence now waits for local
restore and starts a remote request only when its result will be observed; a
regression verifies local bytes render with no remote request. Browser dispatch
also avoids network attempts while the browser already reports offline.

Guarded verification passes **822 tests and clean analysis**
(`outputs/web/verify45-final.log`). The final APK was installed in place on the
S24 using the independent Next debug signer. All 26 pre-existing private files
remained byte-identical before first launch, and install time was preserved.
APK: `outputs/builds/vortice-next-android-debug-20260925-000217.apk`, SHA-256
`58e853958887fc6c0f6fac74625d9e347ef556811388672e65764ff24fa54d6f`.
Phone Downloads: `Vortice-Next-Build-45.apk`. Receipts:
`outputs/build45/upgrade.json`, `settled-home.png`.
The one office/field web workspace and final browser receipts are in NEXT-014.
The production and physical acceptance gates listed above still apply.

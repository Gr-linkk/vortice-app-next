# NEXT-009: Production-readiness housekeeping

Authorized September 14, 2026. Base: `430f7a0`, internal Build 39 (`1.18.1+39`).
Branch: `codex/production-readiness-closeout`. BACKLOG.md owns priority.

September 24 update: Garrett selected Android Google Play and Canadian general
construction, including customer invoicing for Service provider and Both.
NEXT-011 and NEXT-012 now own these release blockers; this document retains
operating closeout and earlier verification evidence. The province, pilot,
identity and final offer remain open.

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
Android-first distribution, Canadian pricing, the first customer segment and
support promises still need Garrett's selection. The proposed C$99 founding /
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
   Subscription pricing is a different decision. Choose the initial region and
   whether customer invoicing is in the pilot before changing tax rules. CAD currency support itself is implemented.
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
| 1 | Choose the first customer segment and country; confirm whether the pilot includes provider invoicing or own-equipment maintenance first | Use the pilot worksheet; scope any regional invoicing correction before selling it |
| 2 | Choose final product/business name, domain, Android distribution and package identity | Implement protected signing, Firebase/recovery alignment and signed install/upgrade once selected |
| 3 | Confirm code/artwork/manual rights and Syncfusion entitlement or replacement | Review the dependency inventory and commercial packet; prepare applicable notices |
| 4 | Select a sending domain/provider and real test recipient; decide whether SMS stays deferred | Configure only Next, then verify invite/code/recovery receipt and retries |
| 5 | Select backup destination/encryption custodian, recovery target/budget and acceptable data-loss/recovery windows | Finish hosted DB + private-file export/restore and off-device retention acceptance |
| 6 | Name the support/incident owner and alert destination; choose crash-monitoring service/budget | Activate reviewed diagnostics/alerts and verify a controlled failure reaches the owner |
| 7 | Approve/revise the offer, price/currency, included users/storage and payment account | Start with the selected simple collection process; no charges or tiers activated yet |
| 8 | Supply legal business/contact details and select retention/export/deletion/cancellation/support terms | Complete/review the draft packet and verify the selected offboarding process |
| 9 | Complete the phone checklist below and the real recipient tests | Record actual device/build, observed result and any reproduction details |
| 10 | Select the first pilot company and obtain its workflow acceptance | Follow the prepared onboarding session; measure support effort, usage and willingness to renew |

Decisions 1–3 determine the next coding slice. Account setup can follow in parallel
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

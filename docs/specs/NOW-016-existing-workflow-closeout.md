# NOW-016: Existing workflow closeout

Scope: Garrett's September 7 closeout request. Finish current workflows, preserve
the established design and EN/ES support, and package a checked internal Android
build. No new stock, purchasing, reporting, recurrence, subscription, telemetry,
iOS or redesign work. Continue the verified NOW-015 implementation.

## Acceptance

- Invoice generation retries safely; issue/void/correction rules and customer
  visibility are enforced by the server. Issued exports use frozen details.
  Issuing, sharing and recipient delivery are described separately.
- Meter, organization, provider assignment and request conversion saves cannot
  leave half an operation. Delayed readings cannot lower an accepted meter.
- Request/report text and media remain recoverable after interruption; retries
  preserve identity. Rejected and unsent work is never silently purged.
- Authoritative access changes invalidate cached records. Offline coverage and
  retention are explicit, including account switching.
- Existing notification events, routing and registration are checked. Phone
  receipt requires physical evidence, separately from server acceptance.
- Unsupported entry points/promises are removed; existing customer journeys
  retain usable loading, error, retry, permission and large-text states.
- Full guarded checks, connected journeys and APK inspection pass. No transfer
  or publication is authorized by this request.

## Release dependencies outside implementation

Final signing/identity, customer SMTP, backups including evidence-object restore,
operational monitoring and commercial setup require separate release decisions.
Physical installation, permission prompts, process-kill recovery and actual push
receipt remain physical acceptance until demonstrated on the final build.

## Evidence

Starting checkout: clean `codex/now-015-checklist-builder`, HEAD and recorded
upstream `1b2614597430f14b4a26362c94bc83d7f5a2b195`, independent origin only.
Prior results in the readiness audit are historical, not closeout verification.

## Implemented and verified

- Four closeout migrations are deployed to `hkjpojobdbbtjkhaudki`: invoice
  immutability/issue/void, atomic meter/org saves, atomic provider saves, and
  durable evidence submission. Recovery/visibility rules are in decision 0014.
- Invoice screens and exports expose issue, void, correction and payment with
  EN/ES wording. PDF exports paginate long invoices using bundled licensed fonts;
  PDF/Excel use frozen details and explicit parts adjustments. Long EN/ES export
  tests pass; Spanish first/final pages were rendered and visually inspected.
- Request/report bundles preserve text, photos and signatures through lost
  acknowledgements, restart and rejected uploads. The queue offers correction
  without overwriting another saved draft. Duplicate taps are guarded.
- Offline read caches have a 24-hour maximum age, reject permission-denied
  fallback and remove missing records on successful list refresh. Drafts and
  rejected/pending operations survive account changes and cache cleanup.
- The consultation entry was already retired in the verified baseline; its
  stale route redirects to the role dashboard. No new response service was added.
  Existing request/invoice wording and recovery errors were localized without
  changing the app's visual design.
- Guarded `scripts/verify.cmd`: clean analysis, **474 passed, 204 existing skips**
  (`outputs/NOW-016-verification.log`). Database contracts: all **17 local and
  17 hosted suites** passed; hosted logs are split between
  `NOW-016-hosted-contracts.log` and `NOW-016-hosted-tail.log` after correcting a
  test assertion that counted unrelated real-device deliveries.
- Eight connected test files exercised custody, direct corrective work, field
  recovery, internal work, operator checks, planning, saved provider workflows
  and six-account navigation. **130 route checks** passed. The first run had one
  premature completion assertion; after awaiting the controller's save, the
  complete saved-workflow test passed, including issue/void/correction/payment.
  Logs: `outputs/NOW-016-connected.log`, `outputs/NOW-016-saved-final.log`.
- Cleanup removed eight exact fixture assets and 24 evidence objects; unrelated
  record counts were preserved (`outputs/NOW-016-cleanup.log` and
  `outputs/NOW-010-cleanup.json`). The privileged fixture transaction temporarily
  disables only the invoice immutability trigger and restores it before commit.
- Notifications: a fresh aggregate snapshot found **one enabled push device,
  seven sent deliveries, one cancelled delivery, 1,440 successful worker runs
  over 24 hours**. Garrett confirmed receiving phone notifications. Event-category
  titles are deployed and all three payload tests pass. These observations do
  not independently prove receipt/tap behavior for every event on Build 19.

## Checked internal build

Version **1.9.1+19**, ARM64 debug APK:
`outputs/builds/vortice-next-android-debug-20260907-064902.apk`

SHA-256:
`e0c14d83cd825e737c9fbb7b5fa69137dc8332588e4840fc65a5c396f13665ec`

APK inspection confirms `com.example.vortice_app_next`, version code/name and
in-app version, the dedicated Next signing certificate, Supabase/Firebase
identities, messaging service and recovery callback. The packaged copy's hash
matches the inspected build. Build log: `outputs/NOW-016-build.log`; inspection:
`outputs/NOW-016-apk.txt`, `outputs/NOW-016-signature.txt`.
No transfer, installation or publication was performed.

The build succeeds with Flutter warnings about future built-in Kotlin migration
for the Android project, `share_plus` and `shared_preferences_android`. This is
a future toolchain-upgrade dependency, not a failed current build.

## Physical acceptance still required

After Garrett authorizes installation of the exact APK above:

1. On the Samsung S24, confirm version 1.9.1+19. Test EN and ES with large text;
   deny then allow camera, photo and notification permissions and verify retries.
2. As operator, submit a problem with a photo; kill the process during upload,
   reopen and retry. Verify one original request with its text and photo.
3. As manager, assign the problem. As mechanic, record labour, parts, diagnosis,
   photos and signature; go offline and kill/reopen during submission. Reconnect
   and verify one report with all evidence and no duplicate labour/parts.
4. Return the report for correction; recover and correct it, then approve.
   Verify history and the intended component's next-service reading. Complete a
   provider work order, generate/issue/export, void with reason, correct and pay.
5. Close the app and trigger assignment, urgent fault and returned-report events
   separately. Confirm category titles and notification taps open the permitted
   inbox/detail. Repeat with notifications denied, then enabled. No synthetic
   phone events were sent solely to claim this acceptance.
6. Switch accounts with cached details and pending work. Verify no other company
   data appears and switching back retains unsent work. Revoke access remotely,
   reconnect and verify the record disappears while rejected evidence remains
   recoverable. Also test an expired cache after more than 24 hours offline.

Final production signing/application identity, customer SMTP and reset-email
delivery, database plus evidence restore drills, operational monitoring and
commercial configuration remain separate production-release dependencies.

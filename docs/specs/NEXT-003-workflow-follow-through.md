# NEXT-003 — Workflow polish and field verification

Authorized September 12, 2026, following internal Build 29. Continue on the
verified independent `codex/kanban-workflows` branch.

Status: all five follow-ups completed September 12, 2026. Final internal
Build 33 (`1.16.4+33`) is installed on the S24 with existing data preserved.

| Item | Outcome | Status |
| --- | --- | --- |
| 1 | New demo roles first, older profiles collapsed, current company/role clear | Implemented; native S24 picker checked and tests pass, including 320 px at 200% text |
| 2 | Create, assign, perform, return, correct, approve and invoice one job | Native S24 demo journey passed; Build 33 return, correction, approval and issued invoice confirmed in provider and customer views |
| 3 | Provider evidence capture survives offline interruption and reopening | Build 32 S24 restart, cached Work, recovered report and unsent photo preview passed with both networks disabled; reconnect and submission passed |
| 4 | Shared execution/evidence rules reduce drift between workflow paths | Shared report readiness and immutable evidence helpers implemented |
| 5 | Repeatable Work hub performance check with representative populated data | Local positive and historical regression probes pass; CI job added |

Provider work starts from its authorized work order and frozen procedure.
Answers, meter readings and captured photos stay account-owned on this device.
Server submission checks current permission/revision and retains retry identity.
Approval, billing, assignments and permission changes still require connectivity.
Use shared production helpers where contracts match; preserve workflow-specific
RPCs and private/customer report boundaries.

Acceptance includes native narrow/large-text account selection, offline evidence
reopen and retry, stale account/revoked access protection, complete saved job
transitions and repeatable populated performance checks. Keep automated Flutter,
hosted SQL, actual Android execution and human acceptance explicitly separate.

No account deletion, original-app changes, new chat product, email/SMS setup or
visual redesign is included. The Build 29 receipt remains historical evidence.

The offline restart test also exposed a scoped-read dependency race: observing
membership's intermediate loading state could invalidate the awaited provider
work context. Service reads now await resolved membership before fetching their
scoped context, retaining account and permission invalidation.

The first physical restart on Build 30 exposed a second delay that the local
server-stop test did not: service-detail enrichment had no request timeout.
Android could keep retrying after both networks were disabled, preventing the
Work list from reaching its existing cache. Each page now has the same six-second
read limit as other workspace reads. A stalled-transport regression verifies
that the warmed asset, component and worker details return within 15 seconds.
This correction is packaged as Build 31; Build 30 remains an intermediate receipt.

Build 31's repeated phone test exposed another refresh dependency: every photo
outbox update restarted hosted Work hub and service enrichment reads. Build 32
separates cached/server planning from the local operation projection. A widget
regression first reproduced the extra fetch, then verified repeated photo retries
keep Work readable, local work actions still update progress, and explicit
Refresh still fetches current server data. Physical Build 32 acceptance passed:
the Work list reached its cache in the first 15-second check. A fresh fourth
test photo was added with both networks disabled, the app was force-stopped,
and the report and photo reopened while the header still showed one pending
upload. Offline submission was blocked with a clear message. Reconnecting
uploaded the evidence and the report was submitted through the native UI.

The return-for-correction step then exposed a closing-sheet lifecycle defect:
text controllers were disposed while the modal exit animation still used them.
The return was saved, but Flutter rendered an error. Build 33 gives the sheet
ownership of its controllers until unmount. A new widget test reproduced the
disposed-controller error before the fix and passes afterward. This shared form
also handles provider blockers, starting meters and invoice charge entry.

## Final delivery and phone evidence

- Source: `dfaf7272a5427bd6c5aaf2ce9624274cdd2409e9`, with the earlier follow-up
  commits retained on `codex/kanban-workflows` and pushed only to Next.
- Full guarded verification: **726 tests passed**, code generation and analysis
  passed. Logs: `outputs/kanban/next003-build33-verify.log` and
  `outputs/kanban/next003-build33.log`. APK inspection verifies package,
  signing certificate, dedicated Next backend/Firebase and bundled features.
- APK: `outputs/builds/INSTALL-Vortice-Next-Build-33.apk`, **139,034,653 bytes**.
  SHA-256: `f1eefeb31e90b1adeba77a1452262a8dc9a00d9de55e9140f14ef2b11145a349`.
  Installed with `adb install -r` and saved in S24 Downloads; receipts:
  `outputs/build33-build-verified.json`, `outputs/build33-phone-delivery.json`.
  The separate `outputs/build33-native-acceptance.json` records the completed
  phone checks and hashes their native screenshots/XML.
- Native fixture: `NEXT003 S24 pressure verification`, work ID
  `5b529c9b-b916-4248-9fed-ac2041446497`, Demo Truck 01. The original **62000 km**
  reading is unchanged. Recorded labour is 8m06s (0.14 h when rounded for billing).
- The three attached checklist answers and four synthetic gallery photos
  survived the workflow. Build 32 proved the fresh pending-photo restart;
  Build 33 proved the repaired return-sheet exit and invoice entry. The final
  repair includes the requested pressure result, and the review correction
  retains prior answers and evidence.
- Customer report visibility was checked before and after approval on the
  actual phone. The pending report was hidden. The completed view exposes the
  approved report, three answers, four photo previews and issued invoice,
  without provider internal labour/cost controls.
- Invoice `INV-20260912-D5FAE54FA70E` is **issued**, for **0 USD / 0 MXN**,
  against the explicitly labeled demo record. It was not marked paid.
- Read-only hosted verification confirms the same work/report/invoice IDs in
  both company views and successfully retrieves all four evidence objects
  under each account's permissions. Receipt:
  `outputs/next003-phone/server-work-final-receipt.json`.
- Native XML/PNG evidence is under `outputs/next003-phone/`: `109` shows the
  recovered unsent photo and pending upload, `110` the offline submission gate,
  `123`/`127` the account picker, `126` the private pre-approval customer view,
  `129` the successful Build 33 return, and `137`–`139` the completed customer
  report, invoice and photo. Wi-Fi/mobile data are restored and rotation is free.

This is an automated native-phone demo journey, not Garrett's acceptance of
every role or production workflow. Camera capture, offline manual source pages,
recurrence, parts, and closed-app notifications retain their separate NEXT-002
checks. Email/SMS setup remains deferred; live agent-host/API checks remain
external. No additional implementation is implied by those remaining checks.

## Performance regression evidence

The performance fixture contains 340 assets, 1,500 jobs and 340 plans. It checks
three samples for four roles under forced generic query plans, a 3-second ceiling
and a same-machine isolation budget. Current medians were about 471 ms for the
provider owner, 491 ms for the fleet owner, 419 ms for the assigned mechanic and
72 ms for an unrelated company. Reinstating the historical slow function in the
disposable test database failed the isolation budget (760 ms versus 609 ms).
This is local repeatable regression evidence, not hosted load or remote CI proof.
Logs: `outputs/kanban/next003-performance-final.log` and
`outputs/kanban/next003-performance-negative-final.log`.

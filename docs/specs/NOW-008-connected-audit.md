# NOW-008 connected workflow audit

Requested on 2026-09-06: exercise the features delivered in Builds 8–10 through
real screens, submit and remove test data, inspect persistence, and fix confirmed
problems. Source baseline: `d99d0db`. This audit targets only Vortice Next.

## Method and scope

The production Flutter app ran against authenticated Next services in a local
browser. A disposable entry point supplied the installed Drift library's web
SQLite adapter; screens, repositories, authorization, RPCs and storage were real.
The adapter was necessary because the Android-oriented default database
constructor does not configure web support. It is not part of the APK.

All new operational records were clearly marked `E2E-008`. No original Vortice
repository, service, deployment, or data was used. Actions were verified against
visible state and saved values; a click alone was not counted as success.

## Connected journeys exercised

| Area | Observed result |
| --- | --- |
| Assets and planning | Created a vessel, engine and generator; required-field errors, asset edit, explicit component plans and due meters verified. |
| Internal execution | Manager created and assigned service; mechanic started/paused labour, blocked for parts, resumed, added/removed/replaced parts. Persisted parts, status, costs and history checked. |
| Maintenance reports | Required notes and stopped-labour validation; draft/reopen, evidence upload/read, remove/keep/discard, submit, manager return, correction/resubmit and approval exercised. |
| Service accounting | Approval advanced only the selected generator plan. Reopen/reapprove retained the first service baseline and did not advance it a second time. Follow-up job and assignment verified. |
| Faults and availability | Required fault data, urgency, acknowledge, assign, start, progress, review, resolve, reopen and dismiss exercised. Availability remained an explicit action; changing outage type preserved its original start. |
| Handover | Company-only handover, isolation state, next steps, manager mention, private photo, inbox destination and named acknowledgment exercised. |
| History and fleet | Actual removed-part details/search and source links inspected; waiting-for-parts and waiting-for-people lists matched the created work. Export and broader filter/pagination contracts supplemented live checks. |
| Provider requests | Client request validation and submission; owner acceptance into a prefilled provider order, assignment, edit and technician start verified. |
| Provider reports | Five-field validation, saved/reopened reports, retained draft, blank/drawn/cleared signature, second report on the same job, successful sync, completion and client read-only view verified. |
| Roles | Company manager, mechanic, provider owner, technician, operator and second client were exercised. The second client's report list excluded the audit reports; the operator had the expected restricted navigation. |
| Operator checks | Empty submission initially saved incorrectly. Retest rejected it, then a complete 20-item checklist including N/A saved and produced a 20-answer history snapshot. |

Managed-checklist required-photo variants, shared/provider discussion boundaries,
all history filter combinations and fleet pagination have SQL/widget coverage;
they were not each repeated as a distinct live browser journey in this audit.
This is broad connected coverage, not proof that every possible button/state,
network interruption, legacy screen or physical-device behavior is correct.

## Confirmed defects corrected

1. Completed labour used truncated milliseconds, causing a one-cent difference
   from the server. It now uses microseconds; the actual captured session times
   reproduce and protect the corrected rounding.
2. History exposed raw cost/hour precision. Costs and hours now use appropriate
   display precision in English and Spanish.
3. Reapproval incorrectly promised another service-plan advancement. Its message
   now describes the preserved baseline; first approval retains its own message.
4. Completed internal reports were absent from legacy asset/report indexes.
   The index combines authorized provider and internal results and opens each
   report in its owning workflow. It does not relax managed-job RLS.
5. A fresh report cache could return null despite a remote report. Direct reads
   now fetch/cache it correctly. Asset refresh also preserves a pending edit
   when its associated work order has not yet been cached.
6. Provider report dates lacked UTC offsets. New writes use UTC and display local
   dates consistently; historical timestamps have not been rewritten.
7. Private signatures were displayed using public URLs. Report images now
   resolve object paths and old URLs to short-lived signed URLs, with retry.
8. The database's global one-report-per-job constraint prevented a second
   provider report from syncing. Provider jobs now support report history;
   managed jobs retain one canonical report and transactional approval.
9. Completed provider reports depended on reading provider-only work-order rows.
   A checked report RPC provides authorized report/asset metadata without exposing
   internal work-order fields. Clients can read their completed reports and media;
   operator and other-company denial contracts remain enforced. Report/photo
   providers refresh with account changes; read-only clients neither upload
   another user's pending work nor reuse an unverified device cache.
10. Negative and nonfinite provider labour/meter values could be saved through
    forms. Create/edit/log-hours validation now rejects them and preserves input.
11. Operator submission allowed missing answers and wrote UI response strings
    that violated baseline database constraints. It now validates all answers
    before writing and maps pass/monitor/action/N/A to the existing schema.
12. Operator photos were never submitted and were discarded with the draft.
    Unsupported photo submissions now stop before writing and retain the draft,
    with English/Spanish feedback. This prevents loss; it does not implement
    daily-checklist photo upload support.

## Database change

`20260906062000_provider_report_history.sql` is active on
`hkjpojobdbbtjkhaudki` only. It adds a derived managed-job report discriminator,
keeps the managed approval conflict target unique, adds scoped completed-provider
report reads, and keeps the media buckets private. The populated upgrade test
verified existing report identifiers, content, timestamps and immutable history,
then exercised an existing managed draft through submission and approval.

All five local and hosted rollback suites passed: company maintenance, faults
and availability, fleet coordination, signup-role boundary and provider reports.
The upgrade fixture passed separately. No deployed migration was subsequently
rewritten.

## Verification and limits

- Full repository verification: guardrails, generation, clean Flutter analysis,
  **380 passing tests and 204 pre-existing skips**. No new skips were introduced.
  The outer Windows redirection wrapper reported a NativeCommandError for the
  informational `Running build hooks` stderr text after the inner verifier had
  printed `Project verification passed`; the analyzer and test outcomes passed.
- Subsequent focused analysis was clean; 29 version/navigation, checklist and
  report-cache tests passed after the last focused edits.
- English/Spanish report lists were rendered and visually checked at 320 logical
  pixels and 1.5 text scale. Export-button coverage verified all CSV pages, the
  filename, MIME type and actual native-plugin handoff. The OS share recipient
  itself was substituted in that test.
- No connected Android device/emulator was available for interactive inspection.
  Installation, native camera permissions, OS share-sheet interaction, physical
  keyboard/insets and interrupted mobile-network behavior remain device checks.
- The inherited operator submission still uses separate run/response/history
  writes. The failed pre-fix trials left incomplete runs in the disposable
  fixture. Transactional retry/idempotency and daily-checklist photo uploads are
  follow-up work, not claimed as fixed by the connected happy-path test.
- After Garrett explicitly authorized the cross-company check, both client
  sessions were authenticated concurrently. The owning client could still read
  the synthetic report after the other client signed in; the other client
  received zero rows for that exact report. In the running app, the other
  client's direct report URL displayed `Not found.` SQL denial and the filtered
  report list also passed.

## Evidence and fixture cleanup

Detailed execution: `outputs/NOW-008-e2e-audit.md`; verification:
`outputs/NOW-008-verification.log`; narrow renders:
`outputs/screenshots/audit/`; build evidence:
`outputs/NOW-008-build-notes.md`. Outputs are local ignored artifacts.

After the access check, guarded cleanup removed disposable vessel
`f1c29b2f-c31d-4b81-ad50-0ee37002157b`, its three work orders, reports and linked
audit records. The three exact test objects in coordination attachments,
maintenance evidence and signatures were deleted through the Storage API and
their absence verified before record removal. A transaction checked the fixture
identity and preserved unrelated asset, work-order and report counts. Final
queries found no fixture records. The local cleanup manifest is
`outputs/NOW-008-cleanup-manifest.json`; simultaneous-session evidence is
`outputs/NOW-008-simultaneous-clients.log`. Temporary web adapter assets were
removed and the browser server stopped.

Build `1.4.1+11` was delivered to Samsung Downloads as
`INSTALL-Vortice-Next-Build-11.apk`. Package/signing/ARM64 checks, the phone's
SHA-256 checksum and media indexing passed. Installation remains a device step.
